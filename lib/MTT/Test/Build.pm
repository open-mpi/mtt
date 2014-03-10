#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2014 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007-2009 Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2008      Mellanox Technologies.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

########################################################################
# Build Tests phase
########################################################################

# The output of this phase is the @MTT::Test::tests
# array of structs, each with the following members:

# Fields...

# Note that PATH and LD_LIBRARY_PATH are automatically prepended with
# relevant values for each MPI installation before each sub-component
# is invoked to build a test suite.  Hence, "mpicc" (and friends)
# should be found via the PATH and if they require some .so files,
# should be handled properly.  

# As a direct result, it is not necessary to prepent-path for PATH or
# LD_LIBRARY_PATH in the ini file; it is done automatically.

########################################################################

package MTT::Test::Build;

use strict;
use Time::Local;
use MTT::Reporter;
use MTT::Messages;
use MTT::INI;
use MTT::Module;
use MTT::Values;
use MTT::Files;
use MTT::Defaults;
use MTT::Test;
use MTT::EnvModule;
use MTT::EnvImporter;
use MTT::Util;
use Data::Dumper;

#--------------------------------------------------------------------------

# File to keep data about builds
my $built_file = "test_built.ini";

# Section in the ini file where info is located
my $built_section = "test_built";

# Where the top-level build tree is
my $build_base;

# What we call this phase
my $phase_name = "Test Build";

#--------------------------------------------------------------------------

#--------------------------------------------------------------------------

sub Build {
    my ($ini, $ini_full, $build_base, $force) = @_;

    $MTT::Globals::Values->{active_phase} = $phase_name;
    Verbose("*** $phase_name phase starting\n");

    # Save the environment
    my %ENV_SAVE = %ENV;

    # Go through all the sections in the ini file looking for section
    # names that begin with "$phase_name:"
    MTT::DoCommand::Chdir($build_base);
    foreach my $section ($ini->Sections()) {

        # See if we're supposed to terminate.  Only check in the
        # outtermost and innermost loops (even though we *could* check
        # at every loop level); that's good enough.
        last
            if (MTT::Util::time_to_terminate());

        if ($section =~ /^\s*test build:/) {
            Verbose(">> $phase_name [$section]\n");

            # Simple section name
            my $simple_section = GetSimpleSection($section);

            # Ensure that we have a test get name
            my $test_get_value = Value($ini, $section, "test_get");
            if (!$test_get_value) {
                Warning("No test_get specified in [$section]; skipping\n");
                next;
            }

            # Make the active INI section name known
            $MTT::Globals::Values->{active_section} = $section;

            # Iterate through all the test_get values
            my @test_gets = MTT::Util::split_comma_list($test_get_value);
            foreach my $test_get_name (@test_gets) {

                # Strip whitespace
                $test_get_name =~ s/^\s*(.*?)\s*/\1/;
                $test_get_name = lc($test_get_name);

                # This is only warning about the INI file; we'll see
                # if we find meta data for the test get later
                if ($test_get_name ne "all" &&
                    !$ini_full->SectionExists("test get: $test_get_name")) {
                    Warning("Test Get section \"$test_get_name\" does not seem to exist in the INI file\n");
                }

                # If we have no sources for this name, then silently
                # skip it.  Don't issue a warning because command line
                # parameters may well have dictated to skip this
                # section.
                if ($test_get_name ne "all" &&
                    !exists($MTT::Test::sources->{$test_get_name})) {
                    Debug("Have no sources for Test Get \"$test_get_name\", skipping\n");
                    next;
                }

                # Find the matching test source
                foreach my $test_get_key (keys(%{$MTT::Test::sources})) {
                    if ($test_get_name eq "all" ||
                        $test_get_key eq $test_get_name) {
                        my $test_get = $MTT::Test::sources->{$test_get_key};

                        # For each MPI source
                        foreach my $mpi_get_key (keys(%{$MTT::MPI::installs})) {
                            my $mpi_get = $MTT::MPI::installs->{$mpi_get_key};

                            # For each version of that source
                            foreach my $mpi_version_key (keys(%{$mpi_get})) {
                                my $mpi_version = $mpi_get->{$mpi_version_key};

                                # For each installation of that version
                                foreach my $mpi_install_key (keys(%{$mpi_version})) {

                                    # See if we're supposed to
                                    # terminate.  Only check in the
                                    # outtermost and innermost loops
                                    # (even though we *could* check at
                                    # every loop level); that's good
                                    # enough.
                                    last
                                        if (MTT::Util::time_to_terminate());

                                    my $mpi_install = $mpi_version->{$mpi_install_key};
                                    # Only take sucessful MPI installs
                                    if (!$mpi_install->{test_result}) {
                                        Verbose("   Failed build for [$mpi_get_key] / [$mpi_version_key] / [$mpi_install_key] / [$simple_section] -- skipping\n");
                                        next;
                                    }

                                    # See if we've already got a
                                    # successful test build for this
                                    # MPI installation.  Test
                                    # incrementally so that it doesn't
                                    # create each intermediate key.
                                    if (!$force &&  defined(MTT::Util::does_hash_key_exist($MTT::Test::builds, $mpi_get_key, $mpi_version_key, $mpi_install_key, $simple_section))) {
                                        Verbose("   Already have a build for [$mpi_get_key] / [$mpi_version_key] / [$mpi_install_key] / [$simple_section] (use --force to re-build)\n");
                                        next;
                                    }

                                    # See if we're supposed to skip
                                    # this MPI get or this MPI install
                                    my $go_next = 0;
                                    my $skip_mpi_get = 
                                        MTT::Values::Value($ini, $section, 
                                                           "skip_mpi_get");
                                    foreach my $skip_one_mpi_get (MTT::Util::split_comma_list($skip_mpi_get)) {
                                        if ($skip_one_mpi_get &&
                                                lc($skip_one_mpi_get) eq lc($mpi_get_key)) {
                                            Verbose("   Skipping build for [$mpi_get_key] / [$mpi_version_key] / [$mpi_install_key] / [$simple_section] per INI configuration\n");
                                            $go_next = 1;
                                        }
                                    }

                                    my $skip_mpi_install = 
                                        MTT::Values::Value($ini, $section, 
                                                           "skip_mpi_install");
                                    foreach my $skip_one_mpi_install (MTT::Util::split_comma_list($skip_mpi_install)) {
                                        if ($skip_one_mpi_install &&
                                                lc($skip_one_mpi_install) eq lc($mpi_install_key)) {
                                            Verbose("   Skipping build for [$mpi_get_key] / [$mpi_version_key] / [$mpi_install_key] / [$simple_section] per INI configuration\n");
                                            $go_next = 1;
                                        }
                                    }

                                    my $only_mpi_install = 
                                        MTT::Values::Value($ini, $section, 
                                                           "mpi_install");
                                    if ($only_mpi_install) {
                                        $go_next=1;
                                        foreach my $one_mpi_install (MTT::Util::split_comma_list($only_mpi_install)) {
                                            if ($one_mpi_install &&
                                                    lc($one_mpi_install) eq lc($mpi_install_key)) {
                                                Verbose("   Build required for [$mpi_get_key] / [$mpi_version_key] / [$mpi_install_key] / [$simple_section] per INI configuration\n");
                                                $go_next = 0;
                                            }
                                        }
                                    }

                                    if ($go_next) {
                                        next;
                                    }

                                    # We don't have a test build for
                                    # this particular MPI source
                                    # instance.  So cd into the MPI
                                    # install tree for this particular
                                    # MPI install.

                                    Verbose("   Building for [$mpi_get_key] / [$mpi_version_key] / [$mpi_install_key] / [$simple_section]\n");
                                    $MTT::Globals::Internals->{mpi_get_name} =
                                        $mpi_get_key;
                                    $MTT::Globals::Internals->{mpi_install_name} =
                                        $mpi_install_key;
                                    $MTT::Globals::Internals->{test_get_name} =
                                        $test_get_name;
                                    $MTT::Globals::Internals->{test_build_name} =
                                        $simple_section;
                                    
                                    MTT::DoCommand::Chdir($build_base);
                                    MTT::DoCommand::Chdir($mpi_install->{version_dir});
                                    
                                    # Do the build and restore the environment
                                    _do_build($ini, $section, $build_base, $test_get, $mpi_get, $mpi_install);
                                    delete $MTT::Globals::Internals->{mpi_get_name};
                                    delete $MTT::Globals::Internals->{mpi_install_name};
                                    delete $MTT::Globals::Internals->{test_get_name};
                                    delete $MTT::Globals::Internals->{test_build_name};
                                    %ENV = %ENV_SAVE;
                                }
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
    my ($test) = @_;

    $test->{prepare_for_install} =~ m/(.+)::(\w+)$/;
    my $module = $1;
    my $method = $2;

    return MTT::Module::Run($module, $method, $test, MTT::DoCommand::cwd());
}

#--------------------------------------------------------------------------

sub _do_build {
    my ($ini, $section, $build_base, $test_get, $mpi_get, $mpi_install) = @_;

    # Simple section name
    my $simple_section = GetSimpleSection($section);

    my $skip_section = Value($ini, $section, "skip_section");
    if ($skip_section) {
        Verbose("skip_section evaluates to $skip_section [$simple_section]; skipping\n");
        return;
    }

    my $config;
    %$config = %$MTT::Defaults::Test_build;
    $config->{full_section_name} = $section;
    $config->{simple_section_name} = $simple_section;
    $config->{test_name} = $test_get->{test_name};
    $config->{srcdir} = "to be filled in below";
    $config->{setenv} = "to be filled in below";
    $config->{unsetenv} = "to be filled in below";
    $config->{prepend_path} = "to be filled in below";
    $config->{append_path} = "to be filled in below";
        
    # Filled in by the module
    $config->{test_result} = 0;
    $config->{msg} = "";
    $config->{result_stdout} = "";

    # Find the build module
    $config->{build_module} = Value($ini, $section, "module");
    if (!$config->{build_module}) {
        Warning("No module specified for [$section]; skipping\n");
        return;
    }

    # Make a directory just for this ini section
    my $tests_dir = MTT::Files::mkdir("tests");
    MTT::DoCommand::Chdir($tests_dir);
    my $build_section_dir = MTT::Files::make_safe_dirname($simple_section);
    MTT::DoCommand::Chdir($build_section_dir);

    # description
    $config->{description} = Value($ini, $section, "description");
    $config->{description} = Value($ini, "MTT", "description")
        if (!$config->{description});

    # test_bitness
    $config->{bitness} = Value($ini, $section, "test_bitness", "bitness");

    # Unpack the source and find out the subdirectory name it created
    my $prepare_source_passed = 1;
    $config->{srcdir} = _prepare_source($test_get);
    $prepare_source_passed = 0
        if (!$config->{srcdir} || !defined($config->{srcdir}));

    # We'll check for failure of this step later
    $config->{srcdir} = MTT::DoCommand::cwd();

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

    # Set the PATH and LD_LIBRARY_PATH
    if ($mpi_install->{bindir}) {
        if (exists($ENV{PATH})) {
            $ENV{PATH} = "$mpi_install->{bindir}:" . $ENV{PATH};
        } else {
            $ENV{PATH} = $mpi_install->{bindir};
        }
    }
    if ($mpi_install->{libdir}) {
        if (exists($ENV{LD_LIBRARY_PATH})) {
            $ENV{LD_LIBRARY_PATH} = "$mpi_install->{libdir}:" . $ENV{LD_LIBRARY_PATH};
        } else {
            $ENV{LD_LIBRARY_PATH} = $mpi_install->{libdir};
        }
    }

    # Some test suites require knowledge of where
    # the MPI library is at the build stage
    $MTT::Test::Run::test_prefix = $mpi_install->{installdir};

    # Process loading of modules -- for both the MPI install and the
    # test build sections
    my @env_modules;
    my $val = Value($ini, $section, "env_module");
    $config->{env_modules} = $val 
        if (defined($val));
    $config->{env_modules} .= "," . $mpi_install->{env_modules}
        if (defined($mpi_install->{env_modules}));
    if ($config->{env_modules}) {
        @env_modules = MTT::Util::split_comma_list($config->{env_modules});
        MTT::EnvModule::unload(@env_modules);
        MTT::EnvModule::load(@env_modules);
    }

    # Process loading of env importers -- for both the MPI install and the
    # test build sections
    my @env_importers;
    my $val = Value($ini, $section, "env_importer");
    $config->{env_importers} = $val 
        if (defined($val));
    $config->{env_importers} .= "," . $mpi_install->{env_importers}
        if (defined($mpi_install->{env_importers}));
    if ($config->{env_importers}) {
        @env_importers = MTT::Util::split_comma_list($config->{env_importers});
        MTT::EnvImporter::load(@env_importers);
    }

    # Process setenv, unsetenv, prepend-path, and append-path -- for
    # both the MPI install and the test build sections
    my @save_env;
    ProcessEnvKeys($mpi_get, \@save_env);
    ProcessEnvKeys($mpi_install, \@save_env);
    ProcessEnvKeys($test_get, \@save_env);
    $config->{setenv} = Value($ini, $section, "setenv");
    $config->{unsetenv} = Value($ini, $section, "unsetenv");
    $config->{prepend_path} = Value($ini, $section, "prepend_path");
    $config->{append_path} = Value($ini, $section, "append_path");
    ProcessEnvKeys($config, \@save_env);
    @save_env = MTT::Util::delete_duplicates_from_array(@save_env);

    # Bump the refcount on the MPI install and test get sections.
    # Even if this build fails, we need it.
    ++$test_get->{refcount};
    ++$mpi_install->{refcount};

    # If _prepare_source(), above, succeeded, run the module.
    # Otherwise, just hard-wire in a failure.
    my $start = timegm(gmtime());
    my $start_time = time();
    my $ret;
    if (!$prepare_source_passed) {
        $ret->{test_result} = MTT::Values::FAIL;
        $ret->{result_message} = "Preparing the test source failed -- see MTT client output for details";
    } elsif ($config->{srcdir}) {
        $ret = MTT::Module::Run("MTT::Test::Build::$config->{build_module}",
                                "Build", $ini, $mpi_install, $config);
    } else {
        $ret->{test_result} = MTT::Values::FAIL;
        $ret->{result_message} = "Current working directory could not be found -- see MTT client output for details";
    }
    my $duration = time() - $start_time . " seconds";
            
    # Unload any loaded environment modules
    if ($#env_modules >= 0) {
        MTT::EnvModule::unload(@env_modules);
    }

    # Unload any loaded environment importers
    if ($#env_importers >= 0) {
        # We need to reverse the order for the shell environment 
        # importers, because unloading an env importer actually
        # means reverting to an env snapshot
        MTT::EnvImporter::unload(reverse @env_importers);
    }

    # Analyze the return
    if ($ret) {
        $ret->{description} = $config->{description};
        $ret->{full_section_name} = $config->{full_section_name};
        $ret->{simple_section_name} = $config->{simple_section_name};
        $ret->{setenv} = $config->{setenv};
        $ret->{unsetenv} = $config->{unsetenv};
        $ret->{prepend_path} = $config->{prepend_path};
        $ret->{append_path} = $config->{append_path};
        $ret->{env_modules} = $config->{env_modules};
        $ret->{srcdir} = $config->{srcdir};
        $ret->{mpi_name} = $mpi_install->{mpi_name};
        $ret->{mpi_get_simple_section_name} = $mpi_install->{mpi_get_simple_section_name};
        $ret->{mpi_install_simple_section_name} = $mpi_install->{simple_section_name};
        $ret->{mpi_version} = $mpi_install->{mpi_version};
        $ret->{test_get_simple_section_name} = $test_get->{simple_section_name};
        $ret->{start_timestamp} = timegm(gmtime());
        $ret->{refcount} = 0;

        if (!defined($ret->{test_result})) {
            $ret->{test_result} = MTT::Values::FAIL;
        }
        
        # Send the results back to the reporter
        my $report = {
            phase => "Test Build",
            description => $config->{description},
            start_timestamp => $start,
            duration => $duration,
            test_result => $ret->{test_result},
            compiler_name => $mpi_install->{compiler_name},
            compiler_version => $mpi_install->{compiler_version},
            result_message => $ret->{result_message},
            environment => "filled in below",
            exit_value => MTT::DoCommand::exit_value($ret->{exit_status}),
            exit_signal => MTT::DoCommand::exit_signal($ret->{exit_status}),
            result_stdout => "filled in below",
            result_stderr => "filled in below",

            suite_name => $config->{simple_section_name},
            bitness => $config->{bitness},

            mpi_name => $mpi_install->{mpi_get_simple_section_name},
            mpi_get_section_name => $mpi_install->{mpi_get_simple_section_name},
            mpi_install_section_name => $mpi_install->{simple_section_name},
            mpi_version => $mpi_install->{mpi_version},
                        
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

        # If we want to save, see how many lines we want to save
        if ($want_save) {
            if ($config->{stdout_save_lines} == -1) {
                $report->{result_stdout} = "$ret->{result_stdout}\n";
            } elsif ($config->{stdout_save_lines} == 0) {
                delete $report->{result_stdout};
            } else {
                if ($ret->{result_stdout} =~ m/((.*\n){$config->{stdout_save_lines}})$/) {
                    $report->{result_stdout} = $1;
                } else {
                    # There were less lines available than we asked
                    # for, so just take them all
                    $report->{result_stdout} = $ret->{result_stdout};
                }
            }
        } else {
            delete $report->{result_stdout};
        }

        # Always fill in the last bunch of lines for result_stderr
        if ($ret->{result_stderr}) {
            if ($config->{stderr_save_lines} == -1) {
                $report->{result_stderr} = "$ret->{result_stderr}\n";
            } elsif ($config->{stderr_save_lines} == 0) {
                delete $report->{result_stderr};
            } else {
                if ($ret->{result_stderr} =~ m/((.*\n){$config->{stderr_save_lines}})$/) {
                    $report->{result_stderr} = $1;
                } else {
                    # There were less lines available than we asked
                    # for, so just take them all
                    $report->{result_stderr} = $ret->{result_stderr};
                }
            }
        } else {
            delete $report->{result_stderr};
        }


        # Did we have any environment?
        @save_env = MTT::Util::delete_duplicates_from_array(@save_env);
        $report->{environment} = undef;
        foreach my $e (@save_env) {
            $report->{environment} .= "$e\n";
        }

        # Delete keys with empty values
        foreach my $k (keys(%$report)) {
            if ($report->{$k} eq "") {
                delete $report->{$k};
            }
        }
        
        # Fetch mpi install serial
        my $mpi_install_id = $MTT::MPI::installs->{$mpi_install->{mpi_get_simple_section_name}}->{$mpi_install->{mpi_version}}->{$mpi_install->{simple_section_name}}->{mpi_install_id};
        $report->{mpi_install_id} = $mpi_install_id;
        $ret->{mpi_install_id} = $mpi_install_id;

        # Submit it!
        my $serials = MTT::Reporter::Submit("Test Build", $simple_section, $report);

        # Merge in the serials from the MTTDatabase
        my $module = "MTTDatabase";
        foreach my $k (keys %{$serials->{$module}}) {
            $ret->{$k} = $serials->{$module}->{$k};
        }

        # Data has been submitted, so reclaim potentially a good chunk of
        # memory...
        delete $ret->{result_stdout};
        delete $ret->{result_stderr};

        # Save it
        $MTT::Test::builds->{$mpi_install->{mpi_get_simple_section_name}}->{$mpi_install->{mpi_version}}->{$mpi_install->{simple_section_name}}->{$simple_section} = $ret;
        MTT::Test::SaveBuilds($build_base, 
            $mpi_install->{mpi_get_simple_section_name},
            $mpi_install->{mpi_version},
            $mpi_install->{simple_section_name},
            $simple_section);
        
        # Print
        if (MTT::Values::PASS == $ret->{test_result}) {
            Verbose("   Completed test build successfully\n");
        } else {
            Warning("Failed to build test [$section]: $ret->{result_message}\n");
            Verbose("   Completed test build unsuccessfully\n");
        }
    } else {
            Verbose("   Skipped test build\n");
    }
}

1;
