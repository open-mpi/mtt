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

package MTT::Test::Run;

use strict;
use Cwd;
use File::Basename;
use Time::Local;
use MTT::Messages;
use MTT::Values;
use MTT::Reporter;
use MTT::Defaults;
use Data::Dumper;

#--------------------------------------------------------------------------

# Exported current number of processes in the test
our $test_np;

# Exported current prefix of the MPI under test
our $test_prefix;

# Exported current executable under text
our $test_executable;

# Exported current argv under test
our $test_argv;

# Exported exit status of the last test run
our $test_exit_status;

#--------------------------------------------------------------------------

sub Run {
    my ($ini, $top_dir, $force) = @_;

    # Save the environment
    my %ENV_SAVE = %ENV;

    Verbose("*** Run test phase starting\n");

    # Go through all the sections in the ini file looking for section
    # names that begin with "Test run:"
    foreach my $section ($ini->Sections()) {
        if ($section =~ /^\s*test run:/) {

            # Simple section name
            my $simple_section = $section;
            $simple_section =~ s/^\s*test run:\s*//;
            Verbose(">> Test run [$simple_section]\n");

            # Ensure that we have a test build name
            my $test_build_value = MTT::Values::Value($ini, $section, "test_build");
            if (!$test_build_value) {
                Warning("No test_build specified in [$section]; skipping\n");
                next;
            }

            # Iterate through all the test_build values
            my @test_builds = split(/,/, $test_build_value);
            foreach my $test_build_name (@test_builds) {
                # Strip whitespace
                $test_build_name =~ s/^\s*(.*?)\s*/\1/;

                # Find the matching test build.  Test builds are
                # indexed on (in order): MPI Get simple section name,
                # MPI Install simple section name, Test Build simple
                # section name
                foreach my $mpi_get_key (keys(%{$MTT::Test::builds})) {
                    foreach my $mpi_version_key (keys(%{$MTT::Test::builds->{$mpi_get_key}})) {
                        foreach my $mpi_install_key (keys(%{$MTT::Test::builds->{$mpi_get_key}->{$mpi_version_key}})) {
                            foreach my $test_build_key (keys(%{$MTT::Test::builds->{$mpi_get_key}->{$mpi_version_key}->{$mpi_install_key}})) {
                                
                                if ($test_build_key eq $test_build_name) {
                                    my $test_build = $MTT::Test::builds->{$mpi_get_key}->{$mpi_version_key}->{$mpi_install_key}->{$test_build_key};
                                    Debug("Found a match! $test_build_key [$simple_section\n");
                                    if (!$test_build->{success}) {
                                        Debug("But that build was borked -- skipping\n");
                                        next;
                                    }
                                    my $mpi_install = $MTT::MPI::installs->{$mpi_get_key}->{$mpi_version_key}->{$mpi_install_key};
                                    _do_run($ini, $section, $test_build, 
                                            $mpi_install, $top_dir, $force);
                                    %ENV = %ENV_SAVE;
                                }
                            }
                        }
                    }                        
                }
            }
        }
    }

    Verbose("*** Run test phase complete\n");
} 

#--------------------------------------------------------------------------

sub _do_run {
    my ($ini, $section, $test_build, $mpi_install, $top_dir, $force) = @_;

    # Check for the module
    my $module = MTT::Values::Value($ini, $section, "module");
    if (!$module) {
        Warning("No module specified in [$section]; skipping\n");
        return;
    }

    Verbose(">> Running with [$mpi_install->{mpi_get_simple_section_name}] / [$mpi_install->{mpi_version}] / [$mpi_install->{simple_section_name}]\n");
    # Find an MPI details section for this MPI
    my $match = 0;
    my $mpi_details_section;
    foreach my $s ($ini->Sections()) {
        if ($s =~ /^\s*mpi details:/) {
            my $section_mpi_name = MTT::Values::Value($ini, $s, "mpi_name");
            if ($section_mpi_name eq $mpi_install->{mpi_name}) {
                Debug("Found MPI details\n");
                $match = 1;
                $mpi_details_section = $s;
                last;
            }
        }
    }
    if (!$match) {
        Warning("Unable to find MPI details section; skipping\n");
        return;
    }
    
    # Get some details about running with this MPI
    my $mpi_details;
    $MTT::Test::Run::test_prefix = $mpi_install->{installdir};
    $mpi_details->{before_any_exec} = 
        MTT::Values::Value($ini, $mpi_details_section, "before_any_exec");
    $mpi_details->{before_each_exec} = 
        MTT::Values::Value($ini, $mpi_details_section, "before_each_exec");
    $mpi_details->{after_each_exec} = 
        MTT::Values::Value($ini, $mpi_details_section, "after_each_exec");
    $mpi_details->{after_all_exec} = 
        MTT::Values::Value($ini, $mpi_details_section, "after_all_exec");
    # Do not evaluate this one now yet
    my $exec = $ini->val($mpi_details_section, "exec");
    while ($exec =~ m/@(.+?)@/) {
        my $val = $ini->val($mpi_details_section, $1);
        if (!$val) {
            Warning("Used undefined key @$1@ in exec value; skipping");
            return;
        }
        $exec =~ s/@(.+?)@/$val/;
    }
    Debug("Got final exec: $exec\n");
    $mpi_details->{exec} = $exec;
    $mpi_details->{name} = $mpi_install->{mpi_name};
    $mpi_details->{mpi_get_simple_section_name} =
        $mpi_install->{mpi_get_simple_section_name};
    $mpi_details->{mpi_install_simple_section_name} = 
        $mpi_install->{simple_section_name};
    $mpi_details->{version} = $mpi_install->{mpi_version};

    # Go to the right dir
    chdir($test_build->{srcdir});

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
            $ENV{LD_LIBRARY_PATH} = "$mpi_install->{libdir}:" . 
                $ENV{LD_LIBRARY_PATH};
        } else {
            $ENV{LD_LIBRARY_PATH} = $mpi_install->{libdir};
        }
    }

    # Process setenv, unsetenv, prepend-path, and append-path -- for
    # both the MPI that we're building with and the section of the ini
    # file that we're building.
    my @save_env;
    MTT::Values::ProcessEnvKeys($mpi_install, \@save_env);
    # JMS: Do we need to grab from Test::Build as well?
    my $config;
    %$config = %$MTT::Defaults::Test_specify;
    $config->{setenv} = MTT::Values::Value($ini, $section, "setenv");
    $config->{unsetenv} = MTT::Values::Value($ini, $section, "unsetenv");
    $config->{prepend_path} = 
        MTT::Values::Value($ini, $section, "prepend_path");
    $config->{append_path} = MTT::Values::Value($ini, $section, "append_path");
    MTT::Values::ProcessEnvKeys($config, \@save_env);

    # Get global values that apply to each test executable, unless
    # they supplied their own.  Don't use Value for all of them; some
    # we need to delay the evaluation.
    my $tmp;
    $tmp = $ini->val($section, "np");
    $config->{np} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "np_ok");
    $config->{np_ok} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "argv");
    $config->{argv} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "pass");
    $config->{pass} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "skipped");
    $config->{skipped} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "save_output_on_pass");
    $config->{save_output_on_pass} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "stderr_save_lines");
    $config->{stderr_save_lines} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "stdout_save_lines");
    $config->{stdout_save_lines} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "merge_stdout_stderr");
    $config->{merge_stdout_stderr} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "timeout");
    $config->{timeout} = $tmp
        if (defined($tmp));

    # Run the module to get a list of tests to run
    my $ret = MTT::Module::Run("MTT::Test::Run::$module",
                               "Specify", $ini, $section, $test_build,
                               $mpi_install, $config);

    # Analyze the return -- should give us a list of tests to run and
    # potentially a Perfbase XML file to analyze the results with
    if ($ret && $ret->{success}) {
        my $test_results;

        # Loop through all the tests
        foreach my $run (@{$ret->{tests}}) {
            if (!exists($run->{executable})) {
                Warning("No executable specified for text; skipped\n");
                next;
            }

            # Get the values for this test
            $run->{perfbase_xml} =
                $ret->{perfbase_xml} ? $ret->{perfbase_xml} :
                $MTT::Defaults::Test_run->{perfbase_xml};
            $run->{full_section_name} = $section;
            $run->{simple_section_name} = $section;
            $run->{simple_section_name} =~ s/^\s*test run:\s*//;

            $run->{test_build_simple_section_name} = $test_build->{simple_section_name};

            # Setup some globals
            $test_executable = $run->{executable};
            $test_argv = $run->{argv};
            my $all_np = MTT::Values::EvaluateString($run->{np});

            # Just one np, or an array of np values?
            if (ref($all_np) eq "") {
                $test_results->{$all_np} =
                    _run_one_np($top_dir, $run, $mpi_details, $all_np, $force);
            } else {
                foreach my $this_np (@$all_np) {
                    $test_results->{$this_np} =
                        _run_one_np($top_dir, $run, $mpi_details, $this_np,
                                    $force);
                }
            }
        }

        # If we ran any tests at all, then run the after_all step and
        # submit the results to the Reporter
        if (exists($mpi_details->{ran_some_tests})) {
            _run_step($mpi_details, "after_all");

            MTT::Reporter::QueueSubmit();
        }
    }
}

sub _run_one_np {
    my ($top_dir, $run, $mpi_details, $np, $force) = @_;

    my $name = basename($test_executable);

    # Load up the final global
    $test_np = $np;

    # Is this np ok for this test?
    my $ok = MTT::Values::EvaluateString($run->{np_ok});
    if ($ok) {

        # Get all the exec's for this one np
        my $execs = MTT::Values::EvaluateString($mpi_details->{exec});

        # If we just got one, run it.  Otherwise, loop over running them.
        if (ref($execs) eq "") {
            _run_one_test($top_dir, $run, $mpi_details, $execs, $name, 1,
                          $force);
        } else {
            my $variant = 1;
            foreach my $e (@$execs) {
                _run_one_test($top_dir, $run, $mpi_details, $e, $name,
                              $variant++, $force);
            }
        }
    }
}

sub _run_one_test {
    my ($top_dir, $run, $mpi_details, $cmd, $name, $variant, $force) = @_;

    # Have we run this test already?  Wow, Perl sucks sometimes -- you
    # can't check for the entire thing because the very act of
    # checking will bring all the intermediary hash levels into
    # existence if they didn't already exist.

    my $str = "   Test: " . basename($name) .
        ", np=$test_np, variant=$variant:";

    if (!$force &&
        exists($MTT::Test::runs->{$mpi_details->{mpi_get_simple_section_name}}) &&
        exists($MTT::Test::runs->{$mpi_details->{mpi_get_simple_section_name}}->{$mpi_details->{version}}) &&
        exists($MTT::Test::runs->{$mpi_details->{mpi_get_simple_section_name}}->{$mpi_details->{version}}->{$mpi_details->{mpi_install_simple_section_name}}) &&
        exists($MTT::Test::runs->{$mpi_details->{mpi_get_simple_section_name}}->{$mpi_details->{version}}->{$mpi_details->{mpi_install_simple_section_name}}->{$run->{test_build_simple_section_name}}) &&
        exists($MTT::Test::runs->{$mpi_details->{mpi_get_simple_section_name}}->{$mpi_details->{version}}->{$mpi_details->{mpi_install_simple_section_name}}->{$run->{test_build_simple_section_name}}->{$run->{simple_section_name}}) &&
        exists($MTT::Test::runs->{$mpi_details->{mpi_get_simple_section_name}}->{$mpi_details->{version}}->{$mpi_details->{mpi_install_simple_section_name}}->{$run->{test_build_simple_section_name}}->{$run->{simple_section_name}}->{$name}) &&
        exists($MTT::Test::runs->{$mpi_details->{mpi_get_simple_section_name}}->{$mpi_details->{version}}->{$mpi_details->{mpi_install_simple_section_name}}->{$run->{test_build_simple_section_name}}->{$run->{simple_section_name}}->{$name}->{$test_np}) &&
        exists($MTT::Test::runs->{$mpi_details->{mpi_get_simple_section_name}}->{$mpi_details->{version}}->{$mpi_details->{mpi_install_simple_section_name}}->{$run->{test_build_simple_section_name}}->{$run->{simple_section_name}}->{$name}->{$test_np}->{$cmd})) {
        Verbose("$str Skipped (already ran)\n");
        return;
    }

    # Setup some environment variables for steps
    delete $ENV{MTT_TEST_NP};
    $ENV{MTT_TEST_PREFIX} = $test_prefix;
    if (MTT::Values::Functions::have_hostfile()) {
        $ENV{MTT_TEST_HOSTFILE} = MTT::Values::Functions::hostfile();
    } else {
        $ENV{MTT_TEST_HOSTFILE} = "";
    }
    if (MTT::Values::Functions::have_hostlist()) {
        $ENV{MTT_TEST_HOSTLIST} = MTT::Values::Functions::hostlist();
    } else {
        $ENV{MTT_TEST_HOSTLIST} = "";
    }

    # See if we need to run the before_all step.
    if (! exists($mpi_details->{ran_some_tests})) {
        _run_step($mpi_details, "before_any");
    }
    $mpi_details->{ran_some_tests} = 1;

    # If there is a before_each step, run it
    $ENV{MTT_TEST_NP} = $test_np;
    _run_step($mpi_details, "before_each");

    my $timeout = MTT::Values::EvaluateString($run->{timeout});
    my $out_lines = MTT::Values::EvaluateString($run->{stdout_save_lines});
    my $err_lines = MTT::Values::EvaluateString($run->{stderr_save_lines});
    my $merge = MTT::Values::EvaluateString($run->{merge_stdout_stderr});
    my $start_time = time;
    my $start = timegm(gmtime());
    my $x = MTT::DoCommand::Cmd($merge, $cmd, $timeout, 
                                $out_lines, $err_lines);
    my $stop_time = time;
    my $duration = $stop_time - $start_time . " seconds";
    $test_exit_status = $x->{status};
    my $pass = MTT::Values::EvaluateString($run->{pass});
    my $skipped = MTT::Values::EvaluateString($run->{skipped});

    # result value: 1=pass, 2=fail, 3=skipped, 4=timed out
    my $result = 2;
    if ($x->{timed_out) {
        $result = 4;
    } elsif ($pass) {
        $result = 1;
    } elsif ($skipped) {
        $result = 3;
    }

    # Queue up a report on this test
    my $report = {
        phase => "Test run",

        start_test_timestamp => $start,
        test_duration_interval => $duration,

        mpi_name => $mpi_details->{name},
        mpi_version => $mpi_details->{version},
        mpi_name => $mpi_details->{mpi_get_simple_section_name},
        mpi_install_section_name => $mpi_details->{mpi_install_simple_section_name},

        perfbase_xml => $run->{perfbase_xml},

        test_name => $name,
        test_command => $cmd,
        test_build_section_name => $run->{test_build_simple_section_name},
        test_run_section_name => $run->{simple_section_name},
        test_np => $test_np,
        exit_status => $x->{status},
        test_result => $result,
    };
    my $want_output;
    if (!$pass) {
        $str =~ s/^ +//;
        if ($x->{timed_out}) {
            Warning("$str TIMED OUT (failed)\n");
        } else {
            Warning("$str FAILED\n");
        }
        $want_output = 1;
        if ($stop_time - $start_time > $timeout) {
            $report->{result_message} = "Failed; timeout expired ($timeout seconds)";
        } else {
            $report->{result_message} = "Failed; exit status: $x->{status}";
        }
    } else {
        Verbose("$str Passed\n");
        $report->{result_message} = "Passed";
        $want_output = $run->{save_output_on_pass};
    }
    if ($want_output) {
        $report->{stdout} = $x->{stdout};
        $report->{stderr} = $x->{stderr};
    }
    $MTT::Test::runs->{$mpi_details->{mpi_get_simple_section_name}}->{$mpi_details->{version}}->{$mpi_details->{mpi_install_simple_section_name}}->{$run->{test_build_simple_section_name}}->{$run->{simple_section_name}}->{$name}->{$test_np}->{$cmd} = $report;
    MTT::Test::SaveRuns($top_dir);
    MTT::Reporter::QueueAdd("Test Run", $run->{simple_section_name}, $report);

    # If there is an after_each step, run it
    _run_step($mpi_details, "after_each");

    return $pass;
}

sub _run_step {
    my ($mpi_details, $step) = @_;

    $step .= "_exec";
    if (exists($mpi_details->{$step}) && $mpi_details->{$step}) {
        Debug("Running step: $step\n");
        my $x = MTT::DoCommand::CmdScript(1, $mpi_details->{$step}, 10);
        #JMS should be checking return status here and in who invoked
        #_run_step.
    }
}

1;
