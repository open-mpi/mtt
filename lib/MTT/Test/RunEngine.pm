#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2007 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007-2008 Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2008      Mellanox Technologies.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::RunEngine;

use strict;
use File::Basename;
use Time::Local;
use Cwd;
use MTT::Messages;
use MTT::Values;
use MTT::Reporter;
use MTT::Defaults;
use MTT::Util;
use MTT::INI;
use MTT::DoCommand;
use Data::Dumper;

#--------------------------------------------------------------------------

my $verbose_out;

# Pointer to INI structure and full Test Run
# section name (needed for $var substitution in
# below EvaluateString() calls)
my $ini;
my $section;
my $mpi_details_name;
my $test_run_full_name;
my $break_threshold;
my $shuffle;
# Keep track of how many tests have passed, failed, skipped, and timed out
my $test_results_count;

#same as test_results_count but global over all envokations of RunEngine
my $test_results_count_global;

# Submit results after each run or after *all* the runs
my $report_after_each_result = 0;
my $report_results_count = 0;
my $report_after_n_results;
my $prev_section_name = undef;
my $group_reports = 0;

#--------------------------------------------------------------------------

sub RunEngine {
    # These arguments are local to this function
    my ($install_dir, $runs_data_dir, $mpi_details, $test_build, $force, $ret);

    # Make sure though, that the $ini remains a global
    ($ini, $section, $install_dir, $runs_data_dir, $mpi_details, $test_build, $force, $ret, my $count_total_tests_number) = @_;

    my $test_results;
    $group_reports = MTT::Values::Value($ini, "mtt", "submit_group_results");
    Verbose(">>> Using group_reports\n") if ($group_reports);

    # Setup some global variables
    $mpi_details_name   = $MTT::Globals::Internals->{mpi_details_name};
    $test_run_full_name = $MTT::Globals::Internals->{test_run_full_name};

    # Reset the results counter for each invocation of RunEngine
    $test_results_count = undef;

    # Count the number of variants (for use in a break_threshold)
    my $tmp;
    my $test_count_total = $#{$ret->{tests}} + 1;
    $tmp = get_array_ref(MTT::Values::EvaluateString($ret->{tests}[0]->{np}, $ini, $test_run_full_name));
    my $np_count_total = scalar @$tmp;
    $tmp = get_array_ref(MTT::Values::EvaluateString($ret->{tests}[0]->{argv}, $ini, $test_run_full_name));
    my $argv_count_total = scalar @$tmp;
    $tmp = get_array_ref(MTT::Values::EvaluateString($mpi_details->{exec}, $ini, $mpi_details_name));
    my $exec_count_total = scalar @$tmp;
    my $variants_count_total =
        $test_count_total * $np_count_total * $argv_count_total * $exec_count_total;
        

    if ($count_total_tests_number eq "yes"){
        return $variants_count_total;
    }
    Verbose("   ###\n");
    Verbose("   ### Total tests to run in this section:\n");
    Verbose("   ###     " . sprintf("%4d", $test_count_total) . " test executable(s)\n");
    Verbose("   ###     " . sprintf("%4d", $np_count_total) . " np value(s)\n");
    Verbose("   ###     " . sprintf("%4d", $argv_count_total) . " argv value(s)\n");
    Verbose("   ###     " . sprintf("%4d", $exec_count_total) . " test variant(s)\n");
    Verbose("   ###     " . sprintf("%4d", $variants_count_total) . " total mpirun command(s) to run\n");
    Verbose("   ###\n");
	if (!$variants_count_total){
        my $footer = "";
		$footer = $footer."Warning: [Test run $section] is skipped.\n";
        $footer = $footer."Reason: total tests variants number is zero - check ini settings.\n";
        $footer = $footer."Number of total executables found: $test_count_total\n";
        $footer = $footer."Number of total np values found: $np_count_total\n";
        $footer = $footer."Number of total argv values found: $argv_count_total\n";
        $footer = $footer."Number of total exec variants found: $exec_count_total\n";
        $footer = $footer."-----------------------------------------------------------------\n";
        $MTT::Globals::Values->{extra_footer} = $footer;
		return;
	}
    
    
    
    # Set some thresholds for an early exit
    $break_threshold = undef;
    $break_threshold->{MTT::Values::PASS}      = Value($ini, $section, "break_threshold_pass");
    $break_threshold->{MTT::Values::FAIL}      = Value($ini, $section, "break_threshold_fail");
    $break_threshold->{MTT::Values::TIMED_OUT} = Value($ini, $section, "break_threshold_timeout");
    $break_threshold->{MTT::Values::SKIPPED}   = Value($ini, $section, "break_threshold_skipped");
    $break_threshold->{MTT::Values::TIMED_OUT_OR_FAIL} = Value($ini, "mtt", "break_threshold_timeout_and_fail");
    
   	$shuffle = undef;
    _register_shuffles($ini,$section);
    
	my $reports_per_job = Value($ini, "mtt", "reports_per_job");
    # This boolean value defaults to 0, and allows the user to submit results
    # after each test to ensure at least *some* results are submitted (in case
    # a single test sets the cluster on fire)
    $report_after_each_result = 
        Logical($ini, $section, "report_after_each_result");
    $report_after_n_results = Value($ini, $section, "report_after_n_results");

    # Deprecated names (to be removed)
    $report_after_each_result = 
        Logical($ini, $section, "submit_after_each_result")
        if (!defined($report_after_each_result));
    $report_after_n_results = 
        Value($ini, $section, "submit_results_after_n_results")
        if (!defined($report_after_n_results));
    $report_after_n_results = 100
        if (!defined($report_after_n_results));

    # Normalize the thresholds. Acceptable formats:
    #   * D%  - percentage
    #   * D/D - fraction
    #   * 0.D - decimal
    #   * D   - integer count of tests
    foreach my $k (keys %$break_threshold) {
        my $str = $break_threshold->{$k};
        my $result_label = $MTT::Values::result_messages->{$k};
        my $value;

        # There must be at least one non-space character
        if ($str !~ /\S/) {
            delete $break_threshold->{$k};
            next;
        }

        # Percentage
        if ($str =~ /(\d+(?:\.\d+)?)\s*\%/) {
            $value = $1 / 100;
            $break_threshold->{$k} = $value;

        # Plain integer (count of tests)
        } elsif ($str =~ /^\s*(\d+)\s*$/) {
            $value = 1;
            $value = $1 / $variants_count_total unless $variants_count_total=0;
            $break_threshold->{$k} = $value;

        # All other eval-able Perl expressions
        } else {
            eval("\$value = $str;");
            if ($@) {
                Error("RunEngine aborted: could not eval $str for break_threshold: $!.\n " .
                      "Please use either a percentage (D%), a fraction (0.D), an expression (D/D), or \n" .
                      "an integer count (D).\n");
            }
        }

        my $per = sprintf("%d%%", $value * 100);
        Verbose("Got break_threshold_$result_label of $per\n");
        $break_threshold->{$k} = $value;
    }

    # Loop through all the tests
    $verbose_out = 0;
    my $test_count = 0;
    my $printed = 0;
    if ($shuffle->{tests}){
    	MTT::Util::shuffle(\@{$ret->{tests}});
    }
    
    foreach my $run (@{$ret->{tests}}) {

        # See if we're supposed to terminate.
        last
            if (MTT::Util::time_to_terminate());

        last
            if (MTT::Util::check_break_threshold(
                    $test_results_count,
                    $break_threshold,
                    $variants_count_total)
            );

        $printed = 0;
        if (!exists($run->{executable})) {
            Warning("No executable specified for test; skipped\n");
            next;
        }

        # Get the values for this test
        $run->{description} = $ret->{description};
        $run->{full_section_name} = $section;
        $run->{simple_section_name} = GetSimpleSection($section);
        $run->{analyze_module} = $ret->{analyze_module};

        
        $run->{test_build_simple_section_name} = $test_build->{simple_section_name};

        # Setup some globals
        $MTT::Test::Run::test_executable = $run->{executable};

        my $test_exe_abs = File::Spec->rel2abs($run->{executable});
        my $test_exe_dir = dirname($test_exe_abs);
        my $test_exe_basename = basename($test_exe_abs);
        $MTT::Test::Run::test_executable_dir = $test_exe_dir;
        $MTT::Test::Run::test_executable_abspath = $test_exe_abs;
        $MTT::Test::Run::test_executable_basename = $test_exe_basename;

        $MTT::Test::Run::test_argv = $run->{argv};
        my $all_np = MTT::Values::EvaluateString($run->{np}, $ini, $test_run_full_name);

        my $save_run_mpi_details = $MTT::Test::Run::mpi_details;
        $MTT::Test::Run::mpi_details = $run->{mpi_details}
            if (defined($run->{mpi_details}));
        
        my $wdir = MTT::Values::Value($ini, $section, "wdir");
        if ($wdir) {
            $run->{wdir} = $wdir;
        }
        # Just one np, or an array of np values?

        if (ref($all_np) eq "") {
            $test_results->{$all_np} = _run_one_np($install_dir, $run, $mpi_details, $all_np, $force);
        } else {
            if ($shuffle->{nps}){
                MTT::Util::shuffle($all_np);
            }
            foreach my $this_np (@$all_np) {
                # See if we're supposed to terminate.
                last
                   if (MTT::Util::time_to_terminate());

                $test_results->{$all_np} = _run_one_np($install_dir, $run, $mpi_details, $this_np,$force);

                last
                   if ($MTT::Globals::Internals->{is_stopped_on_break_threshold});
            }
        }

        last
           if ($MTT::Globals::Internals->{is_stopped_on_break_threshold});
        ++$test_count;

        # Write out the "to be saved" test run results
        MTT::Test::SaveRuns($runs_data_dir);

        $MTT::Test::Run::mpi_details = $save_run_mpi_details;

        # Output a progress bar
        if ($verbose_out > 50) {
            $verbose_out = 0;
            my $per = sprintf("%d%%", ($test_count / $test_count_total) * 100);
            $printed = 1;
            Verbose("   ### Test progress: $test_count of $test_count_total section test executables complete ($per)\n");
        }
    }
    Verbose("   ### Test progress: $test_count of $test_count_total section test executables complete. Moving on.\n")
        if (!$printed);

    # If we ran any tests at all, then run the after_all step and
    # submit the results to the Reporter
    if (exists($mpi_details->{ran_some_tests})) {
        _run_step($mpi_details, "after_all");
        
        MTT::Reporter::QueueSubmit();
    }

}

sub _run_one_np {
    my ($install_dir, $run, $mpi_details, $np, $force) = @_;

    $test_run_full_name = $MTT::Globals::Internals->{test_run_full_name};

    my $name;
    if (-e $MTT::Test::Run::test_executable) {
        $name = basename($MTT::Test::Run::test_executable);
    }
    $run->{name} = $name;

    # Load up the np global
    $MTT::Test::Run::test_np = $np;

    # Is this np ok for this test?
    my $ok = MTT::Values::EvaluateString($run->{np_ok}, $ini, $test_run_full_name);
    if ($ok) {

        # To implement loop for argv parameter
        # Just one argv, or an array of argv values?
        my $all_argv = MTT::Values::EvaluateString($run->{argv}, $ini, $test_run_full_name);

        if (ref($all_argv) eq "") {
            $all_argv = [$all_argv];
        }
        if ($shuffle->{args}){
            MTT::Util::shuffle($all_argv);
        }
        foreach my $this_argv (@$all_argv) {
            last
                if (MTT::Util::time_to_terminate());
            $MTT::Test::Run::test_argv = $this_argv;
        
            # Get all the exec's for this one np
            my $execs = MTT::Values::EvaluateString($mpi_details->{exec}, $ini, $mpi_details_name);
            if (ref($execs) ne "" && $shuffle->{execs}){
            	MTT::Util::shuffle($execs);	 
            }
            
            
            no strict 'refs';
            # If we just got one, make it as array and reuse code below
            if (ref($execs) eq "") {
                @$execs = ($execs);
            }

            my $variant = 1;
            my $rep_cnt = MTT::Values::Value( $ini, "Test run: $run->{simple_section_name}", 'repeat');
            $rep_cnt = 1 if (not defined $rep_cnt);

            if ($rep_cnt>1) {
                $force = 1;
            }

            foreach my $e (@$execs) {
                for(my $i=0; $i < $rep_cnt; $i++) {
                    # See if we're supposed to terminate.
                    last
                    if (MTT::Util::time_to_terminate());

                    _run_one_test($install_dir, $run, $mpi_details, $e, $name,
                        $variant++, $force);

                    last
                    if (MTT::Util::check_break_threshold(
                            $test_results_count_global,
                            $break_threshold,
                            $MTT::Globals::Internals->{total_tests_counter})
                    );
                }
            }
            use strict 'refs';
            last
            if (MTT::Util::check_break_threshold(
                    $test_results_count_global,
                    $break_threshold,
                    $MTT::Globals::Internals->{total_tests_counter})
            );
            

            $MTT::Test::Run::test_argv = undef;
        }
    }

    $MTT::Test::Run::test_np = undef;
}

sub _run_one_test {
    my ($install_dir, $run, $mpi_details, $cmd, $name, $variant, $force) = @_;

    my $basename = $MTT::Test::Run::test_executable;
    if (-e $MTT::Test::Run::test_executable) {
        $basename = basename($MTT::Test::Run::test_executable);
    }

    my $testname = $basename;
    if ($MTT::Test::Run::test_argv) {
        $testname .= " ";
        if (ref($MTT::Test::Run::test_arg)) {
            $testname .= join(" ", $MTT::Test::Run::test_argv[0]);
        } else {
            $testname .= $MTT::Test::Run::test_argv;
        }
    }

    my $str = "   Test: $testname, np=$MTT::Test::Run::test_np, variant=$variant:";

    my @keys;
    push(@keys, $mpi_details->{mpi_get_simple_section_name});
    push(@keys, $mpi_details->{version});
    push(@keys, $mpi_details->{mpi_install_simple_section_name});
    push(@keys, $run->{test_build_simple_section_name});
    push(@keys, $run->{simple_section_name});
    push(@keys, $name);
    push(@keys, $MTT::Test::Run::test_np);
    push(@keys, $cmd);

    if (!$force && defined(does_hash_key_exist($MTT::Test::runs, @keys))) {
        Verbose("$str Skipped (already ran)\n");
        ++$verbose_out;
        return;
    }

    # Save the command line global
    $MTT::Test::Run::test_command_line = $cmd;

    # Setup some environment variables for steps
    delete $ENV{MTT_TEST_NP};
    $ENV{MTT_TEST_PREFIX} = $MTT::Test::Run::test_prefix;
    $ENV{MTT_TEST_EXECUTABLE} = $MTT::Test::Run::test_executable;
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

    # See if we need to run the before_any step.
    if (! exists($mpi_details->{ran_some_tests})) {
        _run_step($mpi_details, "before_any");
    }
    $mpi_details->{ran_some_tests} = 1;

    # If there is a before_each step, run it
    $ENV{MTT_TEST_NP} = $MTT::Test::Run::test_np;
    _run_step($mpi_details, "before_each");

    my $timeout = MTT::Values::EvaluateString($run->{timeout}, $ini, $test_run_full_name);
    $timeout = MTT::Util::parse_time_to_seconds($timeout)
        if (defined($timeout));
    my $out_lines = MTT::Values::EvaluateString($run->{stdout_save_lines}, $ini, $test_run_full_name);
    my $err_lines = MTT::Values::EvaluateString($run->{stderr_save_lines}, $ini, $test_run_full_name);
    my $merge = MTT::Values::EvaluateString($run->{merge_stdout_stderr}, $ini, $test_run_full_name);
    my $start_time = time;
    $run->{start} = timegm(gmtime());

    my $old_dir = cwd();

    if ( $run->{wdir} ) {
        chdir $run->{wdir};
    }
	my $print_timestamp = MTT::Values::Value( $ini, "Test run: $run->{simple_section_name}", 'timestamp' );
    my $x = MTT::DoCommand::Cmd($merge, $cmd, $timeout, $out_lines, $err_lines,$print_timestamp);
    if ( $run->{wdir} ) {
        chdir $old_dir;
    }

    my $stop_time = time;
    $run->{stop} = timegm(gmtime());
    $run->{duration} = $stop_time - $start_time . " seconds";
    $run->{np} = $MTT::Test::Run::test_np;
    $run->{cmd} = $cmd;

    $MTT::Test::Run::test_exit_status = $x->{exit_status};
    $MTT::Test::Run::test_pid = $x->{pid};

    # Analyze the test parameters and results
    my $report;
    $report = MTT::Module::Run("MTT::Test::Analyze", "Analyze", $run, $mpi_details, $str, $x);

	$report->{already_saved_to} = undef;
    # Save characteristics of the run
    $report->{variant} = $variant;
    $report->{description} = $run->{description};
    $report->{launcher} = 
        MTT::Values::EvaluateString($mpi_details->{launcher});
    $report->{resource_manager} = 
        lc(MTT::Values::EvaluateString($mpi_details->{resource_manager}));
    $report->{resource_manager} = "none"
        if (!defined($report->{resource_manager}));
    $report->{resource_manager} = "unknown"
        if (!MTT::Util::is_valid_resource_manager_name($report->{resource_manager}));
    $report->{parameters} = 
        MTT::Values::EvaluateString($mpi_details->{parameters});
    my $tmp = MTT::Values::EvaluateString($mpi_details->{network});
    my $networks;
    my @n = MTT::Util::split_comma_list($tmp);
    foreach my $n (@n) {
        if (!MTT::Util::is_valid_network_name($n)) {
            $networks->{unknown} = 1;
        } else {
            $networks->{$n} = 1;
        }
    }
    $report->{network} = join(",", sort(keys(%$networks)));

    # Assume that the Analyze module will output one line
    ++$verbose_out;

    # For Test Runs data, we have two datasets: the "to be saved" set
    # and the "all results" set.  The "to be saved" set is a
    # relatively small set of data that is written out to disk
    # periodically (i.e., augmenting what has already been written
    # out).  The "all results" set is everything that has occurred so
    # far.  We do this because the "all results" set can get *very*
    # large, so we don't want to write out the whole thing every time
    # we save the results to disk.

    # So save this new result in both the "to be saved" and "all
    # results" sets.  We'll write out the "to be saved" results
    # shortly.

    $MTT::Test::runs_to_be_saved->{$mpi_details->{mpi_get_simple_section_name}}->{$mpi_details->{version}}->{$mpi_details->{mpi_install_simple_section_name}}->{$run->{test_build_simple_section_name}}->{$run->{simple_section_name}}->{$name}->{$MTT::Test::Run::test_np}->{$cmd} = 
        $MTT::Test::runs->{$mpi_details->{mpi_get_simple_section_name}}->{$mpi_details->{version}}->{$mpi_details->{mpi_install_simple_section_name}}->{$run->{test_build_simple_section_name}}->{$run->{simple_section_name}}->{$name}->{$MTT::Test::Run::test_np}->{$cmd} = $report;

    # Submit results after each test?
    $report_results_count++;
    if ($group_reports) {
        if ((defined $prev_section_name) and ($prev_section_name ne $run->{simple_section_name})) {
            MTT::Reporter::QueueSubmit();
            $report_results_count = 0;
        }
        MTT::Reporter::QueueAdd("Test Run", $run->{simple_section_name}, $report);
    } else { 
        MTT::Reporter::QueueAdd("Test Run", $run->{simple_section_name}, $report);
        if ($report_after_each_result or
            (defined($report_after_n_results) and
               $report_results_count > $report_after_n_results)) {
            MTT::Reporter::QueueSubmit();
            $report_results_count = 0;
        }
    }
  
  	if ($MTT::Globals::Values->{save_intermediate_report}){
		MTT::Reporter::Flush();
  	}
    # Set the test run result and increment the counter
    $ENV{MTT_TEST_RUN_RESULT} = $report->{test_result};
    $test_results_count->{$report->{test_result}}++ 
        if (exists($report->{test_result}));

    $test_results_count_global->{$report->{test_result}}++
                if (exists($report->{test_result}));

    $test_results_count_global->{MTT::Values::TIMED_OUT_OR_FAIL}++
                if (exists($report->{test_result}) && 
                    (MTT::Values::FAIL == $report->{test_result} || MTT::Values::TIMED_OUT == $report->{test_result}));
                    

    # If there is an after_each step, run it
    $ENV{MTT_TEST_RUN_RESULT_MESSAGE} =
        (MTT::Values::PASS == $report->{test_result} ? "passed" :
         (MTT::Values::FAIL == $report->{test_result} ? "failed" :
          (MTT::Values::SKIPPED == $report->{test_result} ? "skipped" :
           (MTT::Values::TIMED_OUT == $report->{test_result} ? "timed_out" : "unknown"))));
    _run_step($mpi_details, "after_each");
    delete $ENV{MTT_TEST_RUN_RESULT_MESSAGE};

    $prev_section_name = $run->{simple_section_name};
    return $run->{pass};
}

sub _run_step {
    my ($mpi_details, $step) = @_;

    $step .= "_exec";
    if (exists($mpi_details->{$step}) && $mpi_details->{$step}) {
        my $cmd = $mpi_details->{$step};

        # Get the timeout value
        my $name = $step . "_timeout";
        my $timeout = MTT::Util::parse_time_to_seconds($mpi_details->{$name});
        $timeout = 30 
            if ($timeout <= 0);

        # Get the pass criteria
        $name = $step . "_pass";
        my $pass = $mpi_details->{$name};
        $pass = "&and(&cmd_wifexited(), &eq(&cmd_wexitstatus(), 0))"
            if (!defined($pass));

        # Run the step
        my $x = MTT::DoCommand::RunStep(1, $cmd, $timeout, $ini, $section, $step);

        # Evaluate the result
        if ($x->{timed_out}) {
            Verbose("  Warning: step $step TIMED OUT\n");
            Verbose("  Output: $x->{result_stdout}\n")
                if (defined($x->{result_stdout}) && $x->{result_stdout} ne "");
        } else {
            my $pass_result = MTT::Values::EvaluateString($pass, $ini, $test_run_full_name);
            if ($pass_result != 1) {
                Verbose("  Warning: step $step FAILED\n");
                Verbose("  Output: $x->{result_stdout}\n")
                    if (defined($x->{result_stdout}) &&
                        $x->{result_stdout} ne "");
            } else {
                Debug("Step $step PASSED\n");
            }
        }
    }
}
sub _register_shuffles{
	my ($ini,$section) = @_;
	
	my $val = MTT::Values::Value($ini, $section, "shuffle_tests");
	if (defined($val)) {
	    my @shuffles = grep length, split(/\s*,\s*/,$val);
	    my @allowed_shuffles = ('tests', 'execs', 'nps', 'args', 'all', 'none');
	    my %allowed_map = map { $_ => 1} @allowed_shuffles;
	    foreach my $sh (@shuffles){
	    	if (!exists($allowed_map{$sh})){
	    		MTT::Messages::Error("<$sh> is not allowed section specific shuffle_tests value. Allowed are:", join(',',@allowed_shuffles),".");
	    	}
	    	$shuffle->{$sh} = 1;
	    }
	    if ($shuffle->{none}){
	    	$shuffle = undef;
	    }
	    if ($shuffle->{all}){
	    	foreach my $allow (@allowed_shuffles){
	    		$shuffle->{$allow} = 1;
	    	}
	    }
	    
	}
    else{
    	$shuffle = $MTT::Globals::Values->{shuffle_tests};
    }
}
1;
