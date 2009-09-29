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

# Process the result_stdout emitted from hpcc tests
sub Analyze {
    my($result_stdout) = @_;
    my $report = ();

    my $hpcc_version = "unknown";

    my @lines = split(/\n|\r/, $result_stdout);
    
    my $output_file;
    
    # Find "Run directory: " string in stdout
    foreach my $line (@lines)
    {
    	if ($line =~ m/^OUTPUT: (.+)$/) {
           $output_file = $1 . "/hpccoutf.txt";
    	    last;
    	}	
    }
    if (!defined($output_file))
    {
        Warning("HPCC: Output file is unknown! Skipping\n");
        return undef;    	
    }
    my $error = 0;
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
    } 

    $report->{testphase}->{data_hpl_max_gflops} = $report->{testphase}->{data_hpcc_summary_hpl_tflops} * 1000.0;

    $report->{files_to_copy}->{$output_file} = "";
    
    $report->{test_name} = "hpcc";

    Verbose("HPCC: Analyze finished\n");

    print Dumper($report);

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

