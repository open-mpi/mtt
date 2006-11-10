#!/usr/bin/env perl
#
# Copyright (c) 2006 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::Test::Analyze::Performance::NetPipe;

use strict;
use Data::Dumper;
use MTT::Messages;

# Process the result_stdout emitted from a NetPipe test
sub Analyze {

    my($result_stdout) = @_;
    my $report;
    my(@bytes,
       @times,
       @mbps,
       @usec,
       $bandwidth_unit,
       $latency_unit);

    my @lines = split(/\n|\r/, $result_stdout);

    # Sample result_stdout:
    # 1: 2 bytes  440 times --> 0.05 Mbps in  293.11 usec
    # 2: 3 bytes  341 times --> 0.06 Mbps in  352.66 usec
    # 3: 4 bytes  189 times --> 0.24 Mbps in  125.22 usec
    # 4: 6 bytes  598 times --> 0.29 Mbps in  155.19 usec
    # 5: 8 bytes  322 times --> 0.35 Mbps in  172.63 usec
    # ...

    my $line;
    my $arrow = '[\s\-\>]+';
    while (defined($line = shift(@lines))) {
        if ($line =~
                (/(\d+)     \s+ bytes \s+
                  (\d+)     \s+ times $arrow
                  ([\d\.]+) \s+ (\b\w*bps\b) \s+in\s+
                  ([\d\.]+) \s+ (\b\w*sec(?:onds?)?) /ix)) {

            push(@bytes, $1);
            push(@times, $2);
            push(@mbps, $3);
            $bandwidth_unit = $4;
            push(@usec, $5);
            $latency_unit = $6;
        }
    }

    $report->{test_type} = 'latency_bandwidth';

    # Postgres uses brackets for array insertion
    # (see postgresql.org/docs/7.4/interactive/arrays.html)
    $report->{latency_avg}   = "{" . join(",", @usec) . "}";
    $report->{bandwidth_avg} = "{" . join(",", @mbps) . "}";
    $report->{message_size}  = "{" . join(",", @bytes) . "}";
    $report->{x_axis_label}  = $latency_unit;
    $report->{y_axis_label}  = $bandwidth_unit;

    return $report;
}

1;
