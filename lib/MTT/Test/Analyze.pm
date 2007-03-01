#!/usr/bin/env perl
#
# Copyright (c) 2006 Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2006 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Analyze;

use strict;
use Data::Dumper;
use MTT::Messages;

sub Analyze {

    my ($run, $mpi_details, $msg, $results) = @_;
    my ($correctness_results, $perf_results, $rte_results);
    my $report;

    # Analyze everything (including performance tests) for correctness
    $correctness_results = MTT::Module::Run("MTT::Test::Analyze::Correctness",
                                    "Analyze", $run, $mpi_details, $msg, 
                                    $results);

    # RTE testing needs to perform validation tests on the pid
    $correctness_results->{pid} = $run->{pid};

    # User specifies a module in the INI file
    my $m = $run->{analyze_module};
    my $module;

    if ($m) {

        if ($correctness_results->{test_result} == MTT::Values::PASS) {

            # Avoid double analyzing in the case a good citizen
            # directs us to analyze for correctness
            if ($m !~ /\bcorrectness\b/i) {

                $module = "MTT::Test::Analyze::Performance::$m";

                # Performance
                if (MTT::Module::Exists($module)) {
                    $perf_results = 
                        MTT::Module::Run($module, "Analyze", $correctness_results->{result_stdout});
                }

                $module = "MTT::Test::Analyze::RTE::$m";

                # Run Time Environment
                if (MTT::Module::Exists($module)) {
                    $rte_results = 
                        MTT::Module::Run($module, "Analyze", $correctness_results);
                }
            }
        }
    }

    # Combine the additional analysis data with correctness data
    %$report = (%$correctness_results);

    if ($perf_results) {
        %$report = (%$report, %$perf_results);
    } elsif ($rte_results) {
        %$report = (%$report, %$rte_results);
    }

    return $report;
} 

1;
