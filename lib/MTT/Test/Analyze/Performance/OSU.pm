#!/usr/bin/env perl
#
# Copyright (c) 2006 Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2007 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::Test::Analyze::Performance::OSU;

use strict;
use Data::Dumper;
use MTT::Messages;

# Process the result_stdout emitted from one of 3 OSU tests: osu_bw,
# osu_latency, osu_bibw
sub Analyze {

    my($result_stdout) = @_;
    my $report;
    my(@bytes,
       @times,
       @mbps,
       @usec);

    my @lines = split(/\n|\r/, $result_stdout);
    if ($lines[0] =~ /MPI Latency/) {
        $report->{test_name} = "osu_latency";
    } elsif ($lines[0] =~ /MPI Bandwidth/) {
        $report->{test_name} = "osu_bw";
    } elsif ($lines[0] =~ /MPI Bidirectional Bandwidth/) {
        $report->{test_name} = "osu_bibw";
    } else {
        Warning("Unknown OSU benchmark!  Skipping\n");
        return undef;
    }

    # Sample result_stdout:
    # # OSU MPI Bandwidth Test (Version 2.1)
    # # Size          Bandwidth (MB/s) 
    # 1               0.375650
    # 2               0.942838

    # # OSU MPI Latency Test (Version 2.1)
    # # Size          Latency (us) 
    # 0               5.05
    # 1               5.56

    # # OSU MPI Bidirectional Bandwidth Test (Version 2.1)
    # # Size          Bi-Bandwidth (MB/s) 
    # 1               0.477860
    # 2               0.947305

    my $line;
    my $bandwidth = 0;
    my $latency = 0;
    while (defined($line = shift(@lines))) {
        if ($line =~ /^\#/) {
            $bandwidth = 1
                if ($line =~ /\(MB\/s\)/);
            $latency = 1
                if ($line =~ /\(us\)/);
        } elsif (0 == $bandwidth && 0 == $latency) {
            Warning("Got unexpected input for OSU performance analyzer; unable to parse the output.  Skipping.");
            return undef;
        }

        if ($line =~ m/^(\d+) \s+ ([\d\.]+)/x) {
            push(@bytes, $1);
            push(@usec, $2)
                if ($latency);
            # OSU bw and bibw report in million bytes per second;
            # we need to convert to mega (2^20) bits per second.
            push(@mbps, $2 * (1000000.0 / 1048576.0) * 8)
                if ($bandwidth);
        }
    }

    $report->{test_type} = 'latency_bandwidth';

    # Postgres uses brackets for array insertion
    # (see postgresql.org/docs/7.4/interactive/arrays.html)
    $report->{latency_avg}   = "{" . join(",", @usec) . "}"
        if ($latency);
    $report->{bandwidth_avg} = "{" . join(",", @mbps) . "}"
        if ($bandwidth);
    $report->{message_size}  = "{" . join(",", @bytes) . "}";

    return $report;
}

1;
