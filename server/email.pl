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

my $PBCMD = "perfbase query -d query_mpi_install.xml";
my $SEP = "=====================================================================\n";
my $LINETOKEN = "XXXXX";



# Take a line of input, and if it is the column header line,
#  return an array containing the column headers.  Otherwise, return undef.
sub ParseHeaders {
    my ($line) = @_;
    my @columns;

    # We key on '# ' to determine if this is a column header line.
    return undef unless $line =~ /^# /;

    # Must be column header line.. break it up!
    $line =~ s/^# //;
    $line =~ s/\[\]//g;
    @columns = split(/	/, $line);    # Literal TAB matched

    return @columns;
}


# Take a hash of results and generate text output
sub GenOutput {
    my (%results) = @_;

    #print Dumper(%results);

    # Split stderr/stdout/environment back into multiple lines
    $results{'environment'} =~ s/$LINETOKEN/\n/g;
    $results{'stdout'} =~ s/$LINETOKEN/\n/g;
    $results{'stderr'} =~ s/$LINETOKEN/\n/g;

    my $output = $SEP .
        "MPI Name: $results{'mpi_name'} $results{'mpi_version'}\n" .
        "MPI Unique ID: $results{'mpi_unique_id'}\n\n" .
        "Hostname: $results{'hostname'}\n" .
        "Operating System: $results{'os_version'}\n" .
        "Platform Type: $results{'platform_type'}\n" .
        "Platform ID: $results{'platform_id'}\n" .
        "Compiler: $results{'compiler_name'} $results{'compiler_version'}\n" .
        "Configure Arguments: $results{'configure_arguments'}\n" .
        "Start Date: $results{'start_timestamp'}\n" .
        "Finish Date: $results{'stop_timestamp'}\n\n" .
        "Result: $results{'result_message'}\n\n" .
        "Environment:\n$results{'environment'}\n\n" .
        "Stdout:\n$results{'stdout'}\n\n" .
        "Stderr:\n$results{'stderr'}\n";

    return $output;
}


# Run the perfbase query
if(!open(PBQUERY, "$PBCMD|")) {
    print "Unable to run query!\n";
    die;
}

my @output = <PBQUERY>;
chomp(@output);
close(PBQUERY);

# Find the column header line and parse it.
my @columns;
for(@output) {
    @columns = ParseHeaders($_);
    last if defined(@columns);
}

#for(@columns) {
#    print "'$_'\n";
#}


# Now we have the field names in an array.
# Loop over each line, putting all the results for that line into a hash.
# The keys in this hash are the field names, the values are results.

my $mailbody = "";
my $successes = 0;
my $failures = 0;

for(@output) {
    # Skip commented lines
    next if($_ =~ /^#/);

    print ("line: $_\n");
    my $i = 0;
    my %results;
    for(split(/	/, $_)) {    # Literal TAB matched
        $_ =~ s/ *$//;
        $results{$columns[$i]} = $_;
        $i++;
    }

    if($results{'result_message'} eq "Success") {
        $successes++;
     } else {
         $failures++;
     }
#    print Dumper(%results);
    $mailbody .= GenOutput(%results);
}

# Put the header on the front of the mail body.
$mailbody = "MTT MPI Install Report\n\n" .
    "Summary:\n" .
    " $successes Successful installs\n" .
    " $failures Failed installs\n\n" .
    $mailbody;

print "$mailbody\n";
# TODO: Only show results in the past day
# Sum up success/failure counts
# Actually send off the email..

