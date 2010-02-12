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

package MTT::Test::Analyze::Performance::Fluent;

use strict;
use Data::Dumper;
use MTT::Messages;

# Process the result emitted from fluent benchmark
sub Analyze {

    my($result_stdout) = @_;
    my $report;

    my @lines = split(/\n|\r/, $result_stdout);

    my $fluent_version = "unknown";
    
    my $rundir;
    
    # Find "Run directory: " string in stdout
    foreach my $line (@lines)
    {
    	if ($line =~ m/^Run directory: (.+)$/) {
    		$rundir = $1;
    		last;
    	}	
    }
    if (!defined($rundir))
    {
        Warning("Fluent: Run directory is unknown! Skipping\n");
        return undef;    	
    }
    Verbose("Fluent: rundir=$rundir\n");
    $report->{fluent}->{rundir} = $rundir;
    
    my $error = 0;
    Verbose("Fluent: output file: $rundir/output.log\n");
    open OUTPUT, "$rundir/output.log" || ($error = 1);

    if ($error) {
        Warning("Fluent: Unable to read output.log! Skipping\n");
        return undef;
    }

	my $archive;
	my $result_file;
    while (<OUTPUT>) {
    	if (/Creating benchmarks archive (.+)$/) {
    		$archive = $1;
    	}
        if (/Writing results in file (.+)$/) {
        	$result_file = $1;
        	last;
        }
    }
    close OUTPUT;

	Verbose("Fluent: result file: $rundir/$result_file\n");
    open RESULT, "$rundir/$result_file" || ($error = 1);

    if ($error) {
        Warning("Fluent: Unable to read $result_file! Skipping\n");
        return undef;
    }
    $report->{fluent}->{result_file} = $result_file;

    my $test_case; # eddy_417k
    my $rating;
    while (<RESULT>) {
        if (/Code\s*:\s+(\S.+)$/) {
            $fluent_version = $1;
        }
        if (/Benchmark:\s+(\S.+)$/) {
        	$test_case = $1;
        	Verbose("Fluent: test case: $test_case\n");
        	next;
        }
        if (!defined($rating) && /Rating\s+=\s(\S.+)$/) {
        	$rating = $1;
        	Verbose("Fluent: rating: $rating\n");
        	next;
        }
    }
    close RESULT;

    if (!defined($rating)) {
        return undef;
    }

    $test_case =~ s/^\s+//;
    $test_case =~ s/\s+$//;
    $report->{testphase}->{test_case} = $test_case;
    $rating =~ s/^\s+//;
    $rating =~ s/\s+$//;
    $report->{testphase}->{data_rating} = $rating;

    $report->{suiteinfo}->{suite_name} = "fluent";
    $fluent_version =~ s/^\s+|\s+$//g;
    $report->{suiteinfo}->{suite_version} = $fluent_version;

    $report->{files_to_copy}->{"$rundir/$archive"} = "$archive" if (defined($archive));

    Verbose("Fluent: Analyze finished\n");

    return $report;
}

sub PreReport
{
    my ($phase, $section, $report) = @_;

    $report->{test_name} = "fluent";
       
    if ($report->{command} =~ m/-mpiopt(\s+|=)\"([^\"]*)\"/) {
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
