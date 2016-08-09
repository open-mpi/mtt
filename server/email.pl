#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

use strict;
use Data::Dumper;
use Getopt::Long;
use File::Basename;
use Cwd;

# Try to find the MTT files.  Assume that mtt executable is in the
# base directory for the MTT files.  Try three methods:

# 1. With no effort; see if we can just "require" and find MTT files.
# 2. If $0 is a path, try adding that do @INC and try "require" again.
# 3. Otherwise, search $ENV[PATH] for mtt, and when you find it, add
#    that directory to @INC and try again.

use lib cwd() . "/lib";

my $ret;
eval "\$ret = require MTT::Version";
if (1 != $ret) {
    my $dir = dirname($0);
    my @INC_save = @INC;

    # Change to the dir of $0 (because it might be a relative
    # directory) and add the cwd() to @INC
    my $start_dir = cwd();
    chdir($dir);
    chdir("..");
    push(@INC, cwd() . "/lib");
    chdir($start_dir);
    eval "\$ret = require MTT::Version";

    # If it didn't work, restore @INC and try looking for mtt in the
    # path

    if (1 != $ret) {
        @INC = @INC_save;
        my @dirs = split(/:/, $ENV{PATH});
        my $mtt = basename($0);
        foreach my $dir (@dirs) {

            # If we found the mtt executable, add the dir to @INC and
            # see if we can "require".  If require fails, restore @INC
            # and keep trying.
            if (-x "$dir/$mtt") {
                chdir($dir);
                chdir("..");
                push(@INC, cwd() . "/lib");
                chdir($start_dir);
                eval "\$ret = require MTT::Version";
                if (1 == $ret) {
                    last;
                } else {
                    @INC = @INC_save;
                }
            }
        }
    }

    # If we didn't find them, die.
    die "Unable to find MTT support libraries"
        if (0 == $ret);
}

# Must use "require" (run-time) for all of these, not "use"
# (compile-time)

require Config::IniFiles;
require MTT::Version;
require MTT::Messages;
require MTT::FindProgram;
require MTT::DoCommand;
require MTT::Mail;
require XML::Simple;

my $SEP = "=====================================================================\n";

my $fail_total = 0;
my $fail_mpi_install = 0;
my $fail_test_build = 0;
my $fail_test_run = 0;

my $mpi_install_arg;
my $test_build_arg;
my $test_run_arg;
my $perfbase_arg;
my $email_arg;
my $debug_arg;
my $verbose_arg;
my $version_arg;
my $help_arg;

# TODO - take the stdout_stderr_combined field into account in output
#  make it clear that they are combined or not
# should probably hide stdout if none is given

&Getopt::Long::Configure("bundling", "require_order");
my $ok = Getopt::Long::GetOptions("mpi-install=s" => \$mpi_install_arg,
                                  "test-build=s" => \$test_build_arg,
                                  "test-run=s" => \$test_run_arg,
                                  "perfbase|p=s" => \$perfbase_arg,
                                  "email|e=s" => \$email_arg,
                                  "debug|d" => \$debug_arg,
                                  "verbose|v" => \$verbose_arg,
                                  "version" => \$version_arg,
                                  "help" => \$help_arg);

if($version_arg) {
    print "MTT Version $MTT::Version::Major.$MTT::Version::Minor\n";
    exit(0);
}
if(!$mpi_install_arg && !$test_build_arg && !$test_run_arg) {
    print "Must specify at least one of --mpi-install, --test-build, or\n",
          "--test-run arguments.\n";
    $ok = 0;
}

if(!$ok || $help_arg) {
    print("Command line error\n") if(!$ok);

    print "Options:
--mpi-install <mpi install xml>     Specify the MPI install query XML
--test-build <test build xml>       Specify the test build query XML
--test-run <test run xml>           Specify the test run query XML
--perfbase <full path>              Location of perfbase binary
--email|e <send address>            Address to email reports to
--debug|d                           Debug mode enable
--verbose|v                         Verbose mode enable
--version                           MTT version information
--help|h                            This help message\n";

    exit($ok);
}

# Set up defaults
$perfbase_arg = MTT::FindProgram::FindProgram(qw(perfbase))
    unless $perfbase_arg;
$email_arg = "mtt-devel-core\@lists.open-mpi.org" unless $email_arg;


# Check debug
my $debug = $debug_arg ? 1 : 0;
my $verbose = $verbose_arg ? 1 : 0;
MTT::Messages::Messages($debug, $verbose);
MTT::Messages::Debug("Debug is $debug, Verbose is $verbose\n");


# Grab the current time/date, subtract a date, and return a string
#  in "mmm d yyyy" format.
sub GetYesterday {
    my @names =
            ("jan", "feb", "mar", "april", "may", "jun", "july", "aug", "sep");

    my $time = time() - 24 * 60 * 60; # Go back in time one day.
    my ($seconds, $minutes, $hours, $daymonth, $month, $year) = gmtime($time);
    $year += 1900;
    return "$names[$month]-$daymonth-$year";
}


# Take a dataset XML hash structure and return a 'flattened' version.
#  $dataset->{'values'}->{$key}->{'content'} becomes $dataset->{$key}
sub FlattenDataset {
    my ($dataset) = @_;

    #print Dumper($dataset);
    my $flat;
    for(keys(%{$dataset->{'value'}})) {
        MTT::Messages::Debug("Flattening $_\n");
        $flat->{$_} = $dataset->{'value'}->{$_}->{'content'};
    }

    return $flat;
}


# Take a hash of results and generate text output
sub MPIInstallOutput {
    my ($results) = @_;

    $fail_total++;
    $fail_mpi_install++;

    my $output = "$SEP\nMPI Install failure\n\n" .
        "MPI Name: $results->{'mpi_install_section_name'} " .
            "$results->{'mpi_version'}\n\n" .
        "Hostname: $results->{'hostname'}\n" .
        "Operating System: $results->{'os_version'}\n" .
        "Platform Type: $results->{'platform_type'}\n" .
        "Platform Hardware: $results->{'platform_hardware'}\n" .
        "Compiler: $results->{'compiler_name'} $results->{'compiler_version'}\n" .
        "Configure Arguments: $results->{'configure_arguments'}\n" .
        "Start Date: $results->{'start_timestamp'}\n" .
        "Finish Date: $results->{'stop_timestamp'}\n\n";

    $output .= "Environment:\n$results->{'environment'}\n\n"
        if($results->{'environment'} ne "N/A");
    if($results->{'merge_stdout_stderr'} == 0) {
        $output .= "Stdout (separated):\n$results->{'stdout'}\n\n"
            if($results->{'stdout'} ne "N/A");
        $output .= "Stderr (separated):\n$results->{'stderr'}\n\n"
            if($results->{'stderr'} ne "N/A");
    } else {
        $output .= "Merged stdout/stderr:\n$results->{'stderr'}\n\n"
            if($results->{'stderr'} ne "N/A");
    }

    MTT::Messages::Debug("***** MPIInstallOutput\n$output\n******\n");
    return $output;
}


# Take a hash of results and generate text output
sub TestBuildOutput {
    my ($results) = @_;

    $fail_total++;
    $fail_test_build++;

    my $output = "$SEP\nTest Build failure\n\n" .
        "Test Suite: $results->{'test_build_section_name'}\n" .
        "MPI Name: $results->{'mpi_install_section_name'} " .
            "$results->{'mpi_version'}\n\n" .
        "Hostname: $results->{'hostname'}\n" .
        "Operating System: $results->{'os_version'}\n" .
        "Platform Type: $results->{'platform_type'}\n" .
        "Platform Hardware: $results->{'platform_hardware'}\n" .
        "Compiler: $results->{'compiler_name'} $results->{'compiler_version'}\n" .
        "Configure Arguments: $results->{'configure_arguments'}\n" .
        "Start Date: $results->{'start_timestamp'}\n" .
        "Finish Date: $results->{'stop_timestamp'}\n\n";

    $output .= "Environment:\n$results->{'environment'}\n\n"
        if($results->{'environment'} ne "N/A");
    if($results->{'merge_stdout_stderr'} == 0) {
        $output .= "Stdout (separated):\n$results->{'stdout'}\n\n"
            if($results->{'stdout'} ne "N/A");
        $output .= "Stderr (separated):\n$results->{'stderr'}\n\n"
            if($results->{'stderr'} ne "N/A");
    } else {
        $output .= "Merged stdout/stderr:\n$results->{'stderr'}\n\n"
            if($results->{'stderr'} ne "N/A");
    }

    MTT::Messages::Debug("***** TestBuildOutput\n$output\n******\n");
    return $output;
}


# Generate a report concerning recent MPI Installs
sub DoReport {
    my ($xml, $outputfn) = @_;

    # Run the perfbase query
    #my $cmd = "$perfbase_arg query -f f.date=" . GetYesterday() . " -d $xml";
    my $cmd = "$perfbase_arg query -f f.date=jan-1-2006 -d $xml";
    MTT::Messages::Debug("Running query: $cmd");
    my $ret = MTT::DoCommand::Cmd(1, $cmd, 60);
    if($ret->{status}) {
        MTT::Messages::Warning("Perfbase query failed! Aborting report\n");
        MTT::Messages::Debug(
                "Returned $ret->{status}, output follows:\n$ret->{stdout}");
        return;
    }
   
    my $xml = XML::Simple::XMLin($ret->{stdout});
    print Dumper($xml);

    # Make sure we have a data hash inside
    if(ref($xml->{'data'} ne "HASH")) {
        MTT::Messages::Error("Invalid XML format! Aborting report\n");
        return;
    }

    # If there is only one dataset, it's a hash, otherwise we have an array.
    my $mailbody = "";
    my $type = ref($xml->{'data'}->{'dataset'});
    if($type eq "HASH") {
        $mailbody .= &$outputfn(FlattenDataset($xml->{'data'}->{'dataset'}));
    } elsif ($type eq "ARRAY") {
        for(@{$xml->{'data'}->{'dataset'}}) {

            if(ref($_) ne "HASH") {
                MTT::Messages::Error("Invalid XML format! Aborting report\n");
                return;
            }

            $mailbody .= &$outputfn(FlattenDataset($_));
        }
    } else {
        MTT::Messages::Error("Invalid XML format! Aborting report\n");
        return;
    }

    return $mailbody;
}


my $body;
$body .= DoReport($mpi_install_arg, \&MPIInstallOutput) if($mpi_install_arg);
#$body .= DoReport($test_build_arg, \&TestBuildOutput) if($test_build_arg);
#$body .= DoReport($mpi_install_arg, \&TestRunOutput) if($test_run_arg);

print "Body:$body\n";

my $msg = "\nTotal failures: $fail_total\n" .
                "MPI Install failures: $fail_mpi_install\n" .
                "MPI Test Build failures: $fail_test_build\n" .
                "MPI Test Run failures: $fail_test_run\n\n";
$msg .= $body;        

#Set a subject based on number of failures
if($fail_total == 0) {
    MTT::Mail::Send("MTT Report - success", $email_arg, $msg);
} else {
    MTT::Mail::Send("MTT Report - $fail_total failures", $email_arg, $msg);
}

