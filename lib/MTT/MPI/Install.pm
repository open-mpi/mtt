#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2007 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
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
use MTT::EnvModule;
use MTT::Util;
use Data::Dumper;
use File::Basename;

# File to keep data about builds
my $installed_file = "mpi_installed.ini";

# Section in the ini file where info is located
my $installed_section = "mpi_installed";

# Where the top-level installation tree is
my $install_base;

# Where the MPI library is
our $install_dir;

# What we call this phase
my $phase_name = "MPI install";

#--------------------------------------------------------------------------

sub _make_random_dir {
    my ($len) = @_;

    # Make a directory and ensure it's mine and mine alone (NOTE:
    # assumes a single writer)
    while (1) {
        my $ret = MTT::Values::RandomString($len);
        if (! -d $ret) {
            Debug("Unique directory: $ret\n");
            return _make_safe_dir($ret);
        }
    }
}

#--------------------------------------------------------------------------

sub _make_safe_dir {
    my ($ret) = @_;

    $ret = MTT::Files::make_safe_filename($ret);
    return MTT::Files::mkdir($ret);
}

#--------------------------------------------------------------------------

sub Install {
    my ($ini, $ini_full, $install_dir, $force) = @_;

    $MTT::Globals::Values->{active_phase} = $phase_name;
    Verbose("*** $phase_name phase starting\n");
    
    # Save the environment
    my %ENV_SAVE = %ENV;

    # Go through all the sections in the ini file looking for section
    # names that begin with "MPI Install:"
    $install_base = $install_dir;
    MTT::DoCommand::Chdir($install_base);
    foreach my $section ($ini->Sections()) {

        # See if we're supposed to terminate.  Only check in the
        # outtermost and innermost loops (even though we *could* check
        # at every loop level); that's good enough.
        last
            if (MTT::Util::find_terminate_file());

        if ($section =~ /^\s*mpi install:/) {
            Verbose(">> $phase_name [$section]\n");

            # Simple section name
            my $simple_section = GetSimpleSection($section);

            my $mpi_get_value = Value($ini, $section, "mpi_get");
            if (!$mpi_get_value) {
                Warning("No mpi_get specified in [$section]; skipping\n");
                next;
            }

            # Process input parameters for before/after steps
            my @step_params_list = (
                "before_install",
                "before_install_timeout",
                "after_install",
                "after_install_timeout",
            );

            my $step_params;
            foreach my $p (@step_params_list) {
                # Evaluate these in _run_step because they may contain commands
                # we want to run at a specific time (e.g., before or after
                # installation)
                $step_params->{$p} = $ini->val($section, $p);
            }

            # Iterate through all the mpi_get values
            my @mpi_gets = MTT::Util::split_comma_list($mpi_get_value);
            foreach my $mpi_get_name (@mpi_gets) {
                # Strip whitespace
                $mpi_get_name =~ s/^\s*(.*?)\s*/\1/;
                $mpi_get_name = lc($mpi_get_name);

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

                # Make the active INI section name known
                $MTT::Globals::Values->{active_section} = $section;

                # For each MPI source
                foreach my $mpi_get_key (keys(%{$MTT::MPI::sources})) {
                    if ($mpi_get_key eq $mpi_get_name) {

                        # For each version of that source
                        my $mpi_get = $MTT::MPI::sources->{$mpi_get_key};
                        foreach my $mpi_version_key (keys(%{$mpi_get})) {

                            # See if we're supposed to terminate.
                            # Only check in the outtermost and
                            # innermost loops (even though we *could*
                            # check at every loop level); that's good
                            # enough.
                            last
                                if (MTT::Util::find_terminate_file());

                            my $mpi_version = $mpi_get->{$mpi_version_key};

                            # We found a corresponding MPI source.
                            # Now check to see if it has already been
                            # installed.  Test incrementally so that
                            # it doesn't create each intermediate key.

                            Debug("Checking for [$mpi_get_key] / [$mpi_version_key] / [$simple_section]\n");
                            if (!$force &&
                                defined(MTT::Util::does_hash_key_exist($MTT::MPI::installs, qw/$mpi_get_key $mpi_version_key $simple_section/))) {
                                Verbose("   Already have an install for [$mpi_get_key] / [$mpi_version_key] / [$simple_section]\n");
                            } else {
                                Verbose("   Installing MPI: [$mpi_get_key] / [$mpi_version_key] / [$simple_section]...\n");
                            
                                $MTT::Globals::Internals->{mpi_get_name} =
                                    $mpi_get_key;
                                $MTT::Globals::Internals->{mpi_install_name} = $simple_section;
                                my $mpi_dir = _make_random_dir(4);
                                MTT::DoCommand::Chdir($mpi_dir);
                            
                                # Perform specified steps before the Install
                                _run_step($step_params, "before", $ini, $section);

                                # Install and restore the environment
                                _do_install($section, $ini,
                                            $mpi_version, $mpi_dir, $force);
                                delete $MTT::Globals::Internals->{mpi_get_name};
                                delete $MTT::Globals::Internals->{mpi_install_name};

                                # Do specified steps after the Install such as
                                # creating a tarball, installing software on
                                # whole clusters, etc.
                                _run_step($step_params, "after", $ini, $section);

                                %ENV = %ENV_SAVE;
                            }
                        }
                    }
                }
            }
        }
    }

    Verbose("*** $phase_name phase complete\n");
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
    $config->{description} = "";

    # Filled in automatically below
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

    # Filled in by the module
    $config->{test_result} = MTT::Values::FAIL;
    $config->{result_message} = "to be filled in by module";
    $config->{c_bindings} = 0;
    $config->{cxx_bindings} = 0;
    $config->{f77_bindings} = 0;
    $config->{f90_bindings} = 0;

    $config->{full_section_name} = $section;
    $config->{simple_section_name} = $simple_section;

    # Carry MPI Get module data onwards
    $config->{module_data} = $mpi_get->{module_data};

    # module
    $config->{module} = Value($ini, $section, "module");
    if (!$config->{module}) {
        Warning("module not specified in [$section]; skipped\n");
        return undef;
    }

    # description
    $config->{description} = Value($ini, $section, "description");
    $config->{description} = Value($ini, "MTT", "description")
        if (!$config->{description});

    # Make a directory just for this section.  It's gotta be darn
    # short because some compilers will run out of room and complain
    # about filenames that are too long (doh!).
    MTT::DoCommand::Chdir($this_install_base);
    $config->{version_dir} = $this_install_base;
    my $sym_link_name = 
      MTT::Files::make_safe_filename($mpi_get->{simple_section_name}) .
      "--" . MTT::Files::make_safe_filename($simple_section) . "--" .
      MTT::Files::make_safe_filename($mpi_get->{version});
    $config->{sym_link_name} = $sym_link_name;

    # If the sym link already exists, whack the old directory that it
    # points to (and the sym link)
    MTT::DoCommand::Chdir("..");
    if (-l $sym_link_name) {
        my $start = cwd();
        MTT::DoCommand::Chdir($sym_link_name);
        my $dir_to_die = cwd();
        MTT::DoCommand::Chdir($start);
        # If the link was pointing somewhere valid, whack the previous
        # directory
        if ($dir_to_die ne $start) {
            my $x = MTT::DoCommand::Cmd(1, "rm -rf $dir_to_die");
        }
        unlink($sym_link_name);
    } elsif (-d $sym_link_name) {
        # Can't think of why this would happen, but let's cover the bases.
        MTT::DoCommand::Cmd(1, "rm -rf $sym_link_name");
    }

    # Make the sym link
    symlink(basename($this_install_base), $sym_link_name);
    MTT::DoCommand::Chdir($this_install_base);
    Debug("Sym linked: " . basename($this_install_base) . " to $sym_link_name\n");
    
    # Load any environment modules?
    my @env_modules;
    my $tmp = Value($ini, $section, "env_module");
    if (defined($tmp) && defined($mpi_get->{env_modules})) {
        $config->{env_modules} = $mpi_get->{env_modules} . "," . $tmp;
    } elsif (defined($tmp)) {
        $config->{env_modules} = $tmp;
    } elsif (defined($mpi_get->{env_modules})) {
        $config->{env_modules} = $mpi_get->{env_modules};
    }
    if (defined($config->{env_modules})) {
        @env_modules = MTT::Util::split_comma_list($config->{env_modules});
        Debug("Loading environment modules: @env_modules\n");
        MTT::EnvModule::unload(@env_modules);
        MTT::EnvModule::load(@env_modules);
    }

    # Process setenv, unsetenv, prepend_path, and
    # append_path
    my @save_env;
    ProcessEnvKeys($mpi_get, \@save_env);
    $config->{setenv} = Value($ini, $section, "setenv");
    $config->{unsetenv} = Value($ini, $section, "unsetenv");
    $config->{prepend_path} = Value($ini, $section, "prepend_path");
    $config->{append_path} = Value($ini, $section, "append_path");
    ProcessEnvKeys($config, \@save_env);
    @save_env = MTT::Util::delete_duplicates_from_array(@save_env);

    # JMS TO BE DELETED (now down in Install modules)
    # configure_arguments
    $tmp = Value($ini, $section, "configure_arguments");
    $tmp =~ s/\n|\r/ /g;
    $config->{configure_arguments} = $tmp
        if (defined($tmp));

    # JMS TO BE DELETED (now down in Install modules)
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

    # JMS TO BE DELETED (now down in Install modules)
    # make all arguments
    $tmp = Value($ini, $section, "make_all_arguments");
    $config->{make_all_arguments} = $tmp
        if (defined($tmp));

    # JMS TO BE DELETED (now down in Install modules)
    # make check
    $tmp = Logical($ini, $section, "make_check");
    $config->{make_check} = $tmp
        if (defined($tmp));

    # JMS TO BE DELETED (now down in Install modules)
    # compiler name and version.  We check for validity in the Install
    # modules; don't check here.
    $config->{compiler_name} =
        Value($ini, $section, "compiler_name");
    $config->{compiler_version} =
        Value($ini, $section, "compiler_version");
    $config->{compiler_name} =
        "unknown" if (!defined($config->{compiler_name}));
    $config->{compiler_version} =
        "unknown" if (!defined($config->{compiler_version}));

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

    # Option to restart builds on STDOUT pattern
    $tmp = Value($ini, $section, "restart_on_pattern");
    $config->{restart_on_pattern} = $tmp
        if (defined($tmp));

    # We're in the section directory.  Make a subdir for the source
    # and build.
    MTT::DoCommand::Cmd(1, "rm -rf src");
    my $source_dir = MTT::Files::mkdir("src");
    MTT::DoCommand::Chdir($source_dir);

    # Unpack the source and find out the subdirectory
    # name it created
    $config->{srcdir} = _prepare_source($mpi_get);
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

    # Set install_dir for the global environment
    $install_dir = $config->{installdir};

    # Bump the refcount in the MPI get -- even if this install fails,
    # we need the refcount to be accurate.
    ++$mpi_get->{refcount};

    # Run the module
    my $start = timegm(gmtime());
    my $start_time = time;
    my $ret = MTT::Module::Run("MTT::MPI::Install::$config->{module}",
                               "Install", $ini, $section, $config);

    my $duration = time - $start_time . " seconds";

    # bitness (must be processed *after* installation, and only if the
    # underlying module did not fill it in)
    my $bitness = Value($ini, $section, "mpi_bitness", "bitness");
    if (defined($bitness) || !defined($config->{bitness})) {

        # If the module didn't pass, fill in a value
        if ($ret && MTT::Values::PASS != $ret->{test_result}) {
            $bitness = EvaluateString("&get_mpi_install_bitness(\"32\")");
        } else {
            # If they did not use a funclet, translate the
            # bitness(es) for the MTT database
            if ($bitness !~ /\&/) {
                $bitness = EvaluateString("&get_mpi_install_bitness(\"$bitness\")");
            }
        }
        $config->{bitness} = $bitness;
    }

    # endian
    my $endian = Value($ini, $section, "endian");

    # If they did not use a funclet, translate the
    # endian(es) for the MTT database
    if ($endian !~ /\&/) {
        $endian = EvaluateString("&get_mpi_install_endian(\"$endian\")");
    }
    $config->{endian} = $endian;

    # Fetch cluster info (platform and hardware)
    _get_cluster_info($config, $section, $ini);

    # Unload any loaded environment modules
    if ($#env_modules >= 0) {
        Debug("Unloading environment modules: @env_modules\n");
        MTT::EnvModule::unload(@env_modules);
    }

    # Analyze the return
    if ($ret) {
        # Send the results back to the reporter
        my $report = {
            phase => "MPI Install",

            mpi_install_section_name => $config->{simple_section_name},

            description => $config->{description},
            bitness => $config->{bitness},
            endian => $config->{endian},
            compiler_name => $config->{compiler_name},
            compiler_version => $config->{compiler_version},
            configure_arguments => $config->{configure_arguments},
            vpath_mode => $config->{vpath_mode},
            merge_stdout_stderr => $config->{merge_stdout_stderr},
            platform_type => $config->{platform_type},
            platform_hardware => $config->{platform_hardware},
            os_name => $config->{os_name},
            os_version => $config->{os_version},

            environment => "filled in below",

            start_timestamp => $start,

            duration => $duration,
            mpi_name => $mpi_get->{simple_section_name},
            mpi_version => $mpi_get->{version},

            test_result => $ret->{test_result},
            exit_value => MTT::DoCommand::exit_value($ret->{exit_status}),
            exit_signal => MTT::DoCommand::exit_signal($ret->{exit_status}),
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
        $ret->{mpi_get_full_section_name} = $mpi_get->{full_section_name};
        $ret->{mpi_get_simple_section_name} = $mpi_get->{simple_section_name};
        $ret->{mpi_version} = $mpi_get->{version};

        # Some additional values
        $ret->{description} = $config->{description};
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
        $ret->{sym_link_name} = $config->{sym_link_name};
        $ret->{version_dir} = $config->{version_dir};
        $ret->{source_dir} = $config->{srcdir};
        $ret->{build_dir} = $config->{builddir};
        $ret->{refcount} = 0;

        # Delete keys with empty values
        foreach my $k (keys(%$report)) {
            if ($report->{$k} eq "") {
                delete $report->{$k};
            }
        }

        # Add the data in the global $MTT::MPI::installs table
        $MTT::MPI::installs->{$mpi_get->{simple_section_name}}->{$mpi_get->{version}}->{$simple_section} = $ret;

        # All of the data will be saved to a .dump file, so reclaim
        # potentially a big chunk of memory...
        delete $ret->{result_stdout};
        delete $ret->{result_stderr};
        delete $ret->{configure_stdout};
        delete $ret->{make_all_stdout};
        delete $ret->{make_all_stderr};
        delete $ret->{make_check_stdout};
        delete $ret->{make_install_stdout};

        # Submit to the reporter, and receive a serial
        my $serials = MTT::Reporter::Submit($phase_name, $simple_section, $report);

        # Merge in the serials from the MTTDatabase
        my $module = "MTTDatabase";
        foreach my $k (keys %{$serials->{$module}}) {
            $ret->{$k} = $serials->{$module}->{$k};
        }

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

            Verbose("   Completed $phase_name successfully\n");
        } else {
            Warning("Failed to install [$section]: $ret->{result_message}\n");
            Verbose("   Completed $phase_name unsuccessfully\n");
        }
    } else {
        Verbose("   Skipped $phase_name\n");
    }
}

# Return a hash of hardware and platform information
sub _get_cluster_info {
    my ($config, $section, $ini) = @_;

    # INI sections to check for overrides
    my @sections = ($section, "MTT");

    my @cluster_info_fields = (
        "platform_type",
        "platform_hardware",
        "os_name",
        "os_version",
    );

    # Allow cluster info overrides for the INI file in the
    # current section or [MTT] section
    # (e.g., set OS version using a funclet)
    my $value;
    foreach my $field (@cluster_info_fields) {
        foreach my $ini_section (@sections) {
            $value = $ini->val($ini_section, $field);
            if ($value) {
                $config->{$field} = $value;
                last;
            }
        }

        $config->{$field} = EvaluateString($config->{$field})
            if (defined($config->{$field}));
    }
}

# Run a pre or post-installation step
sub _run_step {
    my ($params, $step, $ini, $section) = @_;

    my $cmd;

    $step .= "_install";
    if (defined($params->{$step})) {
        $cmd = $params->{$step};
    }

    # Get the timeout value
    my $name = $step . "_timeout";
    my $timeout = MTT::Util::parse_time_to_seconds($params->{$name});
    $timeout = undef 
        if ($timeout <= 0);

    # Steps can be funclets
    if ($cmd =~ /^\s*&/) {

        my $ok = EvaluateString($cmd, $ini, $section);
        Verbose("  Warning: step $step FAILED\n") if (!$ok);

    # Steps can be shell commands
    } else {
    
        # Do any needed @var@ expansions
        $cmd = EvaluateString($cmd, $ini, $section);

        Debug("Running step: $step: $cmd / timeout $timeout\n");
        my $x = ($cmd =~ /\n/) ?
            MTT::DoCommand::CmdScript(1, $cmd, $timeout) : 
            MTT::DoCommand::Cmd(1, $cmd, $timeout);
    }
}

1;
