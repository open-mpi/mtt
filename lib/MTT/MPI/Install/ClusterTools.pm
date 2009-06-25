#!/usr/bin/env perl
#
# Copyright (c) 2007-2009 Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2008      Cisco Systems, Inc.  All rights reserved.
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
use POSIX qw/strftime/;
use File::Spec;
use File::Basename;
use File::Temp qw(tempfile tempdir);

#--------------------------------------------------------------------------

# Global package variables
my $major_version_number;
my $release_version_number;
my $build_number;
my $full_ct_version_number;
my $ompi_version_number;
my $product_version;
my $compiler_name;
my $product_name = "ClusterTools";
my $package_name_prefix;
my $package_basedir;
my $configure_prefix;
my $solaris_copyright_file;
my $opensolaris_copyright_file;

# Global uname variables
my $arch = `uname -p`;
my $os   = `uname -s`;
chomp $arch;
chomp $os;

# Grab the OS distro string. E.g., "rhel4" in:
#   $ whatami -t
#   linux-rhel4-x86_64
my $whatami = MTT::Values::Functions::whatami("-t");
my $os_distro;
if ($whatami =~ /(\w+)-(\w+)-(\w+)/) {
    $os_distro = $2;
}

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
    my $abs_srcdir = "$config->{abs_srcdir}";

    # Process clustertools input parameters
    # These variables are primarily only of interest to Release Engineering
    $build_number = Value($ini, $section, "clustertools_build_number");
    my $create_packages = Logical($ini, $section, "clustertools_create_packages");
    my $svn_r_number = Value($ini, $section, "clustertools_svn_r_number");

    # Set the global configure prefix
    $configure_prefix = Value($ini, $section, "clustertools_configure_prefix");

    # Use ${prefix} or hardcode the path into wrapper data files?
    my $wrapper_hardcode_prefix = Value($ini, $section, "clustertools_wrapper_hardcode_prefix");

    my $do_autogen = Logical($ini, $section, "clustertools_do_autogen");
    my $skip_configure = Logical($ini, $section, "clustertools_skip_configure");

    # Gather before/after GNU install steps
    # (Do not evalute these just yet, wait until GNU_Install to do so)
    my $before_configure    = $ini->val($section, "clustertools_before_configure");
    my $after_configure     = $ini->val($section, "clustertools_after_configure");
    my $before_make_all     = $ini->val($section, "clustertools_before_make_all");
    my $after_make_all      = $ini->val($section, "clustertools_after_make_all");
    my $before_make_check   = $ini->val($section, "clustertools_before_make_check");
    my $after_make_check    = $ini->val($section, "clustertools_after_make_check");
    my $before_make_install = $ini->val($section, "clustertools_before_make_install");
    my $after_make_install  = $ini->val($section, "clustertools_after_make_install");

    # Process global clustertools input parameter(s)
    $major_version_number       = Value($ini, $section, "clustertools_major_version");
    $release_version_number     = Value($ini, $section, "clustertools_release_version");
    $full_ct_version_number     = Value($ini, $section, "clustertools_full_version");
    $product_version            = Value($ini, $section, "clustertools_product_version");
    $package_name_prefix        = Value($ini, $section, "clustertools_package_name_prefix");
    $solaris_copyright_file     = Value($ini, $section, "clustertools_solaris_copyright_file");
    $opensolaris_copyright_file = Value($ini, $section, "clustertools_opensolaris_copyright_file");
    $package_basedir            = Value($ini, $section, "clustertools_package_basedir");
    $package_basedir        = defined($package_basedir) ? $package_basedir : "/opt";

    # Grab the internal repository revision number
    my $internal_r_number = $config->{module_data}->{r};

    # Grab the Open MPI version number
    $ompi_version_number = _get_ompi_version_number();

    # Update the version file
    my @greek_parts;
    # With this we get a duplicate string, e.g., 1.3-1.3r12345 ...
    # push(@greek_parts, "$ompi_version_number")   if ($ompi_version_number);
    push(@greek_parts, "r$svn_r_number")            if ($svn_r_number);
    push(@greek_parts, "ct$full_ct_version_number") if ($full_ct_version_number);
    push(@greek_parts, "b$build_number")            if ($build_number);
    push(@greek_parts, "r$internal_r_number")       if ($internal_r_number);
    my $greek = join("-", @greek_parts);

    &_update_version_file($greek, "VERSION");

    # Update the openmpi-mca-params.conf file
    my $mca_params_conf_file = "opal/etc/openmpi-mca-params.conf";
    &_update_openmpi_mca_params_conf($mca_params_conf_file);
    if ($os =~ /SunOS/i) {
        &_update_openmpi_mca_params_conf_solaris($mca_params_conf_file);
    }

    # Get some OMPI-module-specific config arguments
    $config->{make_all_arguments} = Value($ini, $section, "clustertools_make_all_arguments");

    # JMS: compiler name may have come in from "compiler_name" in
    # Install.pm. So if we didn't define one for this module, use the
    # default from "compiler_name".  Note: to be deleted someday
    # (i.e., only rely on this module's compiler_name and not use a
    # higher-level default, per #222).
    $compiler_name                 = Value($ini, $section, "clustertools_compiler_name");
    $config->{compiler_version}    = Value($ini, $section, "clustertools_compiler_version");
    $config->{configure_arguments} = Value($ini, $section, "clustertools_configure_arguments");
    $config->{make_check}          = Logical($ini, $section, "clustertools_make_check");

    # Throw a warning if their compiler doesn't match up with the ones
    # we have in the database
    MTT::Util::is_valid_compiler_name($section, $compiler_name);

    # Hack to set the correct runtime dependency path (-R) for root packages.
    #
    # TODO: There must be a way to change the rpath of the already-built
    # libraries that would not require us to rebuild from scratch. Maybe some
    # libtool magic is needed? The -R/path args seem to be hard-coded into the
    # resulting .la files. How can we recreate those .la files so that the
    # libtool invocations use -R/opt, instead of -R/workspace?
    if ($create_packages) {

        # If the user supplies no DESTDIR argument, then set it automatically
        if ($config->{make_install_arguments} !~ /\bDESTDIR\b/) {
            $config->{make_install_arguments} = "DESTDIR=$config->{installdir}";
        }
        $staging_dir = "$config->{installdir}/$configure_prefix";
        $wrapper_rpath = $configure_prefix;
    }

    # Run autogen.sh
    my $autogen_script = "./autogen.sh";
    if ($do_autogen and -x $autogen_script) {
        $x = MTT::DoCommand::Cmd(1, $autogen_script);
        if (0 != $x->{exit_status}) {
            $ret->{result_message} = "$autogen_script failed.";
            Verbose("$autogen_script failed. Skipping this install.\n");
            return $ret;
        }
    } else {
        Verbose("Skipping $autogen_script.\n");
    }

    # Run configure / make all / make check / make install
    my $configure_arguments = $config->{configure_arguments};

    # Handle a scalar or an array (scalar for single-lib,
    # array of configure_arguments for multi-lib)
    if (ref($configure_arguments) eq "") {
        my $tmp = $configure_arguments;
        undef $configure_arguments;
        push(@$configure_arguments, $tmp);
    }

    my $i = 0;
    foreach my $_configure_arguments (@$configure_arguments) {

        # Add some versioning info:
        #   1. package-string shows up in ompi_info
        #   2. ident-string is embedded into all the binaries as
        #      a #pragma ident
        #
        # Note: we must use *double* quotes here
        $_configure_arguments .=
            " --with-package-string=\"$product_name $full_ct_version_number\"" .
            " --with-ident-string=\"@(#)RELEASE VERSION $ompi_version_number$greek\"";

        # Convert newlines to spaces
        $_configure_arguments =~ s/\n|\r/ /g;

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

            before_configure    => $before_configure,
            after_configure     => $after_configure,
            before_make_all     => $before_make_all,
            after_make_all      => $after_make_all,
            before_make_check   => $before_make_check,
            after_make_check    => $after_make_check,
            before_make_install => $before_make_install,
            after_make_install  => $after_make_install,
        };

        # If this is the first time through (e.g., the first configure, make,
        # make install in a series of two or more) then we do not need to do a
        # make clean. We can't do the make clean every time, because a "make
        # clean" can invoke aclocal (and friends), which in turn recreates the
        # libtool script which we might need to modify ... deep breath.
        $gnu->{make_clean} = 1;
        if ($i == 0) {
            $gnu->{make_clean} = 0;
        }

        # Optionally skip configure
        $gnu->{skip_configure} = 1 if ($skip_configure);

        my $install = MTT::Common::GNU_Install::Install($gnu);
        foreach my $k (keys(%{$install})) {
            $ret->{$k} = $install->{$k};
        }

        # If either of the two builds fails, the entire build has failed
        return $ret
            if (exists($ret->{fail}));

        # Backup the config.log
        my $rand_str = MTT::Values::RandomString(10);
        MTT::DoCommand::Cmd(1, "mv config.log config-$rand_str.log");

        $i++;
    }

    # Symlink the special arch labels (e.g., "sparcv9" and "amd64") to the generic "64"
    # (Someday the special arch labels will be deprecated)
    my ($lib_label_for_64_bit) = &_setup_architecture_dependent_labels();
    MTT::DoCommand::Pushdir("$staging_dir/lib");
    symlink($lib_label_for_64_bit, "64");
    symlink(".", "32");
    MTT::DoCommand::Popdir();

    # Create a symlink in the "instrument" area only if it exists
    if (-d "$staging_dir/instrument/lib") {
        MTT::DoCommand::Pushdir("$staging_dir/instrument/lib");
        symlink($lib_label_for_64_bit, "64");
        symlink(".", "32");
        MTT::DoCommand::Popdir();
    }

    # Create wrapper data files
    my $wrapper_destdir = "$staging_dir/share/openmpi";
    &_create_wrapper_data_files($wrapper_destdir, $compiler_name, $wrapper_rpath, $greek, $wrapper_hardcode_prefix);

    # Copy over the examples directory to the install area
    my $examples_dir = "$config->{abs_srcdir}/examples";
    MTT::DoCommand::Cmd(1, "cp -r $examples_dir $staging_dir");

    # Copy over the mpi.d file to the install area
    if ($os =~ /SunOS/i) {
        my $mpi_d_file = "$config->{abs_srcdir}/ompi/dtrace/mpi.d";
        MTT::DoCommand::Cmd(1, "cp $mpi_d_file $staging_dir");
    }

    CREATE_PACKAGES:

    # Copy over the libC libraries needed for C++ programs (such as ompi_info)
    # to dynamically load
    if ($compiler_name =~ /sun|sos/i) {
        my $libc_libraries = _find_sun_studio_libc_libraries();
        foreach my $lib (@$libc_libraries) {
            MTT::DoCommand::Cmd(1, "cp $lib $staging_dir/lib");
        }
    }

    # Create packages
    if ($create_packages) {

        # Setup the ClusterTools installer
        # TODO: Move installer stuff to create_solaris_packages()
        my $installer_dir   = &_setup_installer($ini, $section);
        my $install_dir     = $config->{installdir};
        my $destination_dir = "$install_dir/../Product";

        # Make a place for the packages to sit
        MTT::Files::mkdir($destination_dir);

        if ($installer_dir) {
            # Copy the following two directories to the staging area:
            #   * examples directory (OMPIomsc package)
            #   * Install_Utilities directory (OMPIomiat package)
            MTT::DoCommand::Cmd(1, "cp -r $installer_dir $staging_dir");

            # Make a place for the packages to sit
            MTT::Files::mkdir("$destination_dir-Solaris");
            MTT::Files::mkdir("$destination_dir-OpenSolaris");

            # Install Utilities for boot-strapping
            MTT::DoCommand::Cmd(1, "cp -r $installer_dir $destination_dir-Solaris");
            MTT::DoCommand::Cmd(1, "cp -r $installer_dir $destination_dir-OpenSolaris");
        }

        if ($os =~ /SunOS/i) {

            # We need to create two sets of packages: one for Solaris, and one for
            # OpenSolaris (each with different copyright files embedded in the
            # packages). [Sigh] The things we do to please Legal Dept ...
            create_packages($staging_dir, "$destination_dir-Solaris", $solaris_copyright_file);
            create_packages($staging_dir, "$destination_dir-OpenSolaris", $opensolaris_copyright_file);
            create_tarball($staging_dir, "$destination_dir-Solaris");

        } elsif ($os =~ /Linux/i) {
            # Create Solaris or Linux (RPM) packages
            create_packages($staging_dir, $destination_dir, $install_dir, $config);
            create_tarball($staging_dir, $destination_dir);
        }

        # Make the installer available to the post-installation steps
        my $installer_path = "$destination_dir/Install_Utilities";
        if (exists($ENV{PATH})) {
            $ENV{PATH} = "$installer_path/bin:" . $ENV{PATH};
        } else {
            $ENV{PATH} = "$installer_path/bin";
        }
    }

    # Remove the mpi.d file from the staging area
    if (-e "$staging_dir/mpi.d") {
        MTT::DoCommand::Cmd(1, "rm $staging_dir/mpi.d");
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

sub _get_ompi_version_number {
    my ($file) = @_;

    my $ret;

    # Get version number from VERSION file by default
    my $file = "./VERSION" if (! defined($file));
    my $contents = MTT::Files::Slurp($file);

    my $major;
    my $minor;
    my $release;

    if ($contents =~ /\nmajor=(.*)/) {
        $major = $1;
    }
    if ($contents =~ /\nminor=(.*)/) {
        $minor = $1;
    }
    if ($contents =~ /\nminor=(.*)/) {
        $release = $1;
    }

    $ret = "$major.$minor";

    Debug("_get_ompi_version_number returning $ret\n");
    return $ret;
}

sub _update_version_file {
    my ($greek) = @_;

    # Read in the default VERSION file
    my $contents = MTT::Files::Slurp("./VERSION");

    # Splice in the greek value and direct configure to
    # not dynamically grab the SVN r #
    $contents =~ s/(\ngreek)=.*/$1=$greek/;
    $contents =~ s/(\nwant_svn)=.*/$1=0/;
    $contents =~ s/(\nsvn_r)=.*/$1=0/;

    # Set the date to be used in the man pages
    # in this format: 08 Aug 2008
    my $month = strftime("%b", localtime);
    my $mday = strftime("%d", localtime);
    my $year = strftime("%Y", localtime);
    $contents =~ s/(\ndate)=.*/$1="$mday $month $year"/;

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

# Append some special ClusterTools settings to mca_params.conf (for Solaris only)
sub _update_openmpi_mca_params_conf_solaris {
    my ($file) = @_;

    my $contents = MTT::Files::Slurp($file);
    my $str = "
# Exclude the sppp0 interface on the M9000 machines
btl_tcp_if_exclude = lo0,sppp0

# Exclude openib BTL, not currently supported
btl = ^openib,ofud
";

    my $ret = MTT::Files::SafeWrite(1, $file, $contents . $str);

    return $ret;
}

# Setup architecture dependent labels for 64-bit (e.g., v9 and amd64)
sub _setup_architecture_dependent_labels {

    my $lib_label;
    my $include_label;
    my $primary_compiler_args;
    my $secondary_compiler_args;
    my $primary_wordsize;
    my $secondary_wordsize;

    if ($os =~ /SunOS/i) {
        $primary_wordsize = 32;
        $secondary_wordsize = 64;
        $primary_compiler_args = "";

        if ($arch =~ /sparc/i) {
            $lib_label = "sparcv9";
            $include_label = "v9";
            $secondary_compiler_args = "-xarch=v9;-xarch=v9a;-xarch=v9b;-xarch=native64;-xarch=generic64;-xtarget=native64;-xtarget=generic64;-m64;";
        } elsif ($arch =~ /i386/i) {
            $lib_label = "amd64";
            $include_label = "amd64";
            $secondary_compiler_args = "-xarch=amd64;-xarch=amd64a;-xarch=native64;-xarch=generic64;-xtarget=native64;-xtarget=generic64;-m64";
        }

    # Intel is the oddball compiler that defaults to 32-bit
    } elsif ($compiler_name =~ /intel/i) {
        $primary_wordsize = 32;
        $secondary_wordsize = 64;

        $lib_label = "lib64";
        $include_label = "64";
        $primary_compiler_args = "";
        $secondary_compiler_args = "-m64";

    # GCC AND SUN STUDIO BOTH DEFAULT TO 64-BIT ON LINUX,
    # BUT IF THIS FACT CHANGES - SO TOO WILL THE BELOW BLOCK
    # NEED TO CHANGE!
    } elsif ($os =~ /Linux/i) {
        $primary_wordsize = 64;
        $secondary_wordsize = 32;

        $lib_label = "lib64";
        $include_label = "64";
        $primary_compiler_args = "";
        $secondary_compiler_args = "-m32";

        # Most of the GNU-compatible compilers support -m32/-m64,
        # except for PGI which has some oddball -tp options
        if ($compiler_name =~ /pgi/i) {
            $primary_compiler_args = "";
            $secondary_compiler_args = "-tp=k8-32;-tp=barcelona;-tp=core2";
        }
    }

    return ($lib_label,
            $include_label,
            $primary_compiler_args,
            $secondary_compiler_args,
            $primary_wordsize,
            $secondary_wordsize);
}

# Arguments:
#   1. Where we are writing the files
#   2. Compiler name: "sun" or "gnu"
#   3. -R (or -Wl,-rpath) <PATH> to be used within the wrapper data files
#   4. version for wrapper .txt files
sub _create_wrapper_data_files {
    my ($destdir, $compiler_name, $installdir, $version, $wrapper_hardcode_prefix) = @_;
    Debug("_create_wrapper_data_files: got @_\n");

    # Ensure that the destination directory exists
    MTT::Files::mkdir($destdir);

    my @compilers = (
        "CC",
        "c++",
        "cc",
        "cxx",
        "f77",
        "f90",
        "f95",
    );

    # Setup architecture dependent labels
    my ($lib_label_for_64_bit,
        $include_label_for_64_bit,
        $primary_compiler_args,
        $secondary_compiler_args,
        $primary_wordsize,
        $secondary_wordsize) =
            &_setup_architecture_dependent_labels();

    my $project = "Open MPI";
    my $project_short = "OMPI";
    my $preprocessor_flags = "";
    my $required_file = "";

    # Prepare a structure containing all the wrapper data
    my $wrapper_data;

    # Open MPI does not appear to have f95 support, but put the
    # data files stubs in there in case it does someday
    $wrapper_data->{"cc"}->{language}  = "C";
    $wrapper_data->{"CC"}->{language}  = "C++";
    $wrapper_data->{"c++"}->{language} = "C++";
    $wrapper_data->{"cxx"}->{language} = "C++";
    $wrapper_data->{"f77"}->{language} = "Fortran 77";
    $wrapper_data->{"f90"}->{language} = "Fortran 90";
    $wrapper_data->{"f95"}->{language} = "Fortran 95";

    # MPI wrapper compilers (Sun)
    $wrapper_data->{"cc"}->{underlying_sun_compiler}  = "cc";
    $wrapper_data->{"CC"}->{underlying_sun_compiler}  = "CC";
    $wrapper_data->{"c++"}->{underlying_sun_compiler} = "CC";
    $wrapper_data->{"cxx"}->{underlying_sun_compiler} = "CC";
    $wrapper_data->{"f77"}->{underlying_sun_compiler} = "f77";
    $wrapper_data->{"f90"}->{underlying_sun_compiler} = "f90";
    $wrapper_data->{"f95"}->{underlying_sun_compiler} = "f95";

    # MPI wrapper compilers (GNU)
    $wrapper_data->{"cc"}->{underlying_gnu_compiler}  = "gcc";
    $wrapper_data->{"CC"}->{underlying_gnu_compiler}  = "g++";
    $wrapper_data->{"c++"}->{underlying_gnu_compiler} = "g++";
    $wrapper_data->{"cxx"}->{underlying_gnu_compiler} = "g++";
    $wrapper_data->{"f77"}->{underlying_gnu_compiler} = "g77";
    $wrapper_data->{"f90"}->{underlying_gnu_compiler} = "gfortran";
    $wrapper_data->{"f95"}->{underlying_gnu_compiler} = "gfortran";

    # MPI wrapper compilers (Pathscale)
    $wrapper_data->{"cc"}->{underlying_pathscale_compiler}  = "pathcc";
    $wrapper_data->{"CC"}->{underlying_pathscale_compiler}  = "pathCC";
    $wrapper_data->{"c++"}->{underlying_pathscale_compiler} = "pathCC";
    $wrapper_data->{"cxx"}->{underlying_pathscale_compiler} = "pathCC";
    $wrapper_data->{"f77"}->{underlying_pathscale_compiler} = "pathf90";
    $wrapper_data->{"f90"}->{underlying_pathscale_compiler} = "pathf90";
    $wrapper_data->{"f95"}->{underlying_pathscale_compiler} = "pathf90";

    # MPI wrapper compilers (Intel)
    $wrapper_data->{"cc"}->{underlying_intel_compiler}  = "icc";
    $wrapper_data->{"CC"}->{underlying_intel_compiler}  = "icpc";
    $wrapper_data->{"c++"}->{underlying_intel_compiler} = "icpc";
    $wrapper_data->{"cxx"}->{underlying_intel_compiler} = "icpc";
    $wrapper_data->{"f77"}->{underlying_intel_compiler} = "ifort";
    $wrapper_data->{"f90"}->{underlying_intel_compiler} = "ifort";
    $wrapper_data->{"f95"}->{underlying_intel_compiler} = "ifort";

    # MPI wrapper compilers (PGI)
    $wrapper_data->{"cc"}->{underlying_pgi_compiler}  = "pgcc";
    $wrapper_data->{"CC"}->{underlying_pgi_compiler}  = "pgCC";
    $wrapper_data->{"c++"}->{underlying_pgi_compiler} = "pgCC";
    $wrapper_data->{"cxx"}->{underlying_pgi_compiler} = "pgCC";
    $wrapper_data->{"f77"}->{underlying_pgi_compiler} = "pgf77";
    $wrapper_data->{"f90"}->{underlying_pgi_compiler} = "pgf90";
    $wrapper_data->{"f95"}->{underlying_pgi_compiler} = "pgf90";

    # VampirTrace wrapper compilers
    $wrapper_data->{"cc"}->{underlying_vt_compiler}  = "vtcc";
    $wrapper_data->{"CC"}->{underlying_vt_compiler}  = "vtcxx";
    $wrapper_data->{"c++"}->{underlying_vt_compiler} = "vtcxx";
    $wrapper_data->{"cxx"}->{underlying_vt_compiler} = "vtcxx";
    $wrapper_data->{"f77"}->{underlying_vt_compiler} = "vtf77";
    $wrapper_data->{"f90"}->{underlying_vt_compiler} = "vtf90";
    $wrapper_data->{"f95"}->{underlying_vt_compiler} = "vtf90";

    $wrapper_data->{"cc"}->{compiler_env}  = "CC";
    $wrapper_data->{"CC"}->{compiler_env}  = "CXX";
    $wrapper_data->{"c++"}->{compiler_env} = "CXX";
    $wrapper_data->{"cxx"}->{compiler_env} = "CXX";
    $wrapper_data->{"f77"}->{compiler_env} = "F77";
    $wrapper_data->{"f90"}->{compiler_env} = "FC";
    $wrapper_data->{"f95"}->{compiler_env} = "FC";

    $wrapper_data->{"cc"}->{compiler_flags_env}  = "CFLAGS";
    $wrapper_data->{"CC"}->{compiler_flags_env}  = "CXXFLAGS";
    $wrapper_data->{"c++"}->{compiler_flags_env} = "CXXFLAGS";
    $wrapper_data->{"cxx"}->{compiler_flags_env} = "CXXFLAGS";
    $wrapper_data->{"f77"}->{compiler_flags_env} = "FFLAGS";
    $wrapper_data->{"f90"}->{compiler_flags_env} = "FCFLAGS";
    $wrapper_data->{"f95"}->{compiler_flags_env} = "FCFLAGS";

    $wrapper_data->{"cc"}->{extra_includes}  = "openmpi";
    $wrapper_data->{"CC"}->{extra_includes}  = "openmpi";
    $wrapper_data->{"c++"}->{extra_includes} = "openmpi";
    $wrapper_data->{"cxx"}->{extra_includes} = "openmpi";
    $wrapper_data->{"f77"}->{extra_includes} = "";
    $wrapper_data->{"f90"}->{extra_includes} = "";
    $wrapper_data->{"f95"}->{extra_includes} = "";

    # Linux and Solaris have slightly differing -lfoo needs
    my $common_libs = "-lmpi -lopen-rte -lopen-pal -lnsl -lrt -lm -ldl";
    if ($os =~ /SunOS/i) {
        $common_libs .= " -lsocket";
    } elsif ($os =~ /Linux/i) {
        $common_libs .= " -lutil";
        # -lpthread is needed if using --without-threads!
        $common_libs .= " -lpthread";
    }

    $wrapper_data->{"cc"}->{libs}  = "$common_libs";
    $wrapper_data->{"CC"}->{libs}  = "$common_libs -lmpi_cxx";
    $wrapper_data->{"c++"}->{libs} = "$common_libs -lmpi_cxx";
    $wrapper_data->{"cxx"}->{libs} = "$common_libs -lmpi_cxx";
    $wrapper_data->{"f77"}->{libs} = "$common_libs -lmpi_f77";
    $wrapper_data->{"f90"}->{libs} = "$common_libs -lmpi_f77 -lmpi_f90";
    $wrapper_data->{"f95"}->{libs} = "$common_libs -lmpi_f77 -lmpi_f90";

    # Default to Sun Studio flags
    my $dash_r =  "-R";
    my $dash_m =  "-M";
    my $linker_flags_32;
    my $linker_flags_64;
    my $linker_flags_gfortran_32;
    my $linker_flags_gfortran_64;
    my $compiler_flags_gfortran_32;
    my $compiler_flags_gfortran_64;

    # By default, use the wrapper-expanded ${prefix} varaible
    # (but allow for hardcoded prefix, e.g., v1.2 testing)
    my $wrapper_prefix = "\${prefix}";
    if ($wrapper_hardcode_prefix) {
        $wrapper_prefix = $installdir;
    }

    if ($compiler_name =~ /gnu|gcc|intel|path|pgi/i) {
        $dash_r = "-Wl,-rpath,";

        # Prevent missing module files error from GCC (4.1)
        # See http://gcc.gnu.org/bugzilla/show_bug.cgi?id=30446
        # Use the workaround they proposed to get the fortran module
        $dash_m =  "";

        $linker_flags_gfortran_32 = "-I$wrapper_prefix/lib ";
        $linker_flags_gfortran_64 = "-I$wrapper_prefix/lib/$lib_label_for_64_bit ";

        # Only gfortran requires the -J option. gfortran compatible compilers
        # (e.g., Intel and Pathscale) do not require the -J workaround
        if ($compiler_name =~ /gnu|gcc/i) {
            $linker_flags_gfortran_64 .= "-J$wrapper_prefix/lib/$lib_label_for_64_bit ";
            $linker_flags_gfortran_32 .= "-J$wrapper_prefix/lib ";
        }

        $compiler_flags_gfortran_32 = "-I$wrapper_prefix/lib";
        $compiler_flags_gfortran_64 = "-I$wrapper_prefix/lib/$lib_label_for_64_bit";

    }

    $linker_flags_32 = "$dash_r/opt/mx/lib " .
                       "$dash_r$wrapper_prefix/lib";
    $linker_flags_64 = "$dash_r/opt/mx/lib/$lib_label_for_64_bit " .
                       "$dash_r$wrapper_prefix/lib/$lib_label_for_64_bit";

    $wrapper_data->{32}->{includedir} = "$wrapper_prefix/include";
    $wrapper_data->{64}->{includedir} = "$wrapper_prefix/include/$include_label_for_64_bit";
    $wrapper_data->{32}->{libdir} = "$wrapper_prefix/lib";
    $wrapper_data->{64}->{libdir} = "$wrapper_prefix/lib/$lib_label_for_64_bit";
    $wrapper_data->{32}->{linker_flags} = $linker_flags_32;
    $wrapper_data->{64}->{linker_flags} = $linker_flags_64;

    # Primary and secondary compiler_args
    $wrapper_data->{$primary_wordsize}->{compiler_args} = $primary_compiler_args;
    $wrapper_data->{$secondary_wordsize}->{compiler_args} = $secondary_compiler_args;

    # Special gfortran linker flags
    $wrapper_data->{"gfortran"}->{32}->{linker_flags} = $linker_flags_gfortran_32;
    $wrapper_data->{"gfortran"}->{64}->{linker_flags} = $linker_flags_gfortran_64;
    $wrapper_data->{"gfortran"}->{32}->{compiler_flags} = $compiler_flags_gfortran_32;
    $wrapper_data->{"gfortran"}->{64}->{compiler_flags} = $compiler_flags_gfortran_64;
    $wrapper_data->{"ifort"}->{32}->{linker_flags} = $linker_flags_gfortran_32;
    $wrapper_data->{"ifort"}->{64}->{linker_flags} = $linker_flags_gfortran_64;
    $wrapper_data->{"ifort"}->{32}->{compiler_flags} = $compiler_flags_gfortran_32;
    $wrapper_data->{"ifort"}->{64}->{compiler_flags} = $compiler_flags_gfortran_64;
    $wrapper_data->{"pathf90"}->{32}->{linker_flags} = $linker_flags_gfortran_32;
    $wrapper_data->{"pathf90"}->{64}->{linker_flags} = $linker_flags_gfortran_64;
    $wrapper_data->{"pathf90"}->{32}->{compiler_flags} = $compiler_flags_gfortran_32;
    $wrapper_data->{"pathf90"}->{64}->{compiler_flags} = $compiler_flags_gfortran_64;
    $wrapper_data->{"vtf90"}->{32}->{linker_flags} = $linker_flags_gfortran_32;
    $wrapper_data->{"vtf90"}->{64}->{linker_flags} = $linker_flags_gfortran_64;
    $wrapper_data->{"vtf90"}->{32}->{compiler_flags} = $compiler_flags_gfortran_32;
    $wrapper_data->{"vtf90"}->{64}->{compiler_flags} = $compiler_flags_gfortran_64;

    # For mpif90, point to mpi.mod using the -M flag
    $wrapper_data->{"f90"}->{module_option} = $dash_m;
    $wrapper_data->{"f95"}->{module_option} = $dash_m;

    # We have to either use -m32 or -m64 for Linux
    # (but there's no need to include -m32 in both the compiler_args
    # and compiler_flags field, because that results in redundancy,
    # e.g., cc ... -m32 -m32)
    $wrapper_data->{32}->{Linux}->{compiler_flags} = "";
    $wrapper_data->{64}->{Linux}->{compiler_flags} = "";

    # Template for the wrapper data files
    my $template = "#
# Default word-size (used when -m flag is supplied to wrapper compiler)
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
compiler_flags=%s
libs=%s
linker_flags=%s
required_file=$required_file
includedir=%s
libdir=%s

#
# Alternative word-size (used when -m flag is not supplied to wrapper compiler)
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
compiler_flags=%s
libs=%s
linker_flags=%s
required_file=$required_file
includedir=%s
libdir=%s
";

    # Incorporate these compiler names into the data file name
    # if need be
    my $filename_labels;
    $filename_labels->{"sun"}       = "";
    $filename_labels->{"sos"}       = "";
    $filename_labels->{"gnu"}       = "";
    $filename_labels->{"gcc"}       = "";
    $filename_labels->{"intel"}     = "";
    $filename_labels->{"pgi"}       = "";
    $filename_labels->{"pathscale"} = "";
    $filename_labels->{"vt"}        = "-vt";

    foreach my $prefix ("mpi", "opal", "orte") {
        foreach my $compiler_type ($compiler_name, "vt") {
            foreach my $compiler (@compilers) {

                # Add in, e.g., "-vt" to wrapper data file name
                my $filename_label = $filename_labels->{$compiler_type};

                # Use either the OMPI or VT underlying compiler name
                my $underlying_compiler_type_key =
                            ($compiler_type) ?
                                 "underlying_${compiler_type}_compiler" :
                                 "underlying_compiler";

                my $underlying_compiler = $wrapper_data->{$compiler}->{$underlying_compiler_type_key};

                my @top_params = (
                    $wrapper_data->{$compiler}->{language},
                    $wrapper_data->{$compiler}->{compiler_env},
                    $wrapper_data->{$compiler}->{compiler_flags_env},
                    $wrapper_data->{$compiler}->{$underlying_compiler_type_key},
                    $wrapper_data->{$compiler}->{module_option},
                    $wrapper_data->{$compiler}->{extra_includes},
                );

                my $contents = sprintf($template,

                    # Default
                    $wrapper_data->{$primary_wordsize}->{compiler_args},
                    @top_params,
                    $wrapper_data->{$primary_wordsize}->{$os}->{compiler_flags} . " " .
                      $wrapper_data->{$underlying_compiler}->{$primary_wordsize}->{compiler_flags},
                    $wrapper_data->{$compiler}->{libs},
                    $wrapper_data->{$primary_wordsize}->{linker_flags} . " " .
                      $wrapper_data->{$underlying_compiler}->{$primary_wordsize}->{linker_flags},
                    $wrapper_data->{$primary_wordsize}->{includedir},
                    $wrapper_data->{$primary_wordsize}->{libdir},

                    # Specific -m32/-m64 argument used
                    $wrapper_data->{$secondary_wordsize}->{compiler_args},
                    @top_params,
                    $wrapper_data->{$secondary_wordsize}->{$os}->{compiler_flags} . " " .
                      $wrapper_data->{$underlying_compiler}->{$secondary_wordsize}->{compiler_flags},
                    $wrapper_data->{$compiler}->{libs},
                    $wrapper_data->{$secondary_wordsize}->{linker_flags} . " " .
                      $wrapper_data->{$underlying_compiler}->{$secondary_wordsize}->{linker_flags},
                    $wrapper_data->{$secondary_wordsize}->{includedir},
                    $wrapper_data->{$secondary_wordsize}->{libdir},
                );

                # Write out the file
                MTT::Files::SafeWrite(1, "$destdir/$prefix$compiler$filename_label-wrapper-data.txt", $contents);
            }
        }
    }
}

# Need to prepend copyright and some basic information
my $year = strftime("%Y", localtime);
my $machname = `uname -p`;
chomp $machname;

# Create Solaris or Linux (RPM) packages
sub create_packages {
    # EAM: This should really use MTT's modular design.
    # E.g.,
    #   OS::Solaris::create_packages()
    #   OS::Linux::create_packages()
    #
    if ($os =~ /SunOS/i) {
        create_solaris_packages(@_);
    } elsif ($os =~ /Linux/i) {
        create_linux_packages(@_);
    } else {
        Warning("$package: MTT can not create packages for $os.\n");
    }
}

sub create_solaris_packages {
    my ($staging_dir, $destination_dir, $copyright_file) = @_;
    Debug("create_solaris_packages: got @_\n");

    # Default to prefixing package names with "OMPI"
    if (!defined($package_name_prefix)) {
        $package_name_prefix = "OMPI";
    }

    # Prepare an overarching status variable
    my $success = 1;

    MTT::DoCommand::Pushdir($staging_dir);

    my $packages;
    my $brand = "Open MPI";

    # SUNW_PKGTYPE 
    #   Solaris-only parameter for Sun internal use only. Required for packages part of
    #   the The Solaris operating environment releases which install into the /, /usr,
    #   /usr/kvm, and /usr/openwin file systems. The Solaris operating environment
    #   installation software must know which packages are part of which file system to
    #   properly install a server/client configuration. The currently allowable values
    #   for this parameter are root, usr, kvm, and ow. If no SUNW_PKGTYPE parameter is
    #   present, the package is assumed to be of BASEDIR= /opt. SUNW_PKGTYPE is
    #   optional only for packages which install into the /opt name space as is the
    #   case for the majority of Solaris add-on software. See the SUNW_PKGTYPE
    #   parameter in packagetoc(4) for further information.

    $packages->{"${package_name_prefix}ompi"}->{"directories"} = [qw(bin etc include lib share instrument)];
    $packages->{"${package_name_prefix}ompi"}->{"name"} = $brand;
    $packages->{"${package_name_prefix}ompi"}->{"description"} = "$brand Message Passing Interface";
    $packages->{"${package_name_prefix}ompi"}->{"basedir"} = $package_basedir;
    $packages->{"${package_name_prefix}ompi"}->{"pkgtype"} = "";
    $packages->{"${package_name_prefix}ompimn"}->{"directories"} = [qw(man)];
    $packages->{"${package_name_prefix}ompimn"}->{"name"} = $brand;
    $packages->{"${package_name_prefix}ompimn"}->{"description"} = "$brand Message Passing Interface Man Pages";
    $packages->{"${package_name_prefix}ompimn"}->{"basedir"} = $package_basedir;
    $packages->{"${package_name_prefix}ompimn"}->{"pkgtype"} = "";
    $packages->{"${package_name_prefix}omsc"}->{"directories"} = [qw(examples)];
    $packages->{"${package_name_prefix}omsc"}->{"name"} = $brand;
    $packages->{"${package_name_prefix}omsc"}->{"description"} = "$brand Message Passing Interface Miscellaneous Files";
    $packages->{"${package_name_prefix}omsc"}->{"basedir"} = $package_basedir;
    $packages->{"${package_name_prefix}omsc"}->{"pkgtype"} = "";
    $packages->{"${package_name_prefix}ompiat"}->{"directories"} = [qw(Install_Utilities)];
    $packages->{"${package_name_prefix}ompiat"}->{"name"} = $brand;
    $packages->{"${package_name_prefix}ompiat"}->{"description"} = "$brand Administrative Tools and Utilities";
    $packages->{"${package_name_prefix}ompiat"}->{"basedir"} = $package_basedir;
    $packages->{"${package_name_prefix}ompiat"}->{"pkgtype"} = "";

    # Special mpi.d package that is not installed in /opt
    $packages->{"${package_name_prefix}ompir"}->{"name"} = $brand;
    $packages->{"${package_name_prefix}ompir"}->{"description"} = "$brand Root Filesystem Files";
    $packages->{"${package_name_prefix}ompir"}->{"mpi_d_package"} = 1;
    $packages->{"${package_name_prefix}ompir"}->{"basedir"} = "/usr";
    $packages->{"${package_name_prefix}ompir"}->{"pkgtype"} = "usr";

    foreach my $package_name (keys %$packages) {

        # Write a pkginfo file to pass to the prototype file
        my $short_name     = $packages->{$package_name}->{"name"};
        my $description    = $packages->{$package_name}->{"description"};
        my $basedir        = $packages->{$package_name}->{"basedir"};
        my $pkgtype        = $packages->{$package_name}->{"pkgtype"};
        my $pkginfo_file   = _write_pkginfo_file($package_name, $short_name, $description, $basedir, $pkgtype);

        # Copy the copyright file to pass to the prototype file
        my $copyright_filename = "copyright";
        MTT::DoCommand::Cmd(1, "cp $copyright_file $copyright_filename");

        my $pkgproto_args;
        my $prototype_file;
        my @directories;
        if ($packages->{$package_name}->{"directories"}) {
            @directories = @{$packages->{$package_name}->{"directories"}};
        }

        # Special flag to create mpi.d package
        my $mpi_d_package = $packages->{$package_name}->{"mpi_d_package"};

        # We either create a prototype file on the fly (normal case), or
        # we concoct a special prototype file (oddball case: e.g., mpi.d file package)
        if (@directories) {
            $prototype_file = _create_prototype_file($package_name, $pkginfo_file, $copyright_filename, \@directories);
            next if (! $prototype_file);

        } elsif ($mpi_d_package) {
            $prototype_file = _create_prototype_file_mpi_d($package_name, $pkginfo_file, $copyright_filename);
        }

        # Make the packages
        my $cmd = "pkgmk -o -b $staging_dir -d $destination_dir -f $prototype_file";
        my $x = MTT::DoCommand::Cmd(1, $cmd);
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
    MTT::DoCommand::Popdir();
}

my $vendor = "Sun Microsystems, Inc.";

# Prologue the prototype file with the "pkginfo" and "copyright" i (include)
# lines
sub _create_prototype_file_prologue {
    my ($pkginfo_file, $copyright_file) = @_;

    my $ret =
        "\n# Copyright (c) $year $vendor All rights reserved." .
        "\n#" .
        "\ni pkginfo=$pkginfo_file" .
        "\ni $copyright_file";

    return $ret;
}

# Create a special prototype file for the mpi.d packages
sub _create_prototype_file_mpi_d {
    my ($package_name, $pkginfo_file, $copyright_file) = @_;

    # Start with the prologue for the prototype file
    my $contents = _create_prototype_file_prologue($pkginfo_file, $copyright_file);
    $contents .=
        "\nd none lib/dtrace 0755 root bin" .
        "\nf none lib/dtrace/mpi.d=mpi.d 0644 root bin";

    # Write out prototype file
    my $ret = "prototype.$package_name";
    MTT::Files::SafeWrite(1, $ret, $contents);

    return $ret;
}

# Create a prototype file for one of the opt/ packages
sub _create_prototype_file {
    my ($package_name, $pkginfo_file, $copyright_file, $directories) = @_;
    Debug("_create_prototype_file got @_\n");

    # Compose the pkgproto command
    my $pkgproto_args;
    foreach my $dir (@$directories) {

        # We can skip over some directories (e.g., instrument will not be here
        # if building with_instrument=0), but we print a Warning about missing directories
        if (-d $dir) {
            $pkgproto_args .= "$dir=${package_name_prefix}hpc/$product_version/$dir/ ";
        } else {
            Warning("$package: Did not find \"$dir\" directory to include in packages.\n");
        }
    }

    # Ensure that pkgproto has some arguments, because it will *hang*
    # without them. (Perhaps, it waits for something at
    # STDIN?)
    my ($cmd, $x);
    if ($pkgproto_args) {
        $cmd = "pkgproto $pkgproto_args";
        $x = MTT::DoCommand::Cmd(1, $cmd);
        if (0 != $x->{exit_status}) {
            Warning("$package: Error in pkgproto: '$cmd'\n");
            return undef;
        }
    }

    # Start with the prologue for the prototype file
    my $contents = _create_prototype_file_prologue($pkginfo_file, $copyright_file);
    my $product_version_dirname = dirname($product_version);
    $contents .= "\nd none ${package_name_prefix}hpc/$product_version_dirname 0755 root bin" . "\n";
    $contents .= "\nd none ${package_name_prefix}hpc/$product_version 0755 root bin" . "\n";

    # Remove duplicates from pkgproto output
    my @contents;
    @contents = split(/\n/, $x->{result_stdout});
    @contents = MTT::Util::delete_duplicates_from_array(@contents);
    @contents = MTT::Util::delete_matches_from_array(@contents, '\.la\b');
    $contents .= join("\n", sort @contents);

    # Do not use ENV here to get the user id and group id, because it
    # might be spoofed in the INI using setenv! This is critical
    # because of the search and replace operation we do using these
    # patterns below (on the output of the prototype commands)
    my $username  = getpwuid($<);
    my $groupname = getgrgid($();
    my $archname  = $ENV{"MACHTYPE"};

    # ClusterTools are root packages, so specify this in the
    $contents =~ s/\b$username\b/root/g;
    $contents =~ s/\b$groupname\b/bin/g;
    $contents =~ s/="ISA"/="$machname"/g;

    # Write out prototype file
    my $ret = "prototype.$package_name";
    MTT::Files::SafeWrite(1, $ret, $contents);

    return $ret;
}

# Write a pkginfo file for the specified package.
# To be passed to the prototype file.
sub _write_pkginfo_file {
    my ($name, $short_name, $desc, $basedir, $sunw_pkgtype) = @_;
    Debug("_write_pkginfo_file: got @_\n");

    my $pkgvers;
    $pkgvers->{"7.0"} = "1.0";
    $pkgvers->{"7.1"} = "2.0";
    $pkgvers->{"8.0"} = "3.0";
    $pkgvers->{"8.1"} = "4.0";
    $pkgvers->{"8.2"} = "5.0";
    $pkgvers->{"9.0"} = "6.0";

    # Default to a bogus release number
    $full_ct_version_number = "unknown" if (!defined($full_ct_version_number));

    # Set the SUNW_PKGVERS string
    my $version = $pkgvers->{$full_ct_version_number};
    my $sunw_pkgvers = $full_ct_version_number;

    # Grab a date string for the VERSION param so that we never get two
    # identical VERSION strings. (Why doesn't the Solaris package manager use
    # PSTAMP?)
    my $rev_date_string = strftime("%Y.%m.%d.%H.%M", localtime);

    # Default the package version to 99.0 to safely
    # avoid conflict with other installed packages
    $version = "unknown" if (!$version);
    $product_version = "HPCx" if (!$product_version);

    # Note: in the case of the ClusterTools installer, some of the below
    # settings (e.g., BASEDIR) may be overridden via an administration file
    # (see admin(4)) passed to the "pkgadd" command
    my $contents = "# Copyright (c) $year $vendor All rights reserved.
#                         Use is subject to license terms.
# \$COPYRIGHT\$
#
# Additional copyrights may follow

PKG=\"$name\"
NAME=\"$short_name\"
VERSION=\"$version,REV=$rev_date_string\"
BASEDIR=\"$basedir\"
ARCH=\"$arch\"
SUNW_PRODVERS=\"$product_version\"
SUNW_PRODNAME=\"Sun HPC $product_name $full_ct_version_number, based on Open MPI $ompi_version_number\"
SUNW_PKGVERS=\"$sunw_pkgvers\"
SUNW_PKGTYPE=\"$sunw_pkgtype\"
DESC=\"$desc\"
VENDOR=\"$vendor\"
CATEGORY=\"system\"
CLASSES=\"none\"
MAXINST=\"1000\"
HOTLINE=\"Please contact your local service provider.\"
EMAIL=\"ct-feedback\@sun.com\"";

    my $filename = "pkginfo.$name";
    MTT::Files::SafeWrite(1, $filename, $contents);

    Debug("_write_pkginfo_file returning $filename\n");
    return $filename;
}

# This is admittedly a complete bastardization of
# RPM, because we are creating a lot of dummy sections
# and files to feed to rpmbuild.
sub create_linux_packages {
    my ($staging_dir, $destination_dir, $install_dir, $config) = @_;
    Debug("create_linux_packages: got @_\n");

    # Prepare an overarching status variable
    my $success = 1;

    MTT::DoCommand::Pushdir($staging_dir);

    # Setup a scratch area for RPM creation
    my $temp_dir = tempdir(TEMPLATE => "XXXXXX-mtt-rpm-scratch", DIR => "/tmp");

    # Create a .spec file on the fly
    #
    # TODO: lump the "source" and "binary" RPM steps into one, so that we
    # create the binary RPM using our very own source RPM
    my $binary_rpm_spec_file = _create_binary_rpm_spec_file($temp_dir, $install_dir);
    my $source_rpm_spec_file = _create_source_rpm_spec_file($temp_dir, $install_dir, $config);

    # From man rpmbuild:
    #  -bb  Build a binary package (after doing the %prep,  %build,
    #       and %install stages).
    my $rpmbuild = FindProgram(qw(rpmbuild));

    # Create three RPMs:
    #   1) 32-bit (i386 RPM)
    #   2) 64-bit (x86_64 RPM)
    #   3) Any (source RPM)
    my @targets = qw(i386 x86_64);

    # Create the binary RPM(s)
    my $nil = '%nil';
    my $cmd;

    # Do rpmbuild for both targets
    foreach my $target (@targets) {
        $cmd = "$rpmbuild --verbose -bb" .
                  " --define=\"_build_name_fmt " .
                              "%%{ARCH}/" .
                              "%%{NAME}-" .
                              "%%{VERSION}-" .
                              "%%{RELEASE}." .
                              "%%{ARCH}-" .
                              "built-with-$compiler_name.rpm\" " .
                  # RPM scratch area
                  " --define=\"_topdir $temp_dir\"" .
                  # Override the below built-in macro because it does annoying
                  # things like gzipping every file in the installation
                  " --define=\"suse_check $nil\"" .
                  " --target $target" .
                  " $binary_rpm_spec_file";

        my $ret = MTT::DoCommand::Cmd(1, $cmd);
        if (0 != $ret->{exit_status}) {
            $success = 0;
        }
    }

    # Create the source RPM
    $cmd = "$rpmbuild --verbose -bs" .
              " --define=\"_build_name_fmt " .
                          "%%{ARCH}/" .
                          "%%{NAME}-" .
                          "%%{VERSION}-" .
                          "%%{RELEASE}." .
                          "src.rpm\"" .
              # RPM scratch area
              " --define=\"_topdir $temp_dir\"" .
              # Override the below built-in macro because it does annoying
              # things like gzipping every file in the installation
              " --define=\"suse_check $nil\"" .
              " $source_rpm_spec_file";

    my $ret = MTT::DoCommand::Cmd(1, $cmd);
    if (0 != $ret->{exit_status}) {
        $success = 0;
    }

    MTT::DoCommand::Cmd(1, "rm -rf rpm");
    MTT::DoCommand::Cmd(1, "cp -r $temp_dir $destination_dir/rpm");
    MTT::DoCommand::Cmd(1, "rm -rf $temp_dir");

    # Open up permissions on "rpm" dir
    # (Why is this needed?)
    MTT::DoCommand::Cmd(1, "chmod -R a+r $destination_dir/rpm");
    MTT::DoCommand::Cmd(1, "find $destination_dir/rpm -type d | xargs chmod a+x");
    chmod(0755, "$destination_dir/rpm");

    # Return the directory we were in before entering this subroutine
    MTT::DoCommand::Popdir();

    # Print an overall pass/fail message
    if (! $success) {
        Verbose("$package: Package creation was unsuccessful.\n");
    } else {
        Verbose("$package: Package creation was successful.\n");
    }

    return $ret;
}

# The tarball will contain the identical binaries that the packages
# contain, but they will just be in the form of a simple gzipped tar
# archive. The only feature the packages provide that the tarball does
# not, is the ability to monitor the system's package metadata. To each
# their own.
sub create_tarball {
    my ($staging_dir, $destination_dir) = @_;
    Debug("create_tarball: got @_\n");

    # Get into the directory containing bin, lib, man, ...
    MTT::DoCommand::Pushdir($staging_dir);

    my @directories = qw(bin include lib man share etc instrument examples);
    my $dir_arguments;
    foreach my $dir (@directories) {
        if (-d $dir) {
            $dir_arguments .= " $dir";
        }
    }

    # Name the tarball file similarly to the RPM file name
    my $tarfile_name = "$product_name-$full_ct_version_number-$build_number.$arch-built-with-$compiler_name.tar";

    MTT::DoCommand::Cmd(1, "tar cf $tarfile_name $dir_arguments");
    MTT::DoCommand::Cmd(1, "gzip $tarfile_name");
    MTT::DoCommand::Cmd(1, "mv $tarfile_name.gz $destination_dir");
    MTT::DoCommand::Popdir();
}

# Create the binary RPM spec file
sub _create_binary_rpm_spec_file {
    my ($rpm_top_dir, $build_root) = @_;
    Debug("_create_binary_rpm_spec_file: got @_\n");

    # Setup standard RPM top dir structure
    _setup_rpm_top_dir($rpm_top_dir);

    # Compose the %files section, but do not include 
    # directories that do not exist (e.g., "instrument" in
    # the case of a with_instrument=0 build)
    my $files_rpm_macro;
    my @directories = qw(bin include lib man share etc instrument examples);
    foreach my $dir (@directories) {
        if (-d $dir) {
            $files_rpm_macro .= "\n%attr(-, root, root) $configure_prefix/$dir";
        }
    }

    my $contents = "
#
# This file was automatically generated by MTT.
# Any changes made to it will likely be lost!
#

Summary: A powerful implementaion of MPI
Name: ${product_name}_${compiler_name}
Version: $full_ct_version_number
Release: $build_number
Vendor: $vendor
License: BSD
Group: Development/Libraries
URL: http://www.sun.com/software/products/clustertools
AutoReqProv: no
Distribution: $vendor
Packager: ompi-clustertools-ext\@sun.com
BuildRoot: $build_root
Prefix: $configure_prefix

%description
Open MPI is a project combining technologies and resources from
several other projects (FT-MPI, LA-MPI, LAM/MPI, and PACX-MPI) in
order to build the best MPI library available.

This RPM contains all the tools necessary to compile, link, and run
Open MPI jobs.

# MTT has already fetched, built, and installed the source. Just point RPM to
# the files we want packaged.
%files
%defattr(-, root, root, -)

# The file permissions are already set properly by
# the OMPI build process. Use '-' to leave them as is.
$files_rpm_macro

# Ensure that the Open MPI .conf files are not overwritten on
# an --upgrade operation, since they may contain local changes
%config $configure_prefix/etc

# Make sure prefix is removed in an \"rpm --erase\" operation
%dir $configure_prefix

";

    my $ret = "$rpm_top_dir/SPECS/$product_name-$full_ct_version_number-$build_number-binary.spec";

    MTT::Files::SafeWrite(1, $ret, $contents);
    return $ret;
}

# Create the source RPM spec file
sub _create_source_rpm_spec_file {
    my ($rpm_top_dir, $build_root, $config) = @_;
    Debug("_create_source_rpm_spec_file: got @_\n");

    # Run configure / make all / make check / make install
    my $configure_arguments = _get_configure_arguments($config->{configure_arguments});

    # Setup standard RPM top dir structure
    _setup_rpm_top_dir($rpm_top_dir);

    # Grab the source name
    my $dist_tarball_name = "$product_name-$full_ct_version_number";
    my $dist_tarball = _make_dist_tarball($config->{abs_srcdir}, $dist_tarball_name);
    MTT::DoCommand::Cmd(1, "cp $dist_tarball $rpm_top_dir/SOURCES");
    $dist_tarball = basename($dist_tarball);

    # Compose the RPM %build section
    my $build_section;
    foreach my $args (@$configure_arguments) {
        $build_section .= "
%configure $args %{_append_to_configure_options}
%{__make}
%{__make} install";
    }

    my $contents = "
#
#
# SPEC file for $product_name $full_ct_version_number
#
#

#############################################################################
#
# Preamble Section
#
#############################################################################

Summary: A powerful implementaion of MPI
Name: $product_name
Version: $full_ct_version_number
# Certain characters (e.g., '-') are not allowed for the Release field
Release: $build_number
Vendor: $vendor
License: BSD
Group: Development/Libraries
Source: $dist_tarball
URL: http://www.sun.com/software/products/clustertools
AutoReqProv: no
Distribution: $vendor
Packager: ompi-clustertools-ext\@sun.com

%description
Open MPI is a project combining technologies and resources from
several other projects (FT-MPI, LA-MPI, LAM/MPI, and PACX-MPI) in
order to build the best MPI library available.

This RPM contains all the tools necessary to compile, link, and run
Open MPI jobs.

#############################################################################
#
# Prepatory Section
#
#############################################################################

%prep
%setup -n $dist_tarball_name

#############################################################################
#
# Build Section
#
#############################################################################

$build_section

#############################################################################
#
# Clean Section
#
#############################################################################

%clean

#############################################################################
#
# Files Section
#
#############################################################################

%files
%defattr(-, root, root, -)
%doc README INSTALL LICENSE

# Ends up attempting to install into /etc, instead of %_prefix/etc
# %config etc
";

    my $ret = "$rpm_top_dir/SPECS/$product_name-$full_ct_version_number-$build_number-source.spec";

    MTT::Files::SafeWrite(1, $ret, $contents);
    return $ret;
}

sub _get_configure_arguments {
    my ($args) = @_;

    # Handle a scalar or an array (scalar for single-lib,
    # array of args for multi-lib)
    if (ref($args) eq "") {
        my $tmp = $args;
        undef $args;
        push(@$args, $tmp);
    }

    # Otherwise we already have an array ref

    # Massage the configure arguments a bit into something
    # sane for a user of the source RPM
    my @ret;
    foreach my $arg (@$args) {

        # Convert the hard-coded prefix to the RPM %_prefix macro
        $arg =~ s/$configure_prefix/%_prefix/g;

        # Convert newlines to spaces
        $arg =~ s/\n|\r/ /g;

        # Pull out any options that use an absolute path
        # which the user may not have access to
        $arg =~ s/(?:\S+=)\/\S+//g;

        push(@ret, $arg);
    }

    return \@ret;
}

# Pass a directory to this subroutine that has already undergone autogen.sh.
# Return the tarball name.
#
# TODO: Get contrib/make_dist_tarball to perform this step
sub _make_dist_tarball {
    my ($dir, $name) = @_;

    my $ret;
    my $temp_dir = tempdir(TEMPLATE => "XXXXXX-mtt-dist-tarball-scratch", DIR => "/tmp");
    MTT::DoCommand::Cmd(1, "cp -r $dir $temp_dir/$name");

    # If the copy operation was successful, tar up the sources
    if (-d "$temp_dir/$name") {
        MTT::DoCommand::Pushdir($temp_dir);

        # Clean up any files that should not be included in the source RPM
        MTT::DoCommand::Pushdir($name);
        MTT::DoCommand::Cmd(1, "make clean");
        MTT::DoCommand::Popdir();

        # Remove versioning data and logs from the source tarball
        MTT::DoCommand::Cmd(1, "find $name | grep -E \'mpi\.mod\$\|\.hg\$\|\.svn\$\' | xargs rm -rf");
        MTT::DoCommand::Cmd(1, "find $name | grep -E \'config.*.log\$\|.*make.out\$\' | xargs rm -rf");
        MTT::DoCommand::Cmd(1, "tar cf $name.tar $name");
        MTT::DoCommand::Cmd(1, "gzip $name.tar");
        MTT::DoCommand::Cmd(1, "mv $name.tar.gz $dir");
        MTT::DoCommand::Popdir();
        MTT::DoCommand::Cmd(1, "rm -rf $temp_dir");

    } else {
        return undef;
    }

    $ret = "$dir/$name.tar.gz";

    return $ret;
}

sub _setup_rpm_top_dir {
    my ($dir) = @_;

    # Set up RPM scratch area
    MTT::Files::mkdir("$dir");
    MTT::Files::mkdir("$dir/BUILD");
    MTT::Files::mkdir("$dir/RPMS");
    MTT::Files::mkdir("$dir/RPMS/i386");
    MTT::Files::mkdir("$dir/RPMS/i586");
    MTT::Files::mkdir("$dir/RPMS/i686");
    MTT::Files::mkdir("$dir/RPMS/x86_64");
    MTT::Files::mkdir("$dir/RPMS/noarch");
    MTT::Files::mkdir("$dir/RPMS/athlon");
    MTT::Files::mkdir("$dir/SOURCES");
    MTT::Files::mkdir("$dir/SPECS");
    MTT::Files::mkdir("$dir/SRPMS");
}

# Setup the (Solaris) Installer.
sub _setup_installer {
    my ($ini, $section) = @_;

    # Fetch Install_Utilities using Mercurial
    my $installer_hg_url = Value($ini, $section, "clustertools_installer_hg_url");

    # Setup the Installer, if we pointed at one
    my $ret;
    if ($installer_hg_url) {

        # The installer is Solaris-based, and the installer URL is a
        # local dir
        if ((! -d $installer_hg_url) or ($os !~ /SunOS/i)) {
            Verbose("$package: Skipping the Installer setup.\n" .
                    "$installer_hg_url does not exist, and/or " .
                    "the Installer will not run on $os.\n");
            return undef;
        }

        my $params;
        $params->{cmd}        = "hg";
        $params->{subcommand} = "clone";
        $params->{url}        = $installer_hg_url;
        $params->{dirname}    = basename($installer_hg_url);
        MTT::Module::Run("MTT::Common::SCM::Mercurial", "Checkout", $params);

        my $installer_dir_src = basename($installer_hg_url);
        MTT::DoCommand::Pushdir($installer_dir_src);

        # Build the Install_Utilities (OMPIompiat package)
        my $cwd = MTT::DoCommand::cwd();
        $ret = "$cwd/Install_Utilities";

        my $cmd = "make all install DESTDIR=$ret";
        my $x = MTT::DoCommand::Cmd(1, $cmd);

        if (0 != $x->{exit_status}) {
            Warning("$package: Error in building the Installer.\n");
        }

        MTT::DoCommand::Popdir();
    }

    Debug("_setup_installer returning $ret\n");
    return $ret;
}

# Return a list of .so files needed for Sun Studio
# C++ programs (e.g., ompi_info)
sub _find_sun_studio_libc_libraries {
    my $suncc = FindProgram(qw(suncc));
    my $dirname_suncc = dirname($suncc);

    # Is there a way we can get these setup to mirror the way
    # they're actually linked in the Studio directory? E.g.,
    #
    #   libCrun.so -> libCrun.so.1
    #
    my @libs = ("libCrun*1", "libCstd*1", "libmtsk*1");
    my @dirs = ("$dirname_suncc/../prod/usr/lib", "$dirname_suncc/../rtlibs", "$dirname_suncc/../lib");

    my @ret;
    foreach my $dirname (@dirs) {
        foreach my $lib (@libs) {
            my ($l) = glob "$dirname/$lib";
            push(@ret, $l) if (-e $l);
        }
    }
    return \@ret;
}

1;
