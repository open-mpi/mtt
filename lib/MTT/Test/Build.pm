#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
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
use Cwd;
use Time::Local;
use MTT::DoCommand;
use MTT::Reporter;
use MTT::Messages;
use MTT::INI;
use MTT::Module;
use MTT::Values;
use MTT::Files;
use MTT::Defaults;
use Data::Dumper;

#--------------------------------------------------------------------------

# File to keep data about builds
my $built_file = "test_built.ini";

# Section in the ini file where info is located
my $built_section = "test_built";

# Where the top-level build tree is
my $build_base;

#--------------------------------------------------------------------------

sub _make_safe_dir {
    my ($ret) = @_;

    $ret = MTT::Files::make_safe_filename($ret);
    return MTT::Files::mkdir($ret);
}

#--------------------------------------------------------------------------

sub Build {
    my ($ini, $build_base, $force) = @_;

    Verbose("*** Test build phase starting\n");

    # Save the environment
    my %ENV_SAVE = %ENV;

    # Go through all the sections in the ini file looking for section
    # names that begin with "Test build:"
    chdir($build_base);
    foreach my $section ($ini->Sections()) {
        if ($section =~ /^\s*test build:/) {
            Verbose(">> Test build [$section]\n");

            # Simple section name
            my $simple_section = $section;
            $simple_section =~ s/^\s*test build:\s*//;

            # Ensure that we have a test get name
            my $test_get_value = Value($ini, $section, "test_get");
            if (!$test_get_value) {
                Warning("No test_get specified in [$section]; skipping\n");
                next;
            }

            # Iterate through all the test_get values
            my @test_gets = split(/,/, $test_get_value);
            foreach my $test_get_name (@test_gets) {
                # Strip whitespace
                $test_get_name =~ s/^\s*(.*?)\s*/\1/;

                # Find the matching test source
                foreach my $test_get_key (keys(%{$MTT::Test::sources})) {
                    if ($test_get_key eq $test_get_name) {
                        my $test_get = $MTT::Test::sources->{$test_get_key};
            
                        # For each MPI source
                        foreach my $mpi_get_key (keys(%{$MTT::MPI::installs})) {
                            my $mpi_get = $MTT::MPI::installs->{$mpi_get_key};

                            # For each version of that source
                            foreach my $mpi_version_key (keys(%{$mpi_get})) {
                                my $mpi_version = $mpi_get->{$mpi_version_key};

                                # For each installation of that version
                                foreach my $mpi_install_key (keys(%{$mpi_version})) {
                                    my $mpi_install = $mpi_version->{$mpi_install_key};

                                    # Only take sucessful MPI installs
                                    if (!$mpi_install->{success}) {
                                        Verbose("   Failed build for [$mpi_get_key] / [$mpi_version_key] / [$mpi_install_key] / [$simple_section] -- skipping\n");
                                        next;
                                    }

                                    # See if we've already got a
                                    # successful test build for this
                                    # MPI installation.  Test
                                    # incrementally so that it doesn't
                                    # create each intermediate key.

                                    if (!$force &&
                                        exists($MTT::Test::builds->{$mpi_get_key}) &&
                                        exists($MTT::Test::builds->{$mpi_get_key}->{$mpi_version_key}) &&
                                        exists($MTT::Test::builds->{$mpi_get_key}->{$mpi_version_key}->{$mpi_install_key}) &&
                                        exists($MTT::Test::builds->{$mpi_get_key}->{$mpi_version_key}->{$mpi_install_key}->{$simple_section})) {
                                        Verbose("   Already have a build for [$mpi_get_key] / [$mpi_version_key] / [$mpi_install_key] / [$simple_section]\n");
                                        next;
                                    }

                                    # We don't have a test build for
                                    # this particular MPI source
                                    # instance.  So cd into the MPI
                                    # install tree for this particular
                                    # MPI install.

                                    Verbose("   Building for [$mpi_get_key] / [$mpi_version_key] / [$mpi_install_key] / [$simple_section]\n");
                                    
                                    chdir($build_base);
                                    chdir(MTT::Files::make_safe_filename($mpi_install->{mpi_get_simple_section_name}));
                                    chdir(MTT::Files::make_safe_filename($mpi_install->{simple_section_name}));
                                    chdir(MTT::Files::make_safe_filename($mpi_install->{mpi_version}));
                                    
                                    # Do the build and restore the environment
                                    _do_build($ini, $section, $build_base, $test_get, $mpi_install);
                                    %ENV = %ENV_SAVE;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Verbose("*** Test build phase complete\n");
}


#--------------------------------------------------------------------------

sub _prepare_source {
    my ($test) = @_;

    $test->{prepare_for_install} =~ m/(.+)::(\w+)$/;
    my $module = $1;
    my $method = $2;

    return MTT::Module::Run($module, $method, $test, cwd());
}

#--------------------------------------------------------------------------

sub _do_build {
    my ($ini, $section, $build_base, $test_get, $mpi_install) = @_;

    # Simple section name
    my $simple_section = $section;
    $simple_section =~ s/^\s*test build:\s*//;

    my $config;
    %$config = %$MTT::Defaults::Test_build;
    $config->{full_section_name} = $section;
    $config->{simple_section_name} = $simple_section;
    $config->{test_nme} = $test_get->{test_name};
    $config->{srcdir} = "to be filled in below";
    $config->{setenv} = "to be filled in below";
    $config->{unsetenv} = "to be filled in below";
    $config->{prepend_path} = "to be filled in below";
    $config->{append_path} = "to be filled in below";
        
    # Filled in by the module
    $config->{success} = 0;
    $config->{msg} = "";
    $config->{stdout} = "";

    # Find the build module
    $config->{build_module} = Value($ini, $section, "module");
    if (!$config->{build_module}) {
        Warning("No module specified for [$section]; skipping\n");
        return;
    }

    # Make a directory just for this ini section
    my $tests_dir = MTT::Files::mkdir("tests");
    chdir($tests_dir);
    my $build_section_dir = _make_safe_dir($simple_section);
    chdir($build_section_dir);

    # Unpack the source and find out the subdirectory name it created

    $config->{srcdir} = _prepare_source($test_get);
    chdir($config->{srcdir});
    $config->{srcdir} = cwd();

    # What to do with stdout/stderr?
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

    # Process setenv, unsetenv, prepend-path, and append-path -- for
    # both the MPI that we're building with and the section of the ini
    # file that we're building.
    my @save_env;
    ProcessEnvKeys($mpi_install, \@save_env);
    $config->{setenv} = Value($ini, $section, "setenv");
    $config->{unsetenv} = Value($ini, $section, "unsetenv");
    $config->{prepend_path} = Value($ini, $section, "prepend_path");
    $config->{append_path} = Value($ini, $section, "append_path");
    ProcessEnvKeys($config, \@save_env);

    # Run the module
    my $start = timegm(gmtime());
    my $start_time = time();
    my $ret = MTT::Module::Run("MTT::Test::Build::$config->{build_module}",
                               "Build", $ini, $mpi_install, $config);
    my $duration = time() - $start_time . " seconds";
            
    # Analyze the return
    if ($ret) {
        $ret->{full_section_name} = $config->{full_section_name};
        $ret->{simple_section_name} = $config->{simple_section_name};
        $ret->{setenv} = $config->{setenv};
        $ret->{unsetenv} = $config->{unsetenv};
        $ret->{prepend_path} = $config->{prepend_path};
        $ret->{append_path} = $config->{append_path};
        $ret->{srcdir} = $config->{srcdir};
        $ret->{mpi_name} = $mpi_install->{mpi_name};
        $ret->{mpi_get_simple_section_name} = $mpi_install->{mpi_get_simple_section_name};
        $ret->{mpi_install_simple_section_name} = $mpi_install->{simple_section_name};
        $ret->{mpi_version} = $mpi_install->{mpi_version};
        $ret->{timestamp} = timegm(gmtime());

        my $perfbase_xml = Value($ini, $section, "perfbase_xml");
        $perfbase_xml = "inp_test_build.xml"
            if (!$perfbase_xml);
        $ret->{success} = 0
            if (!defined($ret->{success}));
        
        # Save the results in an ini file
        Debug("Writing built file: $config->{srcdir}/$built_file\n");
        WriteINI("$build_section_dir/$built_file",
                 $built_section, $ret);
                
        # Send the results back to the reporter
        my $report = {
            phase => "Test Build",
            start_test_timestamp => $start,
            test_duration_interval => $duration,
            success => $ret->{success},
            compiler_name => $mpi_install->{compiler_name},
            compiler_version => $mpi_install->{compiler_version},
            result_message => $ret->{result_message},
            environment => "filled in below",
            stdout => "filled in below",
            stderr => "filled in below",
            perfbase_xml => $perfbase_xml,

            test_build_section_name => $config->{simple_section_name},

            mpi_name => $mpi_install->{mpi_get_simple_section_name},
            mpi_get_section_name => $mpi_install->{mpi_get_simple_section_name},
            mpi_install_section_name => $mpi_install->{simple_section_name},
            mpi_version => $mpi_install->{mpi_version},
        };

        # See if we want to save the stdout
        my $want_save = 1;
        if (1 == $ret->{success}) {
            if (!$config->{save_stdout_on_success}) {
                $want_save = 0;
            }
        } elsif (!$ret->{stdout}) {
            $want_save = 0;
        }

        # If we want to save, see how many lines we want to save
        if ($want_save) {
            if ($config->{stdout_save_lines} == -1) {
                $report->{stdout} = "$ret->{stdout}\n";
            } elsif ($config->{stdout_save_lines} == 0) {
                delete $report->{stdout};
            } else {
                if ($ret->{stdout} =~ m/((.*\n){$config->{stdout_save_lines}})$/) {
                    $report->{stdout} = $1;
                } else {
                    # There were less lines available than we asked
                    # for, so just take them all
                    $report->{stdout} = $ret->{stdout};
                }
            }
        } else {
            delete $report->{stdout};
        }

        # Always fill in the last bunch of lines for stderr
        if ($ret->{stderr}) {
            if ($config->{stderr_save_lines} == -1) {
                $report->{stderr} = "$ret->{stderr}\n";
            } elsif ($config->{stderr_save_lines} == 0) {
                delete $report->{stderr};
            } else {
                if ($ret->{stderr} =~ m/((.*\n){$config->{stderr_save_lines}})$/) {
                    $report->{stderr} = $1;
                } else {
                    # There were less lines available than we asked
                    # for, so just take them all
                    $report->{stderr} = $ret->{stderr};
                }
            }
        } else {
            delete $report->{stderr};
        }

        # Did we have any environment?
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
        
        # Submit it!
        MTT::Reporter::Submit("Test Build", $simple_section, $report);

        # It's been saved, so reclaim potentially a good chunk of
        # memory...
        delete $ret->{stdout};
        delete $ret->{stderr};
        
        # Save it
        $MTT::Test::builds->{$mpi_install->{mpi_get_simple_section_name}}->{$mpi_install->{mpi_version}}->{$mpi_install->{simple_section_name}}->{$simple_section} = $ret;
        MTT::Test::SaveBuilds($build_base);
        
        # Print
        if (1 == $ret->{success}) {
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
