#!/usr/bin/env perl
#
# Copyright (c) 2006-2007 Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2007      Voltaire  All rights reserved.
# Copyright (c) 2009      Voltaire
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::Test::Analyze::Performance::HPLGDS;
use strict;
use Data::Dumper;
use MTT::Messages;

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
    my $output_dir=undef;
    my $max_gflops=0;
    my $hpl_version;
    while (defined($line = shift(@lines))) {
        # HPLinpack 2.0  --  High-Performance Linpack benchmark  --   September 10, 2008
        if ($line =~ m/OUTPUT:\s(\S+)/) {
            $output_dir = $1;
        }
        if ($line =~ m/HPLinpack\s+(\d+[\.\d]+)\s/) {
            $hpl_version = $1;
        } 
        #WR00L2L2       29184   128     2     4           15596.86              1.063e+00
        if ($line =~ m/^(\S+)\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+[\.\d]+)\s+(\S+)/) {
            push(@t_v, $1);
            push(@time, $2);
            push(@gflops, $3);
            if ($max_gflops < $3) {
                $max_gflops = $3;
            }
        }
    }

      # Postgres uses brackets for array insertion
    # (see postgresql.org/docs/7.4/interactive/arrays.html)
    $report->{tv}   = "{" . join(",", @t_v) . "}";
    $report->{time}   = "{" . join(",", @time) . "}";
    $report->{gflops}   = "{" . join(",", @gflops) . "}";

    # MTTGDS addon
    $report->{suiteinfo}->{suite_name} = "HPL";
    $report->{suiteinfo}->{suite_version} = $hpl_version;

    $report->{testphase}->{data_max_gflops} = $max_gflops;

    my $total_mhz = undef;
    if (defined($MTT::Reporter::MTTGDS::clusterInfo)) {
        $total_mhz = $MTT::Reporter::MTTGDS::clusterInfo->{total_mhz};
    }

    if (defined($total_mhz)) {
        my $ini = $MTT::Globals::Internals->{ini};
        my $num_of_floating_point_ops_per_cycle = MTT::Values::Value($ini, "vbench", "hpl_num_of_floating_point_ops_per_cycle");
        $num_of_floating_point_ops_per_cycle = 4 if (!defined($num_of_floating_point_ops_per_cycle) || $num_of_floating_point_ops_per_cycle eq "");
        Warning("HPL Analyser: hpl_num_of_floating_point_ops_per_cycle=$num_of_floating_point_ops_per_cycle\n");
        Warning("HPL Analyser: max_gflops=$max_gflops total_mhz=$total_mhz\n");
        my $performance = ($max_gflops * 1000.0) / ($total_mhz * $num_of_floating_point_ops_per_cycle);
        $report->{testphase}->{data_performance} = int($performance*100.0);
    } else {
        Warning("Can't fill data_performance metric: total_mhz is undefined\n");
    } 

    $report->{files_to_copy}->{"$output_dir/HPL.dat"} = "";        

    return $report;
}

sub PreReport
{
    my ($phase, $section, $report) = @_;

    my $mca = $report->{command};
    if ($mca =~ m/-cmd(\s+|=)\"([\S\s]*)\"/) {
        $mca = $2;
    }
    $mca =~ s/^\S+//;
    $mca =~ s/\s(-n|--n|-np|--np)\s\S+//;
    $mca =~ s/\s(-rf|--rankfile)\s\S+//;
    $mca =~ s/\s(-hostfile|--hostfile)\s\S+//;
    $mca =~ s/\s(-host|--host)\s\S+//;
    $mca =~ s/\s(-x)\s\S+//g;
    $mca =~ s/\s[\S\/\\]*xhpl.*//;
    $mca =~ s/\s\s/ /g;
    $mca =~ s/^\s+|\s+$//g;

    $report->{testphase}->{mpi_mca} = $mca;

    my $rankfile = undef;
    my $cmdline  = $report->{command};
    if ( $cmdline =~ m/-rf\s([\S]+)/ ) {
        $rankfile = $1;
    }
    if ( $cmdline =~ m/--rankfile\s([\S]+)/ ) {
        $rankfile = $1;
    }
    $report->{testphase}->{mpi_rlist} = $rankfile;
}

1;

