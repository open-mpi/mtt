#!/usr/bin/env perl
#
# Copyright (c) 2009      Voltaire
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::Test::Analyze::Performance::PamCrash;

use strict;
use Data::Dumper;
use MTT::Messages;

# Process the result emitted from pamcrash benchmark
sub Analyze {

    my($result_stdout) = @_;
    my $report = ();

    my @lines = split(/\n|\r/, $result_stdout);

    my $pamcrash_version = "unknown";
    
    my $output_file;
    
    my $test_case = "";
    foreach my $line (@lines)
    {
    	if ($line =~ m/Version\s+:\s+(.+)$/) {
    		$pamcrash_version = $1;
    	}	
    	if ($line =~ m/CASE: (.+)$/) {
    		$test_case = $1;
    	}	
    	if ($line =~ m/^OUTPUT: (.+)$/) {
    		$output_file = $1;
    	}	
    }
    if (!defined($output_file))
    {
        Warning("PamCrash: Output file is unknown! Skipping\n");
        return undef;    	
    }
    my $error = 0;
    Verbose("PamCrash: output file: $output_file\n");
    open OUTPUT, "$output_file" || ($error = 1);

    if ($error) {
        Warning("PamCrash: Unable to read $output_file! Skipping\n");
        return undef;
    }

    my $exec_time;
    my $clock_time;
    while (<OUTPUT>) {
        if (/ CPU TIME\s+([-+]?[0-9]*\.?[0-9]+[eE][-+]?[0-9]+)\s/) {
        	$clock_time = $1;
        	next;
        }
        if (/ ELAPSED TIME\s+([-+]?[0-9]*\.?[0-9]+[eE][-+]?[0-9]+)\s/) {
        	$exec_time = $1;
        	next;
        }
    }
    if (!defined($exec_time) || !defined($clock_time)) {
        return undef;
    }
    Verbose("PamCrash: exec_time=$exec_time, clock_time=$clock_time\n");
    close OUTPUT;

    $test_case =~ s/^\s+//;
    $test_case =~ s/\s+$//;
    $report->{testphase}->{test_case} = $test_case;
    $exec_time =~ s/^\s+//;
    $exec_time =~ s/\s+$//;
    $report->{testphase}->{data_exectime} = $exec_time;
    $clock_time =~ s/^\s+//;
    $clock_time =~ s/\s+$//;
    $report->{testphase}->{data_clocktime} = $clock_time;

    $report->{suiteinfo}->{suite_name} = "pamcrash";
    $pamcrash_version =~ s/^\s+|\s+$//g;
    $report->{suiteinfo}->{suite_version} = $pamcrash_version;

    $report->{files_to_copy}->{$output_file} = "";
    
    Verbose("PamCrash: Analyze finished\n");

    return $report;
}

sub PreReport
{
    my ($phase, $section, $report) = @_;

    $report->{test_name} = "pamcrash";
	
    if ($report->{command} =~ m/-mpiopt(\s+|=)\"([^\"]*)\"/) {
        my $mca = $2;
        Debug("Found mpiopt parameter: $mca\n");
        $mca =~ s/\s*(-n|--n|-np|--np)\s\S+//;
        $mca =~ s/\s*(-rf|--rankfile)\s\S+//;
        $mca =~ s/\s*(-hostfile|--hostfile)\s\S+//;
        $mca =~ s/\s*(-host|--host)\s\S+//;
        $mca =~ s/\s*(-x)\s\S+//g;
        $mca =~ s/\s+\s/ /g;
        $mca =~ s/^\s+|\s+$//g;
        Debug("mca parameter: $mca\n");
        $report->{testphase}->{mpi_mca} = $mca;
    } else {
        Warning("Fluent: can't find -mpiopt parameter: $report->{command}\n");
        $report->{testphase}->{mpi_mca} = "";
    }
   
    if ($report->{command} =~ m/-rf\s+([\S.]+)/) {
        $report->{testphase}->{mpi_rlist} = $1;
    } else {
        $report->{testphase}->{mpi_rlist} = "";
    }
}

1;
