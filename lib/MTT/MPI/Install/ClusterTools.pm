#!/usr/bin/env perl
#
# Copyright (c) 2007 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::MPI::Install::ClusterTools;
my $package = ModuleName(__PACKAGE__);

use strict;
use Data::Dumper;
use MTT::DoCommand;
use MTT::Messages;
use MTT::Values;
use MTT::FindProgram;
use MTT::Common::GNU_Install;
use MTT::Files;
use MTT::Util;
use Cwd;
use POSIX qw/strftime/;
use File::Spec;

#--------------------------------------------------------------------------

# Global Solaris package variables
my $release_number;
my $product_version;
my $package_name_prefix;

sub Install {
    my ($ini, $section, $config) = @_;
    my $x;

    # Prepare $ret
    my $ret;
    $ret->{test_result} = MTT::Values::FAIL;
    $ret->{exit_status} = 0;
    $ret->{installdir} = $config->{installdir};
    $ret->{bindir} = "$ret->{installdir}/bin";
    $ret->{libdir} = "$ret->{installdir}/lib";

    # If we are not making packages, install_dir and staging_dir are the same.
    # Otherwise, staging area is installdir/configure_prefix.
    my $staging_dir = $config->{installdir};
    my $wrapper_rpath = $config->{installdir};

    # Process clustertools input parameters
    my $do_ctinstall = Value($ini, $section, "clustertools_do_ctinstall");
    my $build_number = Value($ini, $section, "clustertools_build_number");
    my $create_packages = Value($ini, $section, "clustertools_create_packages");
    my $svn_r_number = Value($ini, $section, "clustertools_svn_r_number");
    my $do_autogen = Value($ini, $section, "clustertools_do_autogen");
    my $skip_configure = Value($ini, $section, "clustertools_skip_configure");
    my $configure_prefix = Value($ini, $section, "clustertools_configure_prefix");

    # Process global clustertools input parameter(s)
    $release_number = Value($ini, $section, "clustertools_release");
    $product_version = Value($ini, $section, "clustertools_product_version");
    $package_name_prefix = Value($ini, $section, "clustertools_package_name_prefix");

    # Grab the SVK "r" number
    my $svk_r_number = $config->{module_data}->{r};

    # Update the version file
    my $greek = "r${svn_r_number}-ct${release_number}b${build_number}r${svk_r_number}";
    &_update_version_file($greek, "VERSION");

    # Update the openmpi-mca-params.conf file
    &_update_openmpi_mca_params_conf("opal/etc/openmpi-mca-params.conf");

    # Get some OMPI-module-specific config arguments
    my $tmp;
    $tmp = Value($ini, $section, "clustertools_make_all_arguments");
    $config->{make_all_arguments} = $tmp
        if (defined($tmp));

    # JMS: compiler name may have come in from "compiler_name" in
    # Install.pm. So if we didn't define one for this module, use the
    # default from "compiler_name".  Note: to be deleted someday
    # (i.e., only rely on this module's compiler_name and not use a
    # higher-level default, per #222).
    $tmp = Value($ini, $section, "clustertools_compiler_name");
    $config->{compiler_name} = $tmp
        if (defined($tmp));
    MTT::Util::is_valid_compiler_name($section, $config->{compiler_name});

    # JMS: Same as above
    $tmp = Value($ini, $section, "clustertools_compiler_version");
    $config->{compiler_version} = $tmp
        if (defined($tmp));

    $tmp = Value($ini, $section, "clustertools_configure_arguments");
    $tmp =~ s/\n|\r/ /g;
    $config->{configure_arguments} = $tmp
        if (defined($tmp));

    $tmp = Logical($ini, $section, "clustertools_make_check");
    $config->{make_check} = $tmp
        if (defined($tmp));

    # Hack to set the correct runtime dependency path (-R) for root packages.
    #
    # TODO: There must be a way to change the rpath of the already-built
    # libraries that would not require us to rebuild from scratch. Maybe some
    # libtool magic is needed? The -R/path args seem to be hard-coded into the
    # resulting .la files. How can we recreate those .la files so that the
    # libtool invocations use -R/opt, instead of -R/workspace?
    if ($create_packages) {
        $config->{make_install_arguments} = "DESTDIR=$config->{installdir}";
        $staging_dir = "$config->{installdir}/$configure_prefix";
        $wrapper_rpath = $configure_prefix;
    }

    # Run autogen.sh
    $x = MTT::DoCommand::Cmd(1, "./autogen.sh") if ($do_autogen);

    # Run configure / make all / make check / make install
    my $configure_arguments = $config->{configure_arguments};

    # Handle a scalar or an array
    if (ref($configure_arguments) eq "") {
        my $tmp = $configure_arguments;
        undef $configure_arguments;
        push(@$configure_arguments, $tmp);
    }

    my $i = 0;
    foreach my $_configure_arguments (@$configure_arguments) {

        # Note: in the case of creating packages, we explicitly set --prefix
        # ourselves in &Sun::get_configure_arguments()
        my $gnu = {
            configdir => $config->{configdir},
            configure_arguments => $_configure_arguments,
            vpath => "no",
            installdir => $config->{installdir},
            bindir => $config->{bindir},
            libdir => $config->{libdir},
            make_all_arguments => $config->{make_all_arguments},
            make_install_arguments => $config->{make_install_arguments},
            make_check => $config->{make_check},
            stdout_save_lines => $config->{stdout_save_lines},
            stderr_save_lines => $config->{stderr_save_lines},
            merge_stdout_stderr => $config->{merge_stdout_stderr},
            restart_on_pattern => $config->{restart_on_pattern},
        };

        # Do a make clean every build, just in case
        $gnu->{make_clean} = 1;

        # Optionally skip configure
        $gnu->{skip_configure} = 1 if ($skip_configure);

        my $install = MTT::Common::GNU_Install::Install($gnu);
        foreach my $k (keys(%{$install})) {
            $ret->{$k} = $install->{$k};
        }

        # If either of the two builds fails, the entire build has failed
        return $ret
            if (exists($ret->{fail}));

        $i++;
    }

    # Create wrapper data files
    my $wrapper_destdir = "$staging_dir/share/openmpi";
    &_create_wrapper_data_files($wrapper_destdir, $wrapper_rpath, $greek);

    # Fetch Install_Utilities using Teamware
    my $teamware_file_list_program = Value($ini, $section, "clustertools_teamware_file_list_program");
    my $install_gate_path = Value($ini, $section, "clustertools_install_gate_path");

    # Setup the Installer, if we pointed at one
    my $installer_dir;
    if ($install_gate_path) {
        MTT::Files::teamware_bringover($teamware_file_list_program, $install_gate_path, "install", ".");

        my $save_cwd = File::Spec->rel2abs(cwd());
        MTT::DoCommand::Chdir("install");

        # Build the Install_Utilities (OMPIompiat package)
        my $cmd = "make clean release";

        my $x = MTT::DoCommand::Cmd(1, $cmd);

        if (0 != $x->{exit_status}) {
            Warning("$package: Error in building the Installer: '$cmd'\n");
        } else {

            # Figure out where the installer is
            # (We need to do this because the Installer workspace Makefile has
            # a bizarre package staging area of its own)
            ($installer_dir) = MTT::Files::FindName(cwd(), "Install_Utilities");
        }

        MTT::DoCommand::Chdir($save_cwd);
    }

    # Create Solaris packages using pkgproto and pkgmk
    if ($create_packages) {
        my $install_dir     = $config->{installdir};
        my $examples_dir    = "$config->{abs_srcdir}/examples";
        my $destination_dir = "$install_dir/../Product";

        # Make a place for the packages to sit
        MTT::Files::mkdir($destination_dir);

        # Copy the following two directories to the staging area:
        #   * examples directory (OMPIomsc package)
        #   * Install_Utilities directory (OMPIomiat package)
        MTT::DoCommand::Cmd(1, "cp -r $examples_dir $staging_dir");
        MTT::DoCommand::Cmd(1, "cp -r $installer_dir $staging_dir");

        # Install Utilities for boot-strapping
        MTT::DoCommand::Cmd(1, "cp -r $installer_dir $destination_dir");

        create_packages($staging_dir, $destination_dir);
    }

    # Install the packages using the installer
    if ($do_ctinstall) {
        _do_ctinstall($ini, $section, $config);
    }

    # Set which bindings were compiled
    $ret->{c_bindings} = 1;
    Debug("$package: Have C bindings: 1\n");
    my $func = \&MTT::Values::Functions::MPI::OMPI::find_bindings;
    $ret->{cxx_bindings} = &{$func}($ret->{bindir}, $ret->{libdir}, "cxx");
    Debug("$package: Have C++ bindings: $ret->{cxx_bindings}\n");
    $ret->{f77_bindings} = &{$func}($ret->{bindir}, $ret->{libdir}, "f77");
    Debug("$package: Have F77 bindings: $ret->{f77_bindings}\n");
    $ret->{f90_bindings} = &{$func}($ret->{bindir}, $ret->{libdir}, "f90");
    Debug("$package: Have F90 bindings: $ret->{f90_bindings}\n");

    # Set bitness (EAM: 32-bit and 64-bit should both be validated)
    $ret->{bitness} = "32,64";

    # All done
    Debug(">> $package: returning successfully\n");
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";

    return $ret;
}

sub _do_ctinstall {
    my ($ini, $section, $config) = @_;
    my ($x, $ret);

    # Process clustertools input parameters
    my $connection_method = Value($ini, $section, "clustertools_ctinstall_connection_method");
    my $activate = Value($ini, $section, "clustertools_ctinstall_activate");

    if ($activate) {
        $activate = "-a";
    }

    my $bindir = "$config->{abs_srcdir}/Product/Install_Utilities/bin";
    my $installer = "ctinstall";
    my $ctinstall = "$bindir/$installer";

    # Find sudo
    my $sudo = FindProgram("sudo");
    if (!defined($sudo)) {
        Error("$package: requires 'sudo'.\n");
        return undef;
    }

    my $want_unique = 1;
    my $hosts = &MTT::Values::Functions::env_hosts($want_unique);

    # Set package location of packages
    my $basedir = "/opt/SUNWhpc";

    # Deactivate packages
    my $ctdeact = "$basedir/bin/Install_Utilities/bin/ctdeact";
    my $x;
    if (-x $ctdeact) {
        $x = MTT::DoCommand::Cmd(1, "$sudo $ctdeact -n $hosts -r $connection_method");
    }

    # Install packages using ctinstall
    $x = MTT::DoCommand::Cmd(1, "$sudo $ctinstall $activate -n $hosts -r $connection_method");

    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        Verbose("$package: $installer failed: $@\n");
        return undef;
    }

    $ret->{installdir} = $basedir;
    $ret->{bindir} = "$ret->{installdir}/bin";
    $ret->{libdir} = "$ret->{installdir}/lib";

    return $ret;
}

# Update the VERSION file
sub _update_version_file {
    my ($greek) = @_;

    # Read in the default VERSION file
    my $contents = MTT::Files::Slurp("./VERSION");

    # Splice in the greek value and direct configure to
    # not dynamically grab the SVN r #
    $contents =~ s/(\ngreek)=.*/$1=$greek/;
    $contents =~ s/(\nwant_svn)=.*/$1=0/;
    $contents =~ s/(\nsvn_r)=.*/$1=0/;

    # Write changed file out
    MTT::Files::SafeWrite(1, "./VERSION", $contents);
}

# Append some special ClusterTools settings to mca_params.conf
sub _update_openmpi_mca_params_conf {
    my ($file) = @_;

    my $contents = MTT::Files::Slurp($file);
    my $str = "
# Do not print message when uDAPL NIS is not found
btl_base_warn_component_unused = 0

# Enable process address data to be sent by connection private data mechanism
btl_udapl_conn_priv_data = 1

# Do not print messages mca load errors
mca_component_show_load_errors = 0
";

    my $ret = MTT::Files::SafeWrite(1, $file, $contents . $str);

    return $ret;
}

# Arguments:
#   1. Where we are writing the files
#   2. -R <PATH> to be used within the wrapper data files
sub _create_wrapper_data_files {
    my ($destdir, $installdir, $version) = @_;
    Debug("_create_wrapper_data_files: got @_\n");

    my @compilers = (
        "CC",
        "c++",
        "cc",
        "cxx",
        "f77",
        "f90",
    );

    # Setup architecture dependent labels (for directories) and compiler args
    my $arch = `uname -p`;
    chomp $arch;
    my $lib_label_for_64_bit;
    my $include_label_for_64_bit;
    my $compiler_args;
    if ($arch =~ /sparc/i) {
        $lib_label_for_64_bit = "sparcv9";
        $include_label_for_64_bit = "v9";
        $compiler_args = "-xarch=v9;-xarch=v9a;-xarch=v9b;-xarch=native64;-xarch=generic64;-xtarget=native64;-xtarget=generic64;";
    } elsif ($arch =~ /i386/i) {
        $lib_label_for_64_bit = "amd64";
        $include_label_for_64_bit = "amd64";
        $compiler_args = "-xarch=amd64;-xarch=amd64a;-xarch=native64;-xarch=generic64;-xtarget=native64;-xtarget=generic64;";
    } else {
        $lib_label_for_64_bit = "unknown";
        $include_label_for_64_bit = "unknown";
    }

    my $project = "Open MPI";
    my $project_short = "OMPI";
    my $preprocessor_flags = "";
    my $compiler_flags = "";
    my $required_file = "";

    # Prepare a structure containing all the wrapper data
    my $wrapper_data;

    $wrapper_data->{"cc"}->{language}  = "C";
    $wrapper_data->{"CC"}->{language}  = "C++";
    $wrapper_data->{"c++"}->{language} = "C++";
    $wrapper_data->{"cxx"}->{language} = "C++";
    $wrapper_data->{"f77"}->{language} = "Fortran 77";
    $wrapper_data->{"f90"}->{language} = "Fortran 90";

    $wrapper_data->{"cc"}->{underlying_compiler}  = "cc";
    $wrapper_data->{"CC"}->{underlying_compiler}  = "CC";
    $wrapper_data->{"c++"}->{underlying_compiler} = "CC";
    $wrapper_data->{"cxx"}->{underlying_compiler} = "CC";
    $wrapper_data->{"f77"}->{underlying_compiler} = "f77";
    $wrapper_data->{"f90"}->{underlying_compiler} = "f95";

    $wrapper_data->{"cc"}->{compiler_env}  = "CC";
    $wrapper_data->{"CC"}->{compiler_env}  = "CXX";
    $wrapper_data->{"c++"}->{compiler_env} = "CXX";
    $wrapper_data->{"cxx"}->{compiler_env} = "CXX";
    $wrapper_data->{"f77"}->{compiler_env} = "F77";
    $wrapper_data->{"f90"}->{compiler_env} = "FC";

    $wrapper_data->{"cc"}->{compiler_flags_env}  = "CFLAGS";
    $wrapper_data->{"CC"}->{compiler_flags_env}  = "CXXFLAGS";
    $wrapper_data->{"c++"}->{compiler_flags_env} = "CXXFLAGS";
    $wrapper_data->{"cxx"}->{compiler_flags_env} = "CXXFLAGS";
    $wrapper_data->{"f77"}->{compiler_flags_env} = "FFLAGS";
    $wrapper_data->{"f90"}->{compiler_flags_env} = "FCFLAGS";

    $wrapper_data->{"cc"}->{extra_includes}  = "openmpi";
    $wrapper_data->{"CC"}->{extra_includes}  = "openmpi";
    $wrapper_data->{"c++"}->{extra_includes} = "openmpi";
    $wrapper_data->{"cxx"}->{extra_includes} = "openmpi";
    $wrapper_data->{"f77"}->{extra_includes} = "";
    $wrapper_data->{"f90"}->{extra_includes} = "";

    my $common_libs = "-lmpi -lopen-rte -lopen-pal -lsocket -lnsl -lrt -lm -ldl";
    $wrapper_data->{"cc"}->{libs}  = "$common_libs";
    $wrapper_data->{"CC"}->{libs}  = "$common_libs -lmpi_cxx";
    $wrapper_data->{"c++"}->{libs} = "$common_libs -lmpi_cxx";
    $wrapper_data->{"cxx"}->{libs} = "$common_libs -lmpi_cxx";
    $wrapper_data->{"f77"}->{libs} = "$common_libs -lmpi_f77";
    $wrapper_data->{"f90"}->{libs} = "$common_libs -lmpi_f77 -lmpi_f90";

    $wrapper_data->{32}->{includedir} = "$installdir/include";
    $wrapper_data->{64}->{includedir} = "$installdir/include/$include_label_for_64_bit";
    $wrapper_data->{32}->{libdir} = "$installdir/lib";
    $wrapper_data->{64}->{libdir} = "$installdir/lib/$lib_label_for_64_bit";
    $wrapper_data->{32}->{compiler_args} = "";
    $wrapper_data->{64}->{compiler_args} = $compiler_args;
    $wrapper_data->{32}->{linker_flags} = "-R/opt/mx/lib -R$installdir/lib";
    $wrapper_data->{64}->{linker_flags} = "-R/opt/mx/lib/$lib_label_for_64_bit -R$installdir/lib/$lib_label_for_64_bit";

    # For mpif90, point to mpi.mod using the -M flag
    $wrapper_data->{"f90"}->{module_option} = "-M";

    # Template for the wrapper data files
    my $template = "#
# default / 32 bit compilations block below
#
compiler_args=%s

project=$project
project_short=$project_short
version=$version
language=%s
compiler_env=%s
compiler_flags_env=%s
compiler=%s
module_option=%s
extra_includes=%s
preprocessor_flags=$preprocessor_flags
compiler_flags=$compiler_flags
libs=%s
linker_flags=%s
required_file=$required_file
includedir=%s
libdir=%s

#
# 64 bit compilations block below
#
compiler_args=%s

project=$project
project_short=$project_short
version=$version
language=%s
compiler_env=%s
compiler_flags_env=%s
compiler=%s
module_option=%s
extra_includes=%s
preprocessor_flags=$preprocessor_flags
compiler_flags=$compiler_flags
libs=%s
linker_flags=%s
required_file=$required_file
includedir=%s
libdir=%s
";

    foreach my $prefix ("mpi", "opal", "orte") {
        foreach my $compiler (@compilers) {

            my @top_params = (
                $wrapper_data->{$compiler}->{language},
                $wrapper_data->{$compiler}->{compiler_env},
                $wrapper_data->{$compiler}->{compiler_flags_env},
                $wrapper_data->{$compiler}->{underlying_compiler},
                $wrapper_data->{$compiler}->{module_option},
                $wrapper_data->{$compiler}->{extra_includes},
                $wrapper_data->{$compiler}->{libs},
            );

            my $contents = sprintf($template,

                                    # 32-bit
                                    $wrapper_data->{32}->{compiler_args},
                                    @top_params,
                                    $wrapper_data->{32}->{linker_flags},
                                    $wrapper_data->{32}->{includedir},
                                    $wrapper_data->{32}->{libdir},

                                    # 64-bit
                                    $wrapper_data->{64}->{compiler_args},
                                    @top_params,
                                    $wrapper_data->{64}->{linker_flags},
                                    $wrapper_data->{64}->{includedir},
                                    $wrapper_data->{64}->{libdir},
            );

            MTT::Files::SafeWrite(1, "$destdir/$prefix$compiler-wrapper-data.txt", $contents);
        }
    }
}

# Need to prepend copyright and some basic information
my $year = strftime("%Y", localtime);
my $machname = `uname -p`;
chomp $machname;

sub create_packages {
    my ($staging_dir, $destination_dir) = @_;
    Debug("create_packages: got @_\n");

    # Default to prefixing package names with "OMPI"
    if (!defined($package_name_prefix)) {
        $package_name_prefix = "OMPI";
    }

    # Prepare an overarching status variable
    my $success = 1;

    my $save_cwd = File::Spec->rel2abs(cwd());
    MTT::DoCommand::Chdir($staging_dir);

    my $username  = $ENV{"USER"};
    my $groupname = $ENV{"GROUP"};
    my $archname  = $ENV{"MACHTYPE"};

    my $packages;
    my $brand = "Open MPI";
    $packages->{"${package_name_prefix}ompi"}->{"directories"} = [qw(bin etc include lib share)];
    $packages->{"${package_name_prefix}ompi"}->{"name"} = $brand;
    $packages->{"${package_name_prefix}ompi"}->{"description"} = "$brand Message Passing Interface";
    $packages->{"${package_name_prefix}ompimn"}->{"directories"} = [qw(man)];
    $packages->{"${package_name_prefix}ompimn"}->{"name"} = $brand;
    $packages->{"${package_name_prefix}omsc"}->{"directories"} = [qw(examples)];
    $packages->{"${package_name_prefix}omsc"}->{"name"} = $brand;
    $packages->{"${package_name_prefix}omsc"}->{"description"} = "$brand Message Passing Interface Miscellaneous Files";
    $packages->{"${package_name_prefix}ompiat"}->{"directories"} = [qw(Install_Utilities)];
    $packages->{"${package_name_prefix}ompiat"}->{"name"} = $brand;
    $packages->{"${package_name_prefix}ompiat"}->{"description"} = "$brand Administrative Tools and Utilities";

    foreach my $package_name (keys %$packages) {

        # Write a pkginfo file to pass to the prototype file
        my $short_name     = $packages->{$package_name}->{"name"};
        my $description    = $packages->{$package_name}->{"description"};
        my $pkginfo_file   = _write_pkginfo_file($package_name, $short_name, $description);

        # Write a copyright file to pass to the prototype file
        my $copyright_file = _write_copyright_file();

        # Start with the prologue for the prototype file
        my $contents = "\n# Copyright (c) $year Sun Microsystems, Inc. All rights reserved." .
                       "\n#" .
                       "\ni pkginfo=$pkginfo_file" .
                       "\ni $copyright_file" .
                       "\nd none \$SUNW_PRODVERS 0755 root bin" .
                       "\n";

        my @directories = @{$packages->{$package_name}->{"directories"}};
        my $pkgproto_args = join(" ", map { "$_=\$SUNW_PRODVERS/$_/" } @directories);
        my $cmd = "pkgproto $pkgproto_args";

        my $x = MTT::DoCommand::Cmd(1, $cmd);
        if (0 != $x->{exit_status}) {
            Warning("$package: Error in pkgproto: '$cmd'\n");
            $success = 0;
            next;
        }

        # Remove duplicates from pkgproto output
        my @contents;
        @contents = split(/\n/, $x->{result_stdout});
        @contents = MTT::Util::delete_duplicates_from_array(@contents);
        @contents = MTT::Util::delete_matches_from_array(@contents, '\.la\b');
        $contents .= join("\n", sort @contents);

        # ClusterTools are root packages, so specify this in the
        $contents =~ s/\b$username\b/root/g;
        $contents =~ s/\b$groupname\b/bin/g;
        $contents =~ s/="ISA"/="$machname"/g;

        # Write out prototype file
        my $prototype_file = "prototype.$package_name";
        MTT::Files::SafeWrite(1, $prototype_file, $contents);

        # Make the packages
        $cmd = "pkgmk -o -b $staging_dir -d $destination_dir -f $prototype_file";
        $x = MTT::DoCommand::Cmd(1, $cmd);
        if (0 != $x->{exit_status}) {
            $success = 0;
            Warning("$package: Error in pkgmk: '$cmd'\n");
        }
    }

    # Print an overall pass/fail message
    if (! $success) {
        Verbose("$package: Package creation was unsuccessful.\n");
    } else {
        Verbose("$package: Package creation was successful.\n");
    }

    # Return the directory we were in before entering this subroutine
    MTT::DoCommand::Chdir($save_cwd);
}

# Write a pkginfo file for the specified package.
# To be passed to the prototype file.
sub _write_pkginfo_file {
    my ($name, $short_name, $desc) = @_;
    Debug("_write_pkginfo_file: got @_\n");

    my $pkgvers;
    $pkgvers->{"7.0"} = "1.0";
    $pkgvers->{"7.1"} = "2.0";
    $pkgvers->{"8.0"} = "3.0";

    # Default to a bogus release number
    $release_number = "unknown" if (!defined($release_number));

    # Set the SUNW_PKGVERS string
    my $version = $pkgvers->{$release_number};

    # Default the package version to 99.0 to safely
    # avoid conflict with other installed packages
    $version = "unknown" if (!$version);
    $product_version = "HPCx" if (!$product_version);

    my $contents = "# Copyright (c) $year Sun Microsystems, Inc. All rights reserved.
#                         Use is subject to license terms.
# \$COPYRIGHT\$
#
# Additional copyrights may follow

PKG=\"$name\"
NAME=\"$short_name\"
VERSION=\"$release_number\"
BASEDIR=\"/opt/${package_name_prefix}hpc\"
ARCH=\"ISA\"
SUNW_PRODVERS=\"$product_version\"
SUNW_PRODNAME=\"Open MPI\"
SUNW_PKGVERS=\"$version\"
DESC=\"$desc\"
VENDOR=\"Open MPI\"
CATEGORY=\"system\"
CLASSES=\"none\"
MAXINST=\"1000\"
HOTLINE=\"Please contact your local service provider.\"
EMAIL=\"\"";

    my $filename = "pkginfo.$name";
    MTT::Files::SafeWrite(1, $filename, $contents);

    Debug("_write_pkginfo_file returning $filename\n");
    return $filename;
}

# Write a copyright file
sub _write_copyright_file {
    my $contents = "# Copyright (c) $year Sun Microsystems, Inc. All rights reserved.
#                         Use is subject to license terms.
# \$COPYRIGHT\$
#
# Additional copyrights may follow";

    my $filename = "copyright";
    MTT::Files::SafeWrite(1, $filename, $contents);

    return $filename;
}

1;
