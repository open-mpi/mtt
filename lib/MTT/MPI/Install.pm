#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2007 Cisco Systems, Inc.  All rights reserved.
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
# test_result (OUT) => 0 or 1; whether the build succeeded or not
# result_message (OUT) => a message describing the result
# mpi_get_section_name (IN) => name of the INI file section for this build
# configure_arguments (IN) => arguments passed to configure when built
# configure_stdout (OUT) => result_stdout and result_stderr from running configure
# vpath_mode (IN) => none, relative, absolute (0, 1, 2)
# configdir (IN) => where configure was invoked relative to the source
#     tree
# builddir (IN) => location of build dir (will not exist if build was
#     successful)
# srcdir (IN) => (relative) source tree
# abs_srcdir (IN) => absolute source tree (will not exist if build was
#     successful)
# merge_stdout_stderr (IN) => 0 or 1; whether result_stdout was combined with result_stderr
#     or not
# make_all_arguments (IN) => arguments passed to "make all"
# result_stdout (OUT) => result_stdout from the installation process (or result_stdout and
#     result_stderr if merge_stdout_stderr == 1)
# result_stderr (OUT) => result_stderr from the installation process (or nonexistant
#     if merge_stdout_stderr == 1)

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
use Time::Local;
use MTT::DoCommand;
use MTT::Values;
use MTT::INI;
use MTT::Messages;
use MTT::Module;
use MTT::Reporter;
use MTT::MPI;
use MTT::Defaults;
use Data::Dumper;
use File::Basename;
use Env::Modulecmd;

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
    my ($ini, $ini_full, $install_dir, $force) = @_;

    Verbose("*** MPI install phase starting\n");
    
    # Save the environment
    my %ENV_SAVE = %ENV;

    # Go through all the sections in the ini file looking for section
    # names that begin with "MPI Install:"
    $install_base = $install_dir;
    MTT::DoCommand::Chdir($install_base);
    foreach my $section ($ini->Sections()) {
        if ($section =~ /^\s*mpi install:/) {
            Verbose(">> MPI install [$section]\n");

            # Simple section name
            my $simple_section = $section;
            $simple_section =~ s/^\s*mpi install:\s*//;

            my $mpi_get_value = Value($ini, $section, "mpi_get");
            if (!$mpi_get_value) {
                Warning("No mpi_get specified in [$section]; skipping\n");
                next;
            }

            # Iterate through all the mpi_get values
            my @mpi_gets = split(/,/, $mpi_get_value);
            foreach my $mpi_get_name (@mpi_gets) {
                # Strip whitespace
                $mpi_get_name =~ s/^\s*(.*?)\s*/\1/;

                # This is only warning about the INI file; we'll see
                # if we find meta data for the MPI get later
                if (!$ini_full->SectionExists("mpi get: $mpi_get_name")) {
                    Warning("Warning: MPI Get section \"$mpi_get_name\" does not seem to exist in the INI file\n");
                }

                # If we have no sources for this name, then silently
                # skip it.  Don't issue a warning because command line
                # parameters may well have dictated to skip this MPI
                # get section.
                if (!exists($MTT::MPI::sources->{$mpi_get_name})) {
                    Debug("Have no sources for MPI Get \"$mpi_get_name\", skipping\n");
                    next;
                }

                # For each MPI source
                foreach my $mpi_get_key (keys(%{$MTT::MPI::sources})) {
                    if ($mpi_get_key eq $mpi_get_name) {

                        # For each version of that source
                        my $mpi_get = $MTT::MPI::sources->{$mpi_get_key};
                        foreach my $mpi_version_key (keys(%{$mpi_get})) {
                            my $mpi_version = $mpi_get->{$mpi_version_key};

                            # We found a corresponding MPI source.
                            # Now check to see if it has already been
                            # installed.  Test incrementally so that
                            # it doesn't create each intermediate key.

                            Debug("Checking for [$mpi_get_key] / [$mpi_version_key] / [$simple_section]\n");
                            if (!$force &&
                                exists($MTT::MPI::installs->{$mpi_get_key}) &&
                                exists($MTT::MPI::installs->{$mpi_get_key}->{$mpi_version_key}) &&
                                exists($MTT::MPI::installs->{$mpi_get_key}->{$mpi_version_key}->{$simple_section})) {
                                Verbose("   Already have an install for [$mpi_get_key] / [$mpi_version_key] / [$simple_section]\n");
                            } else {
                                Verbose("   Installing MPI: [$mpi_get_key] / [$mpi_version_key] / [$simple_section]...\n");
                            
                                MTT::DoCommand::Chdir($install_base);
                                my $mpi_dir = _make_safe_dir($mpi_version->{simple_section_name});
                                MTT::DoCommand::Chdir($mpi_dir);
                            
                                # Install and restore the environment
                                _do_install($section, $ini,
                                            $mpi_version, $mpi_dir, $force);
                                %ENV = %ENV_SAVE;
                            }
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
    my ($section, $ini, $mpi_get, $this_install_base, $force) = @_;

    # Simple section name
    my $simple_section = $section;
    $simple_section =~ s/^\s*mpi install:\s*//;

    my $val;
    my $config;
    %$config = %$MTT::Defaults::MPI_install;
    # Possibly filled in by ini files
    $config->{module} = "";
        
    # Filled in automatically below
    $config->{ident} = "to be filled in below";
    $config->{section_dir} = "to be filled in below";
    $config->{version_dir} = "to be filled in below";
    $config->{srcdir} = "to be filled in below";
    $config->{abs_srcdir} = "to be filled in below";
    $config->{configdir} = "to be filled in below";
    $config->{builddir} = "to be filled in below";
    $config->{installdir} = "to be filled in below";
    $config->{setenv} = "to be filled in below";
    $config->{unsetenv} = "to be filled in below";
    $config->{prepend_path} = "to be filled in below";
    $config->{append_path} = "to be filled in below";
    $config->{bitness} = "to be filled in below";
        
    # Filled in by the module
    $config->{test_result} = MTT::Values::FAIL;
    $config->{result_message} = "to be filled in by module";
    $config->{c_bindings} = 0;
    $config->{cxx_bindings} = 0;
    $config->{f77_bindings} = 0;
    $config->{f90_bindings} = 0;
    
    $config->{full_section_name} = $section;
    $config->{simple_section_name} = $simple_section;

    # module
    $config->{module} = Value($ini, $section, "module");
    if (!$config->{module}) {
        Warning("module not specified in [$section]; skipped\n");
        return undef;
    }
    
    # Make a directory just for this section
    MTT::DoCommand::Chdir($this_install_base);
    $config->{section_dir} = _make_safe_dir($simple_section);
    MTT::DoCommand::Chdir($config->{section_dir});

    # Make a directory just for this version
    $config->{version_dir} = _make_safe_dir($mpi_get->{version});
    MTT::DoCommand::Chdir($config->{version_dir});
    
    # Load any environment modules?
    my @env_modules;
    $config->{env_modules} = Value($ini, $section, "env_module");
    if ($config->{env_modules}) {
        @env_modules = split(",", $config->{env_modules});
        Env::Modulecmd::load(@env_modules);
        Debug("Loading environment modules: @env_modules\n");
    }

    # Process setenv, unsetenv, prepend_path, and
    # append_path
    $config->{setenv} = Value($ini, $section, "setenv");
    $config->{unsetenv} = Value($ini, $section, "unsetenv");
    $config->{prepend_path} = Value($ini, $section, "prepend_path");
    $config->{append_path} = Value($ini, $section, "append_path");
    my @save_env;
    ProcessEnvKeys($config, \@save_env);
    
    # bitness
    my $tmp;
    $tmp = Value($ini, $section, "bitness");
    if ($tmp == 32) {
        $config->{bitness} = 1;
    } elsif ($tmp == 64) {
        $config->{bitness} = 2;
    } else {
        $config->{bitness} = undef;
    }

    # configure_arguments
    $tmp = Value($ini, $section, "configure_arguments");
    $config->{configure_arguments} = $tmp
        if (defined($tmp));
    
    # vpath
    $tmp = lc(Value($ini, $section, "vpath_mode"));
    $config->{vpath_mode} = $tmp
        if (defined($tmp));
    if ($config->{vpath_mode}) {
        if ($config->{vpath_mode} eq "none" ||
            $config->{vpath_mode} eq "absolute" ||
            $config->{vpath_mode} eq "relative") {
            ;
        } else {
            Warning("Unrecognized vpath mode: $val -- ignored\n");
            $config->{vpath_mode} = "none";
        }
    }
    
    # make all arguments
    $tmp = Value($ini, $section, "make_all_arguments");
    $config->{make_all_arguments} = $tmp
        if (defined($tmp));
    
    # make check
    $tmp = Logical($ini, $section, "make_check");
    $config->{make_check} = $tmp
        if (defined($tmp));
    
    # compiler name and version
    $config->{compiler_name} =
        Value($ini, $section, "compiler_name");
    if ($MTT::Defaults::System_config->{known_compiler_names} !~ /$config->{compiler_name}/) {
        Warning("Unrecognized compiler name in [$section] ($config->{compiler_name}); the only permitted names are: \"$MTT::Defaults::System_config->{known_compiler_names}\"; skipped\n");
        return;
    }
    $config->{compiler_version} =
        Value($ini, $section, "compiler_version");

    # What to do with result_stdout/result_stderr?
    my $tmp;
    $tmp = Logical($ini, $section, "save_stdout_on_success");
    $config->{save_stdout_on_success} = $tmp
        if (defined($tmp));
    $tmp = Logical($ini, $section, "merge_stdout_stderr");
    $config->{merge_stdout_stderr} = $tmp
        if (defined($tmp));
    $tmp = Value($ini, $section, "stderr_save_lines");
    $config->{stderr_save_lines} = $tmp
        if (defined($tmp));
    $tmp = Value($ini, $section, "stdout_save_lines");
    $config->{stdout_save_lines} = $tmp
        if (defined($tmp));

    # We're in the section directory.  Make a subdir for the source
    # and build.
    MTT::DoCommand::Cmd(1, "rm -rf source");
    my $source_dir = MTT::Files::mkdir("source");
    MTT::DoCommand::Chdir($source_dir);
    
    # Unpack the source and find out the subdirectory
    # name it created
    $config->{srcdir} = _prepare_source($mpi_get);
    MTT::DoCommand::Chdir($config->{srcdir});
    $config->{abs_srcdir} = cwd();
    
    # vpath mode (error checking was already done above)
    
    if (!$config->{vpath_mode} || $config->{vpath_mode} eq "" ||
        $config->{vpath_mode} eq "none") {
        $config->{vpath_mode} = 0;
        $config->{configdir} = ".";
        $config->{builddir} = $config->{abs_srcdir};
    } else {
        if ($config->{vpath_mode} eq "absolute") {
            $config->{vpath_mode} = 2;
            $config->{configdir} = $config->{abs_srcdir};
            $config->{builddir} = "$config->{version_dir}/build_vpath_absolute";
        } else {
            $config->{vpath_mode} = 1;
            $config->{configdir} = "../$config->{srcdir}";
            $config->{builddir} = "$config->{version_dir}/build_vpath_relative";
        }
        
        MTT::Files::mkdir($config->{builddir});
    }
    MTT::DoCommand::Chdir($config->{builddir});
    
    # Installdir
    $config->{installdir} = "$config->{version_dir}/install";
    MTT::Files::mkdir($config->{installdir});

    # Bump the refcount in the MPI get -- even if this install fails,
    # we need the refcount to be accurate.
    ++$mpi_get->{refcount};

    # Run the module
    my $start = timegm(gmtime());
    my $start_time = time;
    my $ret = MTT::Module::Run("MTT::MPI::Install::$config->{module}",
                               "Install", $ini, $section, $config);
    my $duration = time - $start_time . " seconds";
    
    # Detect bitness
    if ((MTT::Values::PASS == $ret->{test_result})
        && defined($ret->{bitness})) {
        $config->{bitness} = $ret->{bitness};
    }
    
    # Unload any loaded environment modules
    if ($#env_modules >= 0) {
        Debug("Unloading environment modules: @env_modules\n");
        Env::Modulecmd::unload(@env_modules);
    }

    # Analyze the return
    
    if ($ret) {
        # Send the results back to the reporter
        my $report = {
            phase => "MPI Install",

            mpi_install_section_name => $config->{simple_section_name},
            compiler_name => $config->{compiler_name},
            compiler_version => $config->{compiler_version},
            configure_arguments => $config->{configure_arguments},
            vpath_mode => $config->{vpath_mode},
            merge_stdout_stderr => "$config->{merge_stdout_stderr}",
            environment => "filled in below",

            start_timestamp => $start,
            duration => $duration,
            mpi_details => $mpi_get->{mpi_details},
            mpi_name => $mpi_get->{simple_section_name},
            mpi_version => $mpi_get->{version},

            test_result => $ret->{test_result},
            result_message => $ret->{result_message},
            client_serial => $ret->{client_serial},
            mpi_install_id => $ret->{mpi_install_id},
            result_stdout => "filled in below",
            result_stderr => "filled in below",
        };

        # See if we want to save the result_stdout
        my $want_save = 1;
        if (MTT::Values::PASS == $ret->{test_result}) {
            if (!$config->{save_stdout_on_success}) {
                $want_save = 0;
            }
        } elsif (!$ret->{result_stdout}) {
            $want_save = 0;
        }

        # If we want to, save stdout
        if ($want_save) {
            $report->{result_stdout} = $ret->{result_stdout};
        } else {
            delete $report->{result_stdout};
        }

        # $ret->{result_stderr} will be filled in on error.  If there was no
        # error, then take $ret->{make_all_stderr}.
        my $result_stderr;
        if ($ret->{result_stderr}) {
            $result_stderr = $ret->{result_stderr};
        } else {
            $result_stderr = $ret->{make_all_stderr};
        }

        # Always fill in the last bunch of lines for result_stderr
        if ($result_stderr) {
            if ($config->{stderr_save_lines} == -1) {
                $report->{result_stderr} = "$result_stderr\n";
            } elsif ($config->{stderr_save_lines} == 0) {
                delete $report->{result_stderr};
            } else {
                if ($result_stderr =~ m/((.*\n){$config->{stderr_save_lines}})$/) {
                    $report->{result_stderr} = $1;
                } else {
                    # There were less lines available than we asked
                    # for, so just take them all
                    $report->{result_stderr} = $result_stderr;
                }
            }
        } else {
            delete $report->{result_stderr};
        }

        # Did we have any environment?
        $report->{environment} = undef;
        foreach my $e (@save_env) {
            $report->{environment} .= "$e\n";
        }

        # Fill in which MPI we used
        $ret->{mpi_details} = $mpi_get->{mpi_details};
        $ret->{mpi_get_full_section_name} = $mpi_get->{full_section_name};
        $ret->{mpi_get_simple_section_name} = $mpi_get->{simple_section_name};
        $ret->{mpi_version} = $mpi_get->{version};

        # Some additional values
        $ret->{full_section_name} = $config->{full_section_name};
        $ret->{simple_section_name} = $config->{simple_section_name};
        $ret->{compiler_name} = $config->{compiler_name};
        $ret->{compiler_version} = $config->{compiler_version};
        $ret->{configure_arguments} = $config->{configure_arguments};
        $ret->{vpath_mode} = $config->{vpath_mode};
        $ret->{merge_stdout_stderr} = $config->{merge_stdout_stderr};
        $ret->{setenv} = $config->{setenv};
        $ret->{unsetenv} = $config->{unsetenv};
        $ret->{prepend_path} = $config->{prepend_path};
        $ret->{append_path} = $config->{append_path};
        $ret->{env_modules} = $config->{env_modules};
        $ret->{start_timestamp} = timegm(gmtime());
        $ret->{refcount} = 0;

        # Delete keys with empty values
        foreach my $k (keys(%$report)) {
            if ($report->{$k} eq "") {
                delete $report->{$k};
            }
        }
        
        # Save the results in an ini file so that we save all the
        # result_stdout, etc.
        WriteINI("$config->{version_dir}/$installed_file",
                 $installed_section, $ret);
        
        # All of the data has been saved to an INI file, so reclaim
        # potentially a big chunk of memory...
        delete $ret->{result_stdout};
        delete $ret->{result_stderr};
        delete $ret->{configure_stdout};
        delete $ret->{make_all_stdout};
        delete $ret->{make_all_stderr};
        delete $ret->{make_check_stdout};
        delete $ret->{make_install_stdout};
        
        # Submit to the reporter, and receive a serial
        my $serials = MTT::Reporter::Submit("MPI install", $simple_section, $report);

        # Merge in the serials from the MTTDatabase
        my $module = "MTTDatabase";
        foreach my $k (keys %{$serials->{$module}}) {
            $ret->{$k} = $serials->{$module}->{$k};
        }

        # Add the data in the global $MTT::MPI::installs table
        $MTT::MPI::installs->{$mpi_get->{simple_section_name}}->{$mpi_get->{version}}->{$simple_section} = $ret;
        MTT::MPI::SaveInstalls($install_base);

        # Successful build?
        if (MTT::Values::PASS == $ret->{test_result}) {
            # If it was successful, there's no need for
            # the source or build trees anymore
            # JMS: this is not right -- if there is a problem with
            # (for example) test build, then we might want the MPI
            # source around (e.g., running a debugger)
            
            if (exists $ret->{abs_srcdir}) {
                Verbose("Removing source dir: $ret->{abs_srcdir}\n");
                MTT::DoCommand::Cmd(1, "rm -rf $ret->{abs_srcdir}");
            }
            if (exists $ret->{builddir}) {
                Verbose("Removing build dir: $ret->{builddir}\n");
                MTT::DoCommand::Cmd(1, "rm -rf $ret->{builddir}");
            }

            # Drop some environment variable files to make this tree
            # easy to access (e.g., set PATH, LD_LIBRARY_PATH,
            # MANPATH)
            # sh-flavored shells
            my $file = "$config->{version_dir}/mpi_installed_vars.sh";
            open (FILE, ">$file");
            print FILE "#!/bin/sh
# This file automatically generated by the mtt client
# on `date`.
# DO NOT EDIT; CHANGES WILL BE LOST!

MPI_ROOT=$ret->{installdir}
export MPI_ROOT
PATH=$ret->{bindir}:\$PATH
export PATH
LD_LIBRARY_PATH=$ret->{libdir}:\$LD_LIBRARY_PATH
export LD_LIBRARY_PATH\n";
            close(FILE);
            chmod(0755, $file);

            # csh-flavored shells
            my $file = "$config->{version_dir}/mpi_installed_vars.csh";
            open (FILE, ">$file");
            print FILE "#!/bin/csh
# This file automatically generated by the mtt client
# on `date`.
# DO NOT EDIT; CHANGES WILL BE LOST!

setenv MPI_ROOT $ret->{installdir}
set path = ($ret->{bindir} \$path)
if (\$?LD_LIBRARY_PATH == 0) then
    setenv LD_LIBRARY_PATH $ret->{libdir}
else
    setenv LD_LIBRARY_PATH $ret->{libdir}:\$LD_LIBRARY_PATH
endif\n";
            close(FILE);
            chmod(0755, $file);

            # modulefile
            my $file = "$config->{version_dir}/mpi_installed_vars.module";
            open (FILE, ">$file");
            print FILE "#%Module1.0
# This file automatically generated by the mtt client
# on `date`.
# DO NOT EDIT; CHANGES WILL BE LOST!

setenv MPI_ROOT $ret->{installdir}
prepend-path PATH $ret->{bindir}
prepend-path LD_LIBRARY_PATH $ret->{libdir}\n";
            close(FILE);

            Verbose("   Completed MPI install successfully\n");
        } else {
            Warning("Failed to install [$section]: $ret->{result_message}\n");
            Verbose("   Completed MPI install unsuccessfully\n");
        }
    } else {
        Verbose("   Skipped MPI install\n");
    }
}

1;
