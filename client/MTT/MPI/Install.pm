#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::MPI::Install;

########################################################################
# Install MPI phase
########################################################################

# The output of this phase is the @MTT::MPI::installs array
# of structs, each with the following members (IN means that these
# values are passed down to the install module; OUT means that they are
# filled in by the module during the install):

# Fields dealing with the build:
# ------------------------------

# module (IN) => name of the module that built the MPI
# success (OUT) => 0 or 1; whether the build succeeded or not
# result_message (OUT) => a message describing the result
# section_name (IN) => name of the INI file section for this build
# configure_args (IN) => arguments passed to configure when built
# configure_stdout (OUT) => stdout and stderr from running configure
# vpath_mode (IN) => none, relative, absolute
# configdir (IN) => where configure was invoked relative to the source
#     tree
# builddir (IN) => location of build dir (will not exist if build was
#     successful)
# srcdir (IN) => (relative) source tree
# abs_srcdir (IN) => absolute source tree (will not exist if build was
#     successful)
# std_combined (IN) => 0 or 1; whether stdout was combined with stderr
#     or not
# make_all_args (IN) => arguments passed to "make all"
# make_all_stdout (OUT) => stdout from "make all" (or stdout and
#     stderr if std_combined == 1)
# make_all_stderr (OUT) => stderr from "make all" (blank if
#     std_combined == 1)
# make_check (IN) => 0 or 1; whether we ran "make check" or not (only
#     observed if the build was successful)
# make_check_stdout (OUT) => stdout and stderr from "make check" (only
#     if make_check == 1)
# test_compile_stdout (OUT) => stdout and stderr from trivial test
#     compile/links from the build, only exists on failure

# Other fields:
# -------------
# section_dir (IN) => top-level directory for each build/install
# compiler_name (IN) => name of the compiler (from ini file)
# compiler_version (IN) => version of the compiler (from the ini file)
# installdir (OUT) => --prefix location; MPI will be installed there
# bindir (OUT) => location of MPI binaries such as mpicc, mpirun, etc.
# libdir (OUT) => location of MPI libraries that need to be in
#     LD_LIBRARY_PATH to run MPI apps
# setenv (IN) => any setenv's from the ini file
# unsetenv (IN) => any unsetenv's from the ini file
# prepend-path (IN) => any prepend-path's from the ini file
# append-path (IN) => any append-path's from the ini file
# c_bindings (OUT) => logical, whether the C MPI bindings are available
# cxx_bindings (OUT) => logical, whether the C++ MPI bindings are available
# f77_bindings (OUT) => logical, whether the F77 MPI bindings are available
# f90_bindings (OUT) => logical, whether the F90 MPI bindings are available

# If a build is successful, the MPI will be installed and the source
# and build trees will be deleted.  A number of trivial MPI test
# programs are compiled and linked against the installation to verify
# that the build was good (hello world kinds of MPI programs in C,
# C++, F77, and F90 if each of the language bindings are present).

# This module calls BuildMPI/*.pm sub-modules to actually
# build/install the MPI.  The sub-module's "Build" method is invoked
# with a single hash containing the fields listed above.  All the "IN"
# fields are passed down by this module to the build module; all the
# OUT fields are expected to be filled in (as relevant) by the build
# module.  It is not necessary to fill in *every* field; for example,
# if a build fails, there is no need to put anything in
# "make_check_stdout" because it clearly couldn't have been run.

########################################################################

use strict;
use Cwd;
use POSIX qw(strftime);
use MTT::DoCommand;
use MTT::Values;
use MTT::INI;
use MTT::Messages;
use MTT::Module;
use MTT::Reporter;
use MTT::MPI;
use MTT::Constants;
use Data::Dumper;
use File::Basename;

# File to keep data about builds
my $installed_file = "mpi_installed.ini";

# Section in the ini file where info is located
my $installed_section = "mpi_installed";

# Where the top-level installation tree is
my $install_base;

#--------------------------------------------------------------------------

sub _make_safe_dir {
    my ($ret) = @_;

    $ret = MTT::Files::make_safe_filename($ret);
    return MTT::Files::mkdir($ret);
}

#--------------------------------------------------------------------------

sub Install {
    my ($ini, $install_dir, $force) = @_;

    Verbose("*** MPI install phase starting\n");
    
    # Save the environment
    my %ENV_SAVE = %ENV;

    # Go through all the sections in the ini file looking for section
    # names that begin with "MPI Install:"
    $install_base = $install_dir;
    chdir($install_base);
    foreach my $section ($ini->Sections()) {
        if ($section =~ /^\s*mpi install:/) {
            Verbose(">> MPI install [$section]\n");
            my $skip = Logical($ini, $section, "skip");
            if ($skip) {
                Verbose("   Skipped\n");
                next;
            }

            # Find a corresponding source for this mpi_name
            my $mpi_name = Value($ini, $section, "mpi_name");
            if (!$mpi_name) {
                Warning("No mpi_name specified in [$section]; skipping\n");
                next;
            }

            # For each MPI source
            foreach my $mpi_section_key (keys(%{$MTT::MPI::sources})) {
                # For each unique instance of that source
                my $mpi_section = $MTT::MPI::sources->{$mpi_section_key};
                foreach my $mpi_unique_key (keys(%{$mpi_section})) {
                    my $mpi_source = $mpi_section->{$mpi_unique_key};
                    if ($mpi_source->{mpi_name} = $mpi_name) {

                        # We found a corresponding MPI source.  Now
                        # check to see if it has already been built.
                        # Test incrementally so that it doesn't create
                        # each intermediate key.
                        Debug("Checking for $mpi_name [$mpi_section_key] / [$mpi_source->{section_name}] / $section\n");
                        if (!$force &&
                            exists($MTT::MPI::installs->{$mpi_section_key}) &&
                            exists($MTT::MPI::installs->{$mpi_section_key}->{$mpi_unique_key}) &&
                            exists($MTT::MPI::installs->{$mpi_section_key}->{$mpi_unique_key}->{$section})) {
                            Verbose("   Already have an install for $mpi_name [$mpi_source->{section_name}]\n");
                        } else {
                            Verbose("   Installing MPI: $mpi_name / [$mpi_source->{section_name}]...\n");

                            chdir($install_base);
                            my $mpi_dir = _make_safe_dir($mpi_source->{section_name});
                            chdir($mpi_dir);
                            $mpi_dir = _make_safe_dir($mpi_source->{unique_id});
                            chdir($mpi_dir);
                            
                            # Install and restore the environment
                            _do_install($section, $ini,
                                        $mpi_source, $mpi_dir, $force);
                            %ENV = %ENV_SAVE;
                            Verbose("   Completed MPI install\n");
                        }
                    }
                }
            }
        }
    }

    Verbose("*** MPI install phase complete\n");
}

#--------------------------------------------------------------------------

sub _prepare_source {
    my ($mpi) = @_;

    $mpi->{prepare_for_install} =~ m/(.+)::(\w+)$/;
    my $module = $1;
    my $method = $2;

    return MTT::Module::Run($module, $method, $mpi, cwd());
}

#--------------------------------------------------------------------------

# Install an MPI from sources
sub _do_install {
    my ($section, $ini, $mpi, $this_install_base, $force) = @_;

    # Loop through all the configuration values in this
    # section (with defaults)

    my $val;
    my $config = {
        # Possibly filled in by ini files
        configure_args => "",
        vpath_mode => "none",
        make_all_args => "",
        make_check => 1,
        module => "",
        std_combined => 0,
        
        # Filled in automatically below
        ident => "to be filled in below",
        section_dir => "to be filled in below",
        srcdir => "to be filled in below",
        abs_srcdir => "to be filled in below",
        configdir => "to be filled in below",
        builddir => "to be filled in below",
        installdir => "to be filled in below",
        setenv => "to be filled in below",
        unsetenv => "to be filled in below",
        prepend_path => "to be filled in below",
        append_path => "to be filled in below",
        
        # Filled in by the module
        success => 0,
        result_message => "",
        bindir => "",
        libdir => "",
        configure_stdout => "",
        make_all_stdout => "",
        make_all_stderr => "",
        make_check_stdout => "",
        c_bindings => 0,
        cxx_bindings => 0,
        f77_bindings => 0,
        f90_bindings => 0,
    };
    
    $config->{section_name} = $section;

    # module
    $config->{module} = Value($ini, $section, "module");
    if (!$config->{module}) {
        Warning("module not specified in [$section]; skipped\n");
        return undef;
    }
    
    # Make a directory just for this section
    chdir($this_install_base);
    $config->{section_dir} = _make_safe_dir($section);
    chdir($config->{section_dir});
    
    # Process setenv, unsetenv, prepend_path, and
    # append_path
    $config->{setenv} = Value($ini, $section, "setenv");
    $config->{unsetenv} = Value($ini, $section, "unsetenv");
    $config->{prepend_path} = Value($ini, $section, "prepend_path");
    $config->{append_path} = Value($ini, $section, "append_path");
    my @save_env;
    ProcessEnvKeys($config, \@save_env);
    
    # configure_args
    $config->{configure_args} =
        Value($ini, $section, "configure_args");
    
    # vpath
    $config->{vpath_mode} = lc(Value($ini, $section, "vpath"));
    if ($config->{vpath_mode}) {
        if ($config->{vpath_mode} eq "none" ||
            $config->{vpath_mode} eq "absolute" ||
            $config->{vpath_mode} eq "relative") {
            ;
        } else {
            Warning("Unrecognized vpath mode: $val -- ignored\n");
            delete $config->{vpath_mode};
        }
    }
    
    # separate stdout/stderr
    $config->{std_combined} = 
        ! Logical($ini, $section, "separate_stdout_stderr");
    
    # make all args
    $config->{make_all_args} = 
        Value($ini, $section, "make_all_args");
    
    # make check
    $config->{make_check} = 
        Logical($ini, $section, "make_check");
    
    # compiler name and version
    $config->{compiler_name} =
        Value($ini, $section, "compiler_name");
    if (join(' ', @MTT::Constants::known_compiler_names) !~ /$config->{compiler_name}/) {
        Warning("Unrecognized compiler name in [$section] ($config->{compiler_name}); the only permitted names are: \"@MTT::Constants::known_compiler_names\"; skipped\n");
        return;
    }
    $config->{compiler_version} =
        Value($ini, $section, "compiler_version");
    
    # We're in the section directory.  Make a subdir for
    # the source and build.
    MTT::DoCommand::Cmd(1, "rm -rf source");
    my $source_dir = MTT::Files::mkdir("source");
    chdir($source_dir);
    
    # Unpack the source and find out the subdirectory
    # name it created
    $config->{srcdir} = _prepare_source($mpi);
    chdir($config->{srcdir});
    $config->{abs_srcdir} = cwd();
    
    # configdir and builddir
    
    if (!$config->{vpath_mode} || $config->{vpath_mode} eq "" ||
        $config->{vpath_mode} eq "none") {
        $config->{configdir} = ".";
        $config->{builddir} = $config->{abs_srcdir};
    } else {
        if ($config->{vpath_mode} eq "absolute") {
            $config->{configdir} = $config->{abs_srcdir};
            $config->{builddir} = "$config->{section_dir}/build_vpath_absolute";
        } else {
            $config->{configdir} = "../$config->{srcdir}";
            $config->{builddir} = "$config->{section_dir}/build_vpath_relative";
        }
        
        MTT::Files::mkdir($config->{builddir});
    }
    chdir($config->{builddir});
    
    # Installdir
    
    $config->{installdir} = "$config->{section_dir}/install";
    MTT::Files::mkdir($config->{installdir});
    
    # Run the module
    my $start = localtime;
    my $ret = MTT::Module::Run("MTT::MPI::Install::$config->{module}",
                               "Install", $config);
    my $stop = localtime;
    
    # Analyze the return
    
    if ($ret) {

        # Send the results back to the reporter
        my $report = {
            phase => "MPI Install",

            section_name => $config->{section_name},
            compiler_name => $config->{compiler_name},
            compiler_version => $config->{compiler_version},
            flags => $ret->{configure_args},
            vpath_mode => $ret->{vpath_mode},
            stdout_stderr_combined => $ret->{std_combined},
            environment => "filled in below",

            start_timestamp => $start,
            stop_timestamp => $stop,
            mpi_name => $mpi->{mpi_name},
            mpi_section_name => $mpi->{section_name},
            mpi_version => $mpi->{version},
            mpi_unique_id => $mpi->{unique_id},

            success => $ret->{success},
            result_message => $ret->{result_message},
            stdout => "filled in below",
            stderr => "filled in below",
        };
        # On a successful build, skip the stdout -- only keep the last
        # $error_lines of stderr (which will only be there if the
        # builder separated it out, and if there were any compile/link
        # warnings)
        if (1 == $ret->{success}) {
            delete $report->{stdout};
            if ($ret->{make_all_stderr}) {
                $report->{stderr} = "$ret->{make_all_stderr}\n";
                if ($report->{stderr} =~ m/((.*\n){$MTT::Constants::error_lines_mpi_install})$/) {
                    $report->{stderr} = $1;
                }
            }
        }
        # On an unsuccessful build, only fill in the last
        # bunch of lines in stdout / stderr.
        else {
            # If we have at least $error_lines, then save
            # only the last $error_lines.  Perl is so ugly
            # it's pretty!
            if ($report->{stdout}) {
                $report->{stdout} = "$ret->{stdout}\n";
                if ($report->{stdout} =~ m/((.*\n){$MTT::Constants::error_lines_mpi_install})$/) {
                    $report->{stdout} = $1;
                }
            }
            # Ditto for stderr
            if ($report->{stderr}) {
                $report->{stderr} = "$ret->{stderr}\n";
                if ($report->{stderr} =~ m/((.*\n){$MTT::Constants::error_lines_mpi_install})$/) {
                    $report->{stderr} = $1;
                }
            }
        }
        # Did we have any environment?
        $report->{environment} = undef;
        foreach my $e (@save_env) {
            $report->{environment} .= "$e\n";
        }
        # Fill in which MPI we used
        $ret->{mpi_name} = $mpi->{mpi_name};
        $ret->{mpi_section_name} = $mpi->{section_name};
        $ret->{mpi_version} = $mpi->{version};
        $ret->{mpi_unique_id} = $mpi->{unique_id};

        # Some additional values
        $ret->{section_name} = $config->{section_name};
        $ret->{test_status} = "installed";
        $ret->{timestamp} = $report->{timestamp} = strftime("%j%Y-%H%M%S", localtime);
        $ret->{compiler_name} = $config->{compiler_name};
        $ret->{compiler_version} = $config->{compiler_version};
        $ret->{configure_args} = $config->{configure_args};
        $ret->{vpath_mode} = $config->{vpath_mode};
        $ret->{std_combined} = $config->{std_combined};
        $ret->{setenv} = $config->{setenv};
        $ret->{unsetenv} = $config->{unsetenv};
        $ret->{prepend_path} = $config->{prepend_path};
        $ret->{append_path} = $config->{append_path};

        # Delete keys with empty values
        foreach my $k (keys(%$report)) {
            if ($report->{$k} eq "") {
                delete $report->{$k};
            }
        }
        
        # Save the results in an ini file so that we save all the
        # stdout, etc.
        WriteINI("$config->{section_dir}/$installed_file",
                 $installed_section, $ret);
        
        # All of the data has been saved to an INI file, so reclaim
        # potentially a big chunk of memory...
        delete $ret->{stdout};
        delete $ret->{stderr};
        delete $ret->{configure_stdout};
        delete $ret->{make_all_stdout};
        delete $ret->{make_all_stderr};
        delete $ret->{make_check_stdout};
        
        # Submit to the reporter
        MTT::Reporter::Submit("MPI install", $section, $report);

        # Successful build?
        if (1 == $ret->{success}) {
            # If it was successful, there's no need for
            # the source or build trees anymore
            
            if (exists $ret->{abs_srcdir}) {
                Verbose("Removing source dir: $ret->{abs_srcdir}\n");
                MTT::DoCommand::Cmd(1, "rm -rf $ret->{abs_srcdir}");
            }
            if (exists $ret->{builddir}) {
                Verbose("Removing build dir: $ret->{builddir}\n");
                MTT::DoCommand::Cmd(1, "rm -rf $ret->{builddir}");
            }

            # Add the data in the global $MTT::MPI::installs table
            $MTT::MPI::installs->{$mpi->{section_name}}->{$mpi->{unique_id}}->{$section} = $ret;
            MTT::MPI::SaveInstalls($install_base);
        } else {
            Warning("Failed to install [$section]: $ret->{result_message}\n");
        }
    }
}

1;
