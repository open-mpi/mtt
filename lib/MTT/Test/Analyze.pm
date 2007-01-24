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
    my ($correctness, $performance);
    my $report;

    # Analyze everything (including performance tests) for correctness
    $correctness = MTT::Module::Run("MTT::Test::Analyze::Correctness",
                                    "Analyze", $run, $mpi_details, $msg, 
                                    $results);

    my $m = $run->{analyze_module};

    # Avoid double analyzing in the case a good citizen
    # directs us to analyze for correctness
    if ($correctness->{test_result} == MTT::Values::PASS) {
        if ($m and ($m !~ /\bcorrectness\b/i)) {
            $performance = MTT::Module::Run("MTT::Test::Analyze::Performance::$m", 
                                    "Analyze", $correctness->{result_stdout});
        }
    }

    %$report = (%$correctness);
    %$report = (%$report, %$performance) if ($performance);

    return $report;
} 

1;
