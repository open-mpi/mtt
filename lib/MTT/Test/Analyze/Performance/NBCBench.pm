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

package MTT::Test::Analyze::Performance::NBCBench;

use strict;
use Data::Dumper;
use MTT::Messages;

# Process the result_stdout emitted from NBCBench
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

    # Sample output (extra "#" added in front of each line):

##------------------------------------------------------------------------
##| benchmarking MPI_Bcast 
##| on 2 to 4 nodes 
##| with sizes 4096 bytes to 262144 bytes
##| NBC_Test is done for each 2048 bytes
##| ***** 
##| using verbose output
##| each measurement is repeated 50 times and the median (1) is printed
##| 1) the reduction is done for the values of each rank and the maximum among all ranks is printed
##|-----------------------------------------------------------------------
##p size comp (tests) t_{comp} :: t_{MPI} | t_{NBC} t_{NBCCOMMOV} t_{TEST} t_{WAIT} (t_{NBCCOMMOV}-t_{CALC}) (share of ov. comm) t_{NBCINIT} t_{NBCTEST}
##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#2 4096 4096 (3)  25.99 ::  14.07 | 12.16 50.07 11.21 7.87 (24.08) (-0.98/-0.80) 2.86 3.10 :: 

    my $line;
    while (defined($line = shift(@lines))) {
        if ($line =~ /^\#/) {
            if ($line =~ m/^\#\| benchmarking (\S+)/) {
                $report->{test_name} = $1;
            }
        } elsif ($line =~ m/\d+\s/) {
            my @vals = split(/\s+/, $line);

            push(@bytes, $vals[1]);
            push(@usec, $vals[8]);
        }
    }

    $report->{test_type} = 'latency_bandwidth';

    # Postgres uses brackets for array insertion
    # (see postgresql.org/docs/7.4/interactive/arrays.html)
    $report->{latency_avg}   = "{" . join(",", @usec) . "}";
    $report->{message_size}  = "{" . join(",", @bytes) . "}";

    return $report;
}

1;
