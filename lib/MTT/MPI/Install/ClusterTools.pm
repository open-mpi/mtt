#!/usr/bin/env perl
#
# Copyright (c) 2007-2008 Sun Microsystems, Inc.  All rights reserved.
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
use File::Basename;
use File::Temp qw(tempfile tempdir);

#--------------------------------------------------------------------------

# Global package variables
my $major_version_number;
my $release_version_number;
my $build_number;
my $full_version_number;
my $product_version;
my $compiler_name;
my $product_name = "ClusterTools";
my $package_name_prefix;
my $package_basedir;
my $configure_prefix;

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

    # Process clustertools input parameters
    # These variables are primarily only of interest to Release Engineering
    $build_number = Value($ini, $section, "clustertools_build_number");
    my $create_packages = Logical($ini, $section, "clustertools_create_packages");
    my $svn_r_number = Value($ini, $section, "clustertools_svn_r_number");

    # Set the global configure prefix
    $configure_prefix = Value($ini, $section, "clustertools_configure_prefix");

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
    $major_version_number   = Value($ini, $section, "clustertools_major_version");
    $release_version_number = Value($ini, $section, "clustertools_release_version");
    $full_version_number    = Value($ini, $section, "clustertools_full_version");
    $product_version        = Value($ini, $section, "clustertools_product_version");
    $package_name_prefix    = Value($ini, $section, "clustertools_package_name_prefix");
    $package_basedir        = Value($ini, $section, "clustertools_package_basedir");
    $package_basedir        = $package_basedir ? $package_basedir : "/opt";

    # Grab the internal repository revision number
    my $internal_r_number = $config->{module_data}->{r};

    # Update the version file
    my $greek = "r${svn_r_number}-ct${full_version_number}-b${build_number}-r${internal_r_number}";
    &_update_version_file($greek, "VERSION");

    # Update the openmpi-mca-params.conf file
    &_update_openmpi_mca_params_conf("opal/etc/openmpi-mca-params.conf");

    # Get some OMPI-module-specific config arguments
    $config->{make_all_arguments} = Value($ini, $section, "clustertools_make_all_arguments");

    # Log the make output
    my $rand_str = MTT::Values::RandomString(10);
    $config->{make_all_arguments} .= " 2>&1| tee make-$rand_str.log";

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

    # In some cases, we might need to patch the Libtool script.
    # Disable for now. This is only required because:
    #
    #   a) There's quirk in Sun Studio's f90 linker flag handling.
    #   b) Autotools links in Crun and Cstd libraries behind our backs
    #
    if ($compiler_name =~ /sun|sos/i) {
        $after_configure = \&_update_libtool_script;
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
            " --with-package-string=\"$product_name $full_version_number\"" .
            " --with-ident-string=\"@(#)RELEASE VERSION $greek\"";

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

        # Backup the config.log
        # EAM: THIS BELONGS IN ITS OWN FUNCTION, BUT HOW CAN WE PASS
        #       *MULTIPLE* CODE REFERENCES TO RUNSTEP()?
        my $rand_str = MTT::Values::RandomString(10);
        MTT::DoCommand::Cmd(1, "mv config.log config-$rand_str.log");

        $i++;
    }

    # Symlink the special arch labels (e.g., "sparcv9" and "amd64") to the generic "64"
    # (Someday the special arch labels will be deprecated)
    my ($lib_label_for_64_bit) = &_setup_architecture_dependent_labels();
    MTT::DoCommand::Pushdir("$staging_dir/lib");
    symlink($lib_label_for_64_bit, "64");
    MTT::DoCommand::Popdir();

    # Create wrapper data files
    my $wrapper_destdir = "$staging_dir/share/openmpi";
    &_create_wrapper_data_files($wrapper_destdir, $compiler_name, $wrapper_rpath, $greek);

    # Copy over the examples directory to the install area
    my $examples_dir = "$config->{abs_srcdir}/examples";
    MTT::DoCommand::Cmd(1, "cp -r $examples_dir $staging_dir");

    # Copy over the mpi.d file to the install area
    if ($os =~ /SunOS/i) {
        my $mpi_d_file = "$config->{abs_srcdir}/ompi/dtrace/mpi.d";
        MTT::DoCommand::Cmd(1, "cp $mpi_d_file $staging_dir");
    }

    # Create binary packages
    if ($create_packages) {

        # Setup the ClusterTools installer
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

            # Install Utilities for boot-strapping
            MTT::DoCommand::Cmd(1, "cp -r $installer_dir $destination_dir");
        }

        # Create Solaris or Linux (RPM) packages
        create_packages($staging_dir, $destination_dir, $install_dir);

        # Make the installer available to the post-installation steps
        my $installer_path = "$destination_dir/Install_Utilities";
        if (exists($ENV{PATH})) {
            $ENV{PATH} = "$installer_path/bin:" . $ENV{PATH};
        } else {
            $ENV{PATH} = "$installer_path/bin";
        }
    }

    # Remove the mpi.d file from the staging area
    MTT::DoCommand::Cmd(1, "rm $staging_dir/mpi.d");

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

# Setup architecture dependent labels for 64-bit (e.g., v9 and amd64)
sub _setup_architecture_dependent_labels {

    my $lib_label;
    my $include_label;
    my $compiler_args;

    if ($os =~ /SunOS/i) {
        if ($arch =~ /sparc/i) {
            $lib_label = "sparcv9";
            $include_label = "v9";
            $compiler_args = "-xarch=v9;-xarch=v9a;-xarch=v9b;-xarch=native64;-xarch=generic64;-xtarget=native64;-xtarget=generic64;-m64;";
        } elsif ($arch =~ /i386/i) {
            $lib_label = "amd64";
            $include_label = "amd64";
            $compiler_args = "-xarch=amd64;-xarch=amd64a;-xarch=native64;-xarch=generic64;-xtarget=native64;-xtarget=generic64;-m64";
        }
    } elsif ($os =~ /Linux/i) {
        $lib_label = "lib64";
        $include_label = "64";
        $compiler_args = "-m64";
    }

    return ($lib_label,
            $include_label,
            $compiler_args);
}

# Arguments:
#   1. Where we are writing the files
#   2. Compiler name: "sun" or "gnu"
#   3. -R (or -Wl,-rpath) <PATH> to be used within the wrapper data files
#   4. version for wrapper .txt files
sub _create_wrapper_data_files {
    my ($destdir, $compiler_name, $installdir, $version) = @_;
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
    my ($lib_label_for_64_bit, $include_label_for_64_bit, $compiler_args) =
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

    if ($compiler_name =~ /gnu|gcc/i) {
        $dash_r = "-Wl,-rpath,";

        # Prevent missing module files error from GCC (4.1)
        # See http://gcc.gnu.org/bugzilla/show_bug.cgi?id=30446
        # Use the workaround they proposed to get the fortran module
        $dash_m =  "";

        $linker_flags_gfortran_32 = "-I$installdir/lib " .
                                    "-J$installdir/lib";

        $linker_flags_gfortran_64 = "-I$installdir/lib/$lib_label_for_64_bit " .
                                    "-J$installdir/lib/$lib_label_for_64_bit";

    }

    $linker_flags_32 = "$dash_r/opt/mx/lib " .
                       "$dash_r$installdir/lib";
    $linker_flags_64 = "$dash_r/opt/mx/lib/$lib_label_for_64_bit " .
                       "$dash_r$installdir/lib/$lib_label_for_64_bit";

    $wrapper_data->{32}->{includedir} = "$installdir/include";
    $wrapper_data->{64}->{includedir} = "$installdir/include/$include_label_for_64_bit";
    $wrapper_data->{32}->{libdir} = "$installdir/lib";
    $wrapper_data->{64}->{libdir} = "$installdir/lib/$lib_label_for_64_bit";
    $wrapper_data->{32}->{compiler_args} = "";
    $wrapper_data->{64}->{compiler_args} = $compiler_args;
    $wrapper_data->{32}->{linker_flags} = $linker_flags_32;
    $wrapper_data->{64}->{linker_flags} = $linker_flags_64;

    # Special gfortran linker flags
    $wrapper_data->{"gfortran"}->{32}->{linker_flags} = $linker_flags_gfortran_32;
    $wrapper_data->{"gfortran"}->{64}->{linker_flags} = $linker_flags_gfortran_64;

    # For mpif90, point to mpi.mod using the -M flag
    $wrapper_data->{"f90"}->{module_option} = $dash_m;
    $wrapper_data->{"f95"}->{module_option} = $dash_m;

    # We have to either use -m32 or -m64 for Linux
    $wrapper_data->{32}->{Linux}->{compiler_flags} = "-m32";
    $wrapper_data->{64}->{Linux}->{compiler_flags} = "";

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
compiler_flags=%s
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
compiler_flags=%s
libs=%s
linker_flags=%s
required_file=$required_file
includedir=%s
libdir=%s
";

    # Incorporate the these compiler names into the data file name
    # if need be
    my $filename_labels;
    $filename_labels->{"sun"} = "";
    $filename_labels->{"sos"} = "";
    $filename_labels->{"gnu"} = "";
    $filename_labels->{"gcc"} = "";
    $filename_labels->{"vt"}  = "-vt";

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

                                        # 32-bit
                                        $wrapper_data->{32}->{compiler_args},
                                        @top_params,
                                        $wrapper_data->{32}->{$os}->{compiler_flags},
                                        $wrapper_data->{$compiler}->{libs},
                                        $wrapper_data->{32}->{linker_flags} . " " .
                                          $wrapper_data->{$underlying_compiler}->{32}->{linker_flags},
                                        $wrapper_data->{32}->{includedir},
                                        $wrapper_data->{32}->{libdir},

                                        # 64-bit
                                        $wrapper_data->{64}->{compiler_args},
                                        @top_params,
                                        $wrapper_data->{64}->{$os}->{compiler_flags},
                                        $wrapper_data->{$compiler}->{libs},
                                        $wrapper_data->{64}->{linker_flags} . " " .
                                          $wrapper_data->{$underlying_compiler}->{64}->{linker_flags},
                                        $wrapper_data->{64}->{includedir},
                                        $wrapper_data->{64}->{libdir},
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
    my ($staging_dir, $destination_dir) = @_;
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

    # Special mpi.d package that is not installed in /opt
    $packages->{"${package_name_prefix}ompir"}->{"name"} = $brand;
    $packages->{"${package_name_prefix}ompir"}->{"description"} = "$brand Root Filesystem Files";
    $packages->{"${package_name_prefix}ompir"}->{"mpi_d_package"} = 1;

    foreach my $package_name (keys %$packages) {

        # Write a pkginfo file to pass to the prototype file
        my $short_name     = $packages->{$package_name}->{"name"};
        my $description    = $packages->{$package_name}->{"description"};
        my $pkginfo_file   = _write_pkginfo_file($package_name, $short_name, $description);

        # Write a copyright file to pass to the prototype file
        my $copyright_file = _write_copyright_file();

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
            $pkgproto_args  = join(" ", map { "$_=${package_name_prefix}hpc/$product_version/$_/" } @directories);
            $prototype_file = _create_prototype_file($package_name, $pkginfo_file, $copyright_file, $pkgproto_args);
            next if (! $prototype_file);

        } elsif ($mpi_d_package) {
            $prototype_file = _create_prototype_file_mpi_d($package_name, $pkginfo_file, $copyright_file);
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
        "\nd none /usr/lib/dtrace 0755 root bin" .
        "\nf none /usr/lib/dtrace/mpi.d=mpi.d 0644 root bin";

    # Write out prototype file
    my $ret = "prototype.$package_name";
    MTT::Files::SafeWrite(1, $ret, $contents);

    return $ret;
}

# Create a prototype file for one of the opt/ packages
sub _create_prototype_file {
    my ($package_name, $pkginfo_file, $copyright_file, $pkgproto_args) = @_;

    my $cmd = "pkgproto $pkgproto_args";

    my $x = MTT::DoCommand::Cmd(1, $cmd);
    if (0 != $x->{exit_status}) {
        Warning("$package: Error in pkgproto: '$cmd'\n");
        return undef;
    }

    # Start with the prologue for the prototype file
    my $contents = _create_prototype_file_prologue($pkginfo_file, $copyright_file);
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
    my ($name, $short_name, $desc, $package_basedir) = @_;
    Debug("_write_pkginfo_file: got @_\n");

    my $pkgvers;
    $pkgvers->{"7.0"} = "1.0";
    $pkgvers->{"7.1"} = "2.0";
    $pkgvers->{"8.0"} = "3.0";
    $pkgvers->{"9.0"} = "4.0";

    # Default to a bogus release number
    $release_version_number = "unknown" if (!defined($release_version_number));

    # Set the SUNW_PKGVERS string
    my $version = $pkgvers->{$release_version_number};

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
VERSION=\"$release_version_number\"
BASEDIR=\"$package_basedir\"
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
    my $contents = "# Copyright (c) $year $vendor All rights reserved.
#                         Use is subject to license terms.
# \$COPYRIGHT\$
#
# Additional copyrights may follow";

    my $filename = "copyright";
    MTT::Files::SafeWrite(1, $filename, $contents);

    return $filename;
}

# This is admittedly a complete bastardization of 
# RPM, because we are creating a lot of dummy sections
# and files to feed to rpmbuild.
sub create_linux_packages {
    my ($staging_dir, $destination_dir, $install_dir) = @_;
    Debug("create_linux_packages: got @_\n");

    # Prepare an overarching status variable
    my $success = 1;

    MTT::DoCommand::Pushdir($staging_dir);

    my @staging_dirs = ($staging_dir);
    my $filelist = MTT::Values::Functions::find(".", \@staging_dirs);

    # Setup a scratch area for RPM creation
    my $temp_dir = tempdir(TEMPLATE => "XXXXXX-mtt-rpm-scratch", DIR => "/tmp");

    # Create a .spec file on the fly
    my $spec_file = _create_spec_file($temp_dir, $install_dir);

    # From man rpmbuild:
    #  -bb  Build a binary package (after doing the %prep,  %build,
    #       and %install stages).
    my $rpmbuild = FindProgram(qw(rpmbuild));

    my $nil = '%nil';
    my $cmd = "$rpmbuild --verbose -bb" .
              # Add $os_distro to the RPM filename format
              " --define=\"_build_name_fmt " .
                          "%%{ARCH}/" .
                          "%%{NAME}-" .
                          "%%{VERSION}-" .
                          "%%{RELEASE}." .
                          "%%{ARCH}-" .
                          "$os_distro-" .
                          "built-with-$compiler_name.rpm\" " .
              # RPM scratch area
              " --define=\"_topdir $temp_dir\"" .
              # Override the below built-in macro because it does annoying
              # things like gzipping every file in the installation
              " --define=\"suse_check $nil\"" .
              " $spec_file";

    my $ret = MTT::DoCommand::Cmd(1, $cmd);
    if (0 != $ret->{exit_status}) {
        $success = 0;
    }

    # We can use the %_build_name_fmt macro instead of this subroutine
    # &_update_rpm_file_name($temp_dir);

    MTT::DoCommand::Cmd(1, "rm -rf rpm");
    MTT::DoCommand::Cmd(1, "cp -r $temp_dir $destination_dir/rpm");
    MTT::DoCommand::Cmd(1, "rm -rf $temp_dir");

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

# For some reason RPMs are traditionally named in the below format,
# though the RPM file name is not critical to the RPMs functionality.
# (For all rpm cares, the file could even have the wrong extension.)
#
#   E.g., <product>-<version>-<release>.<arch>.rpm
#
# Since we're creating RPMs for multiple Linuxes (Linuxi?), let's
# include it in the RPM filename.
sub _update_rpm_file_name {
    my ($dir) = @_;
    Debug("_update_rpm_file_name: got @_\n");
    MTT::DoCommand::Pushdir($dir);

    my $ext = "rpm";
    my @rpms = glob "*RPMS/$arch/*.$ext";
    my $old_rpm_name;
    my $new_rpm_name;

    foreach my $rpm (@rpms) {
        $old_rpm_name = $rpm;
        $rpm =~ s/(.$ext)$/-$os_distro$1/;
        $new_rpm_name = $rpm;
        MTT::DoCommand::Cmd(1, "mv $old_rpm_name $new_rpm_name");
    }

    MTT::DoCommand::Popdir();
}

sub _create_spec_file {
    my ($rpm_top_dir, $build_root) = @_;
    Debug("_create_spec_file: got @_\n");

    # Set up RPM scratch area
    MTT::Files::mkdir("$rpm_top_dir");
    MTT::Files::mkdir("$rpm_top_dir/BUILD");
    MTT::Files::mkdir("$rpm_top_dir/RPMS");
    MTT::Files::mkdir("$rpm_top_dir/RPMS/i386");
    MTT::Files::mkdir("$rpm_top_dir/RPMS/i586");
    MTT::Files::mkdir("$rpm_top_dir/RPMS/i686");
    MTT::Files::mkdir("$rpm_top_dir/RPMS/x86_64");
    MTT::Files::mkdir("$rpm_top_dir/RPMS/noarch");
    MTT::Files::mkdir("$rpm_top_dir/RPMS/athlon");
    MTT::Files::mkdir("$rpm_top_dir/SOURCES");
    MTT::Files::mkdir("$rpm_top_dir/SPECS");
    MTT::Files::mkdir("$rpm_top_dir/SRPMS");

    my $contents = "
#
# This file was automatically generated by MTT.
# Any changes made to it will likely be lost!
#
    
Summary: A powerful implementaion of MPI
Name: $product_name
Version: $full_version_number
Release: $build_number
Vendor: $vendor
License: BSD
Group: Development/Libraries
URL: http://www.sun.com/software/products/clustertools
AutoReqProv: no
Distribution: $vendor
Packager: ompi-clustertools-ext\@sun.com
BuildRoot: $build_root

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
%attr(-, root, root) $configure_prefix/bin
%attr(-, root, root) $configure_prefix/include
%attr(-, root, root) $configure_prefix/lib
%attr(-, root, root) $configure_prefix/man
%attr(-, root, root) $configure_prefix/share
%attr(-, root, root) $configure_prefix/etc
%attr(-, root, root) $configure_prefix/examples
";

    my $ret = "$rpm_top_dir/SPECS/$product_name-$full_version_number-$build_number.spec";

    MTT::Files::SafeWrite(1, $ret, $contents);
    return $ret;
}

# MAGIC REGEXP ALERT! This routine contains some magic
# strings that are found in an autogenerated libtool scripts.
# It has been tested with the following libtool, but may need
# to be adjusted for different versions!
#
#   $ libtool --version
#   ltmain.sh (GNU libtool) 2.2
#
sub _update_libtool_script {
    my ($file) = @_;
    Debug("_update_libtool_script: got @_\n");

    $file = "./libtool" if (! -e $file);

    # Keep a backup copy of the file lying around for debugging
    # purposes
    MTT::DoCommand::Cmd(1, "cp $file $file.orig");

    # Grab uname OS variable
    my $os = `uname -s`;
    chomp $os;

    my $bad_var = "whole_archive_flag_spec";

    # We could be more precise here with this REGEXP!
    # Perhaps even better would be to place a patch in
    # (e.g., config/foo.diff)
    # There is precedent for doing this in autogen.sh. See this file:
    # https://svn.open-mpi.org/trac/ompi/browser/trunk/config/lt21a-pathCC.diff
    # To be absolutely sure, we really want to match all the funny
    # characters (e.g., $, \, {, -, ...) like below,
    # but to be expedient, we can just fill in the oddball
    # characters with wildcards (.). 
    # my $bad_pattern1 = '\${wl}-soname \$wl\$soname';
    my $bad_pattern1 = '..{wl}-soname ..wl..soname';
    
    # Read in the libtool script file
    my $contents = MTT::Files::Slurp($file);

    if (!$contents) {
        Error("Couldn't Slurp $file!\n");
    }

    my $comment1 = "
# $bad_var has been commented out by MTT to avoid linker flag errors
# in Sun Studio 12 (Linux). See the below link for the purpose of this
# variable:
# http://www.gnu.org/software/libtool/manual.html#index-whole_005farchive_005fflag_005fspec-352
";

    my $comment2 = "
# $bad_pattern1 has been removed by MTT to avoid the below compiler
# error(s): 
#   f90: Warning: Option -Wl,-soname passed to ld, if ld is invoked, ignored otherwise
#   f90: Warning: Option -Wl,libmpi_f90.so.0 passed to ld, if ld is invoked, ignored otherwise
#   /usr/bin/ld: unrecognized option '-Wl,-soname'
#   /usr/bin/ld: use the --help option for usage information
#   make[2]: *** [libmpi_f90.la] Error 1
";

    my $bad_pattern2 ='(\n# ### BEGIN LIBTOOL TAG CONFIG: FC.*)\n(wl="-Wl,")';
    my $good_pattern2 = '
# MTT has reassigned wl to "" because Sun Studio f90 (for Linux) does
# not pass -Wl values to the GNU linker (/usr/bin/ld)
wl=""';

    my $bad_pattern3 ='(\n# ### BEGIN LIBTOOL TAG CONFIG: CXX.*)\n(postdeps="(?:-library=Cstd)\s*(?:-library=Crun)?")';
    my $good_pattern3 = '
# MTT has commented out postdeps so that libCstd.so and libCrun.so are not
# linked in to libmpi_cxx.so. The autogen.sh patch for this same issue was
# supposed to take care of this, but apparently Autosomething-or-other has
# apparently usurped that patch and thrown in the bad -library flags.
postdeps=""
';

    # Comment out whole_archive_flag_spec
    # $contents =~ s/($bad_var\=.*)/$comment1# $1/;
    
    # Comment out this to avoid -Wl
    # $contents =~ s/$bad_pattern1//g;
    # $contents .= $comment2;

    # From perldoc perlre, the "s" modifier in s///s:
    #   Treat string as single line. That is, change "." to match any character
    #   whatsoever, even a newline, which normally it would not match. Used
    #   together, as /ms, they let the "." match any character whatsoever,
    #   while still allowing "^" and "$" to match, respectively, just after and
    #   just before newlines within the string.

    if ($os =~ /Linux/i) {
        Verbose("$package: We need to patch $file for libmpi_f90.\n");

        # Set wl to "" for f90
        $contents =~ s/$bad_pattern2/$1\n# $2\n$good_pattern2/s;
    }

    # Comment this postdeps var out of CXX section
    # postdeps="-library=Cstd -library=Crun"
    Verbose("$package: Patching $file to avoid linking with libCstd and libCrun.\n");
    $contents =~ s/$bad_pattern3/$1\n# $2\n$good_pattern3/s;
    
    # Write changed file out
    MTT::Files::SafeWrite(1, $file, $contents);
}

# Add "set -x" to libtool script
sub _set_x_in_libtool_script {
    my ($file) = @_;
    Debug("_set_x_in_libtool_script: got @_\n");

    $file = "./libtool" if (! -e $file);

    # Keep a backup copy of the file lying around for debugging
    # purposes
    MTT::DoCommand::Cmd(1, "cp $file $file.orig");

    Verbose("$package: Adding 'set -x' to $file.\n");

    # Read in the libtool script file
    my $contents = MTT::Files::Slurp($file);

    if (!$contents) {
        Error("Couldn't Slurp $file!\n");
    }

    my $search_pattern = '\n\s*\n';
    my $replace_pattern = '

# Set debug
set -x

';

    # set -x
    $contents =~ s/$search_pattern/\n$replace_pattern\n/s;
    
    # Write changed file out
    MTT::Files::SafeWrite(1, $file, $contents);
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
        MTT::Module::Run("MTT::Common::SCM::Mercurial", "Checkout", $params);

        my $installer_dir_src = basename($installer_hg_url);
        MTT::DoCommand::Pushdir($installer_dir_src);

        # Build the Install_Utilities (OMPIompiat package)
        my $cwd = cwd();
        $ret = "$cwd/Install_Utilities";

        my $cmd = "make all install DESTDIR=$ret";
        my $x = MTT::DoCommand::Cmd(1, $cmd);

        if (0 != $x->{exit_status}) {
            Warning("$package: Error in building the Installer.\n");
        }

        MTT::DoCommand::Popdir();
    }

    Debug("$package: returning $ret\n");
    return $ret;
}

1;
