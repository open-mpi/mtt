#!/usr/bin/env perl
#
# Copyright (c) 2006 Sun Microsystems, Inc. All rights reserved.
# Copyright (c) 2006-2007 Cisco Systems, Inc. All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Analyze::Correctness;

use strict;
use Data::Dumper;
use MTT::Messages;
use MTT::Values;
use MTT::Test;

# Return a ready-to-submit hash of correctness test results data
sub Analyze {

    my ($run, $mpi_details, $msg, $results) = @_;

    # Only evaluatate $pass if we didn't timeout or skip
    my $skipped = MTT::Values::EvaluateString($run->{skipped});
    my $pass = 0;
    if (!$skipped && !$results->{timed_out}) {
        $pass = MTT::Values::EvaluateString($run->{pass});
    }

    # result value: 0=fail, 1=pass, 2=skipped, 3=timed out
    my $result = MTT::Values::FAIL;
    if ($skipped) {
        $result = MTT::Values::SKIPPED;
    } elsif ($results->{timed_out}) {
        $result = MTT::Values::TIMED_OUT;
    } elsif ($pass) {
        $result = MTT::Values::PASS;
    }

    # Queue up a report on this test
    my $report = {
        phase => "Test run",

        start_timestamp => $run->{start},
        stop_timestamp => $run->{stop},
        duration => $run->{duration},

        mpi_name => $mpi_details->{name},
        mpi_version => $mpi_details->{version},
        mpi_name => $mpi_details->{mpi_get_simple_section_name},
        mpi_install_section_name => $mpi_details->{mpi_install_simple_section_name},

        test_name => $run->{name},
        command => $run->{cmd},
        test_build_section_name => $run->{test_build_simple_section_name},
        test_run_section_name => $run->{simple_section_name},
        np => $run->{np},
        exit_value => MTT::DoCommand::exit_value($results->{exit_status}),
        exit_signal => MTT::DoCommand::exit_signal($results->{exit_status}),
        test_result => $result,
    };

    $report->{signal} = $results->{signal} if (defined($results->{signal}));

    my $want_output;
    my $str;
    $str = $msg;
    if ($pass) {
        Verbose("$str Passed\n");
        $report->{result_message} = "Passed";
        $want_output = $run->{save_stdout_on_pass};
    } elsif ($skipped) {
        Verbose("$str Skipped\n");
        $report->{result_message} = "Skipped";
        $want_output = $run->{save_stdout_on_pass};
    } else {
        $str =~ s/^ +//;
        if ($results->{timed_out}) {
            Warning("$str TIMED OUT (failed)\n");
        } else {
            Warning("$str FAILED\n");
        }
        $want_output = 1;
        if ($results->{timed_out}) {
            $report->{result_message} = "Failed; timeout expired (" .
                MTT::Values::EvaluateString($run->{timeout}) . " seconds) )";
        } else {
            $report->{result_message} = "Failed; ";
            if (MTT::DoCommand::wifexited($results->{exit_status})) {
                my $s = MTT::DoCommand::wexitstatus($results->{exit_status});
                $report->{result_message} .= "exit status: $s";
            } else {
                my $sig = MTT::DoCommand::wtermsig($results->{exit_status});
                $report->{result_message} .= "termination signal: $sig";
            }
        }
    }
    if ($want_output) {
        $report->{result_stdout} = $results->{result_stdout};
        $report->{result_stderr} = $results->{result_stderr};
    }
    my $test_build_id = $MTT::Test::builds->{$mpi_details->{mpi_get_simple_section_name}}->{$mpi_details->{version}}->{$mpi_details->{mpi_install_simple_section_name}}->{$run->{test_build_simple_section_name}}->{test_build_id};
    $report->{test_build_id} = $test_build_id;

    return $report;
}

1;
