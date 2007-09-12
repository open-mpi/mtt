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

package MTT::Test::Analyze::Performance::SKaMPI;

use strict;
use Data::Dumper;
use MTT::Messages;

# Process the result_stdout emitted from SKaMPI
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

    # Sample output (from running input_files/coll_bcast.ski with 2
    # MPI processes):

    # # SKaMPI Version 5.0 rev. 191
    #
    # begin result "MPI_Bcast-nodes-length"
    # nodes= 2 count= 1        1       6.6       0.1       54       3.1       6.6

    # For all skampi tests except barrier, the columns are:

    # [#procs]  [# elements] [Msg size[B]] [Duration [usec]] [STD [usec]] [# of repetitions] [measured values on all processes]

    # For barrier, it is the same except there is no message size.

    my $line;
    while (defined($line = shift(@lines))) {
        if ($line =~ m/^nodes=/) {
            my @vals = split(/\s+/, $line);

            # If we're running barrier, there is no message size in
            # the output
            if ($report->{test_name} =~ /barrier/i) {
                push(@bytes, 0);
                push(@usec, $vals[4]);
            } else {
                push(@bytes, $vals[4]);
                push(@usec, $vals[5]);
            }
        } elsif ($line =~ m/begin result \"(.+)\"/) {
            $report->{test_name} = $1;
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
