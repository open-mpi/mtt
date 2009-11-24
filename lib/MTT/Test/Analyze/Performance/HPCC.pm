#!/usr/bin/env perl
#
# Copyright (c) 2009      Voltaire
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::Test::Analyze::Performance::HPCC;

use strict;
use Data::Dumper;
use MTT::Messages;

my $error_str = "HPCC: Input file corrupted";

# Process the result_stdout emitted from hpcc tests
sub Analyze {
    my($result_stdout) = @_;
    my $report = ();

    my $hpcc_version = "unknown";

    my @lines = split(/\n|\r/, $result_stdout);
    
    my $output_file;
    my $input_file;
    
    # Find "Run directory: " string in stdout
    foreach my $line (@lines)
    {
    	if ($line =~ m/^OUTPUT: (.+)$/) {
           $output_file = $1 . "/hpccoutf.txt";
           $input_file = $1 . "/hpccinf.txt";
           last;
    	}	
    }
    if (!defined($output_file))
    {
        Warning("HPCC: Output directory is unknown! Using current dir.\n");
        $output_file = "hpccoutf.txt";
        $input_file = "hpccinf.txt";
    }
    my $error = 0;

    Verbose("HPCC: input file: $input_file\n");
    open my $input, "$input_file" || ($error = 1);

    if ($error) {
        Warning("HPCC: Unable to read $input_file! Skipping\n");
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


    Verbose("HPCC: output file: $output_file\n");
    open OUTPUT, "$output_file" || ($error = 1);

    if ($error) {
        Warning("HPCC: Unable to read $output_file! Skipping\n");
        return undef;
    }

    my $save_results = 0;
    while (<OUTPUT>) {
        if (/HPC Challenge Benchmark version\s*([\d\.]+)/) {
            $hpcc_version = $1;
        }
        if (/Begin of Summary section./) {
            $save_results = 1;
            Debug("Found result section.\n");
            next;
        }
        if (/End of Summary section./) {
            $save_results = 0;
            Debug("End of result section.\n");
            last;
        }
        next if ($save_results != 1);

        if ($_ =~ m/^(\S+)=([\S\d\.]+)$/) {
           $report->{testphase}->{"data_hpcc_summary_" . lc($1)} = $2;
           next;
        }

        Warning("HPCC: Can't process data: $_\n");
    }
    close OUTPUT;

    $report->{suiteinfo}->{suite_name} = "hpcc";
    $report->{suiteinfo}->{suite_version} = $hpcc_version;

    my $total_mhz = undef;
    if (defined($MTT::Reporter::MTTGDS::clusterInfo)) {
        $total_mhz = $MTT::Reporter::MTTGDS::clusterInfo->{total_mhz};
    }

    if (defined($total_mhz)) {
        my $ini = $MTT::Globals::Internals->{ini};
        my $num_of_floating_point_ops_per_cycle = MTT::Values::Value($ini, "vbench", "hpl_num_of_floating_point_ops_per_cycle");
        $num_of_floating_point_ops_per_cycle = 4 if (!defined($num_of_floating_point_ops_per_cycle) || $num_of_floating_point_ops_per_cycle eq "");
        Warning("HPCC Analyser: hpl_num_of_floating_point_ops_per_cycle=$num_of_floating_point_ops_per_cycle\n");
        Warning("HPCC Analyser: hpl_tflops=" . $report->{testphase}->{data_hpcc_summary_hpl_tflops} . " total_mhz=$total_mhz\n");
        my $performance = ($report->{testphase}->{data_hpcc_summary_hpl_tflops} * 1000000.0) / ($total_mhz * $num_of_floating_point_ops_per_cycle);
        $report->{testphase}->{data_hpl_performance} = int($performance*100.0);
    } else {
        Warning("Can't fill data_hpl_performance metric: total_mhz is undefined\n");
        return undef;
    } 

    $report->{testphase}->{data_hpl_max_gflops} = $report->{testphase}->{data_hpcc_summary_hpl_tflops} * 1000.0;

    $report->{files_to_copy}->{$output_file} = "";
    $report->{files_to_copy}->{$input_file} = "";
    
    $report->{test_name} = "hpcc";

    Verbose("HPCC: Analyze finished\n");

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
    $mca =~ s/\s[\S\/\\]*hpcc.*//;
    $mca =~ s/\s(-x)\s\S+//g;
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

