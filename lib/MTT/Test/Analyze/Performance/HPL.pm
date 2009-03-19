#!/usr/bin/env perl
#
# Copyright (c) 2006-2007 Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2007      Voltaire  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::Test::Analyze::Performance::HPL;
use strict;
use Data::Dumper;
#use MTT::Messages;

# Process the result_stdout emitted from one of hpl tests
sub Analyze {

    my($result_stdout) = @_;
    my $report;
    my(@t_v,
       @time,
       @gflops);
    
$report->{test_name}="HPL";
    my @lines = split(/\n|\r/, $result_stdout);
    # Sample result_stdout:
#- The matrix A is randomly generated for each test.
#- The following scaled residual check will be computed:
#      ||Ax-b||_oo / ( eps * ( || x ||_oo * || A ||_oo + || b ||_oo ) * N )
#- The relative machine precision (eps) is taken to be               1.110223e-16
#- Computational tests pass if scaled residuals are less than                16.0
#================================================================================
#T/V                N    NB     P     Q               Time                 Gflops
#--------------------------------------------------------------------------------
#WR00L2L2       29184   128     2     4           15596.86              1.063e+00
#--------------------------------------------------------------------------------
#||Ax-b||_oo/(eps*(||A||_oo*||x||_oo+||b||_oo)*N)=        0.0008986 ...... PASSED
#================================================================================
#T/V                N    NB     P     Q               Time                 Gflops
#--------------------------------------------------------------------------------
#WR00L2L4       29184   128     2     4           15251.81              1.087e+00
    my $line;
    while (defined($line = shift(@lines))) {
        #WR00L2L2       29184   128     2     4           15596.86              1.063e+00
        if ($line =~ m/^(\S+)\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+[\.\d]+)\s+(\S+)/) {
            push(@t_v, $1);
            push(@time, $2);
            push(@gflops, $3);
        }
    }

      # Postgres uses brackets for array insertion
    # (see postgresql.org/docs/7.4/interactive/arrays.html)
    $report->{tv}   = "{" . join(",", @t_v) . "}";
    $report->{time}   = "{" . join(",", @time) . "}";
    $report->{gflops}   = "{" . join(",", @gflops) . "}";
    return $report;
}

1;

