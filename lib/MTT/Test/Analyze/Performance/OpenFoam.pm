#!/usr/bin/env perl
#
# Copyright (c) 2009      Voltaire
# Copyright (c) 2010 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::Test::Analyze::Performance::OpenFoam;

use strict;
use Data::Dumper;
use MTT::Messages;

# Process the result emitted from openfoam benchmark
sub Analyze {

    my($result_stdout) = @_;
    my $report = ();

    my $openfoam_version = "unknown";

    my @lines = split(/\n|\r/, $result_stdout);
    
    my $output_file;
    
    my $test_exec; # oodles
    my $test_case; # pitzDaily

    foreach my $line (@lines)
    {
        if (!defined($test_exec) && $line =~ /EXEC:\s+(\S.+)$/) {
        	$test_exec = $1;
        	Verbose("OpenFoam: test exec: $test_exec\n");
        	next;
        }
        if (!defined($test_case) && $line =~ /CASE:\s+(\S.+)$/) {
        	$test_case = $1;
        	Verbose("OpenFoam: test case: $test_case\n");
        	next;
        }
        if ($line =~ m/^OUTPUT: (.+)$/) {
            $output_file = $1;
            last;
        }
    }
    if (!defined($output_file))
    {
        Warning("OpenFoam: Output file is unknown! Skipping\n");
        return undef;    	
    }
    my $error = 0;
    Verbose("OpenFoam: output file: $output_file\n");
    open OUTPUT, "$output_file" || ($error = 1);

    if ($error) {
        Warning("OpenFoam: Unable to read $output_file! Skipping\n");
        return undef;
    }

    my $exec_time;
    my $clock_time;
    while (<OUTPUT>) {
        if (/ExecutionTime\s=\s+([\d\.]+)\ss\s+ClockTime\s=\s+([\d\.]+)/) {
        	$exec_time = $1;
        	$clock_time = $2;
        	next;
        }
        if (/Version:\s+([\d\.\S]+)\s/) {
            $openfoam_version = $1;
        }
    }
    if (!defined($exec_time) || !defined($clock_time)) {
        return undef;
    }
    Verbose("OpenFoam: exec_time=$exec_time, clock_time=$clock_time\n");
    close OUTPUT;

    $test_case =~ s/^\s+//;
    $test_case =~ s/\s+$//;
    $report->{testphase}->{test_case} = "$test_exec/$test_case";
    $exec_time =~ s/^\s+//;
    $exec_time =~ s/\s+$//;
    $report->{testphase}->{data_exectime} = $exec_time;
    $clock_time =~ s/^\s+//;
    $clock_time =~ s/\s+$//;
    $report->{testphase}->{data_clocktime} = $clock_time;

    $report->{suiteinfo}->{suite_name} = "openfoam";
    $report->{suiteinfo}->{suite_version} = $openfoam_version;

    $report->{files_to_copy}->{$output_file} = "";
    
    Verbose("OpenFoam: Analyze finished\n");

    return $report;
}

sub PreReport
{
    my ($phase, $section, $report) = @_;

    $report->{test_name} = "openfoam";
	
    if ($report->{command} =~ m/-mpiopt(\s+|=)\"\'?([^\"]*)\'?\"/) {
        Debug("Found mpiopt parameter: $2\n");
        $report->{testphase}->{mpi_mca} =
            MTT::Values::Functions::MPI::OMPI::find_mca_params($2);
        Debug("Extracted mca parameters: $report->{testphase}->{mpi_mca}\n");
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
