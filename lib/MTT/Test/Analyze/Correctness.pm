#!/usr/bin/env perl
#
# Copyright (c) 2006 Sun Microsystems, Inc. All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Analyze::Correctness;

use strict;
use MTT::Messages;
use Data::Dumper;

# Return a ready-to-submit hash of correctness test results data
sub Analyze {

    my ($run, $mpi_details, $results) = @_;

    my $pass = MTT::Values::EvaluateString($run->{pass});
    my $skipped = MTT::Values::EvaluateString($run->{skipped});

    # result value: 1=pass, 2=fail, 3=skipped, 4=timed out
    my $result = 2;
    if ($results->{timed_out}) {
        $result = 4;
    } elsif ($pass) {
        $result = 1;
    } elsif ($skipped) {
        $result = 3;
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
        exit_status => $results->{exit_status},
        test_result => $result,
    };
    my $want_output;
    my $str;
    if (!$pass) {
        $str =~ s/^ +//;
        if ($results->{timed_out}) {
            Warning("$str TIMED OUT (failed)\n");
        } else {
            Warning("$str FAILED\n");
        }
        $want_output = 1;
        if ($run->{stop_time} - $run->{start_time} > $run->{timeout}) {
            $report->{result_message} = "Failed; timeout expired ($run->{timeout} seconds)";
        } else {
            $report->{result_message} = "Failed; exit_status: $results->{exit_status}";
        }
    } else {
        Verbose("$str Passed\n");
        $report->{result_message} = "Passed";
        $want_output = $run->{save_stdout_on_pass};
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
