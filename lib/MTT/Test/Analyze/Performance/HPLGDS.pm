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

my $error_str = "HPL: Input file corrupted";

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
    my $output_dir=".";
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
        return undef;
    }

    my $input_file = "$output_dir/HPL.dat";
    $report->{files_to_copy}->{$input_file} = "";        
 
    open my $input, "$input_file" || ($error = 1);

    if ($error) {
        Warning("HPL: Unable to read $input_file! Skipping\n");
        return undef;
    }

    my $inputline;
    $inputline = <$input>; if (!defined($inputline)) { Debug($error_str . "\n"); return undef; }
    $inputline = <$input>; if (!defined($inputline)) { Debug($error_str . "\n"); return undef; }
    $inputline = <$input>; if (!defined($inputline)) { Debug($error_str . "\n"); return undef; }
    $inputline = <$input>; if (!defined($inputline)) { Debug($error_str . "\n"); return undef; }
    
    my $ncount = process_input_one_parameter(\%$report, $input, "n_count"); if (!defined($ncount)) { return undef; }
    if (!defined(process_input_array(\%$report, $input, "n", $ncount))) { return undef; }

    my $nbcount = process_input_one_parameter(\%$report, $input, "nb_count"); if (!defined($nbcount)) { return undef; }
    if (!defined(process_input_array(\%$report, $input, "nb", $nbcount))) { return undef; }

    my $pmap = process_input_one_parameter(\%$report, $input, "pmap"); if (!defined($pmap)) { return undef; }

    my $gridcount = process_input_one_parameter(\%$report, $input, "grid_count"); if (!defined($gridcount)) { return undef; }
    if (!defined(process_input_array(\%$report, $input, "p", $gridcount))) { return undef; }
    if (!defined(process_input_array(\%$report, $input, "q", $gridcount))) { return undef; }

    my $threshold = process_input_one_parameter(\%$report, $input, "threshold"); if (!defined($threshold)) { return undef; }

    my $pfactcount = process_input_one_parameter(\%$report, $input, "pfact_count"); if (!defined($pfactcount)) { return undef; }
    if (!defined(process_input_array(\%$report, $input, "pfact", $pfactcount))) { return undef; }

    my $nbmincount = process_input_one_parameter(\%$report, $input, "nbmin_count"); if (!defined($nbmincount)) { return undef; }
    if (!defined(process_input_array(\%$report, $input, "nbmin", $nbmincount))) { return undef; }

    my $ndivcount = process_input_one_parameter(\%$report, $input, "ndiv_count"); if (!defined($ndivcount)) { return undef; }
    if (!defined(process_input_array(\%$report, $input, "ndiv", $ndivcount))) { return undef; }

    my $rfactcount = process_input_one_parameter(\%$report, $input, "rfact_count"); if (!defined($rfactcount)) { return undef; }
    if (!defined(process_input_array(\%$report, $input, "rfact", $rfactcount))) { return undef; }

    my $bcastcount = process_input_one_parameter(\%$report, $input, "bcast_count"); if (!defined($bcastcount)) { return undef; }
    if (!defined(process_input_array(\%$report, $input, "bcast", $bcastcount))) { return undef; }

    my $depthcount = process_input_one_parameter(\%$report, $input, "depth_count"); if (!defined($depthcount)) { return undef; }
    if (!defined(process_input_array(\%$report, $input, "depth", $depthcount))) { return undef; }

    my $swap = process_input_one_parameter(\%$report, $input, "swap"); if (!defined($swap)) { return undef; }

    my $swapthreshold = process_input_one_parameter(\%$report, $input, "swap_threshold"); if (!defined($swapthreshold)) { return undef; }

    my $l1 = process_input_one_parameter(\%$report, $input, "l1"); if (!defined($l1)) { return undef; }

    my $u = process_input_one_parameter(\%$report, $input, "u"); if (!defined($u)) { return undef; }

    my $equil = process_input_one_parameter(\%$report, $input, "equil"); if (!defined($equil)) { return undef; }

    my $hpl_align = process_input_one_parameter(\%$report, $input, "align"); if (!defined($hpl_align)) { return undef; }

    close $input;

    return $report;
}

sub process_input_one_parameter
{
    my ($report, $input, $parameter_name) = @_;
    my $inputline;
    $inputline = <$input>; if (!defined($inputline)) { Debug($error_str . "\n"); return undef; }
    my $res;
    if ($inputline =~ m/^([\d.]+)\s/) {
        $res = $1;
        ${report}->{testphase}->{"custom_hpl_input_" . $parameter_name} = $res;
        return $res;
    } else { Debug($error_str . ": " . $inputline . "\n"); return undef; }
}

sub process_input_array
{
    my ($report, $input, $parameter_name, $count) = @_;
    my $inputline;
    $inputline = <$input>; if (!defined($inputline)) { Debug($error_str . "\n"); return undef; }
    my $value = "";
    for (my $i=1; $i <= $count; $i++) {
        if ($inputline =~ m/^([\d.]+)\s/) {
            $value .= $1; $value .= " " if ($i != $count);
            #${report}->{testphase}->{"custom_hpl_input_" . $parameter_name . "_" . lc($i)} = $1;
            $inputline =~ s/^([\d.]+)\s//;
        } else { Debug($error_str . ": " . $inputline . "\n"); return undef; }
    } 
    ${report}->{testphase}->{"custom_hpl_input_" . $parameter_name} = $value;
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

