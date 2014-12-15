#!/usr/bin/env perl

#
# Josh Hursey
#
# A script to help with the yearly update of the MTT database.
# Each year we need to add new partition tables for the upcoming year.
#

use strict;

my $database_name = "mtt";
my $database_user = "mtt";

#####################################################################
my $year;

my $argc = scalar(@ARGV);

my $cmd;
my $filename;
my @all_files = ();

#
# Check command line parameters
#
if( $argc < 1 ) {
    print "Error: Argument of a year (YYYY) is required!\n";
    print "Usage: ./yearly-table-update.pl YYYY\n";
    exit -1;
}
$year = $ARGV[0];

if( int($year) < 2000 || int($year) > 2100 ) {
    print "Error: Invalid year. Must be between 2000 and 2100\n";
    exit -1;
}

#
# Create the table files
#
print "-"x70 . "\n";
print "Creating Tables for year: $year\n";
print "-"x70 . "\n";

$cmd = "mkdir -p tmp";
if( 0 != system($cmd) ) {
    print "Error: Failed while running the following command:\n";
    print "\t$cmd\n";
    exit -1;
}


$filename = "tmp/" . $year . "-mpi-install.sql";
$cmd = "./create-partitions-mpi-install.pl " . $year . " XX > " . $filename;
print "\tCreating file: " . $filename . "\n";
push(@all_files, $filename);

if( 0 != system($cmd) ) {
    print "Error: Failed while running the following command:\n";
    print "\t$cmd\n";
    exit -1;
}


$filename = "tmp/" . $year . "-test-build.sql";
$cmd = "./create-partitions-test-build.pl " . $year . " XX > " . $filename;
print "\tCreating file: " . $filename . "\n";
push(@all_files, $filename);

if( 0 != system($cmd) ) {
    print "Error: Failed while running the following command:\n";
    print "\t$cmd\n";
    exit -1;
}


$filename = "tmp/" . $year . "-test-run.sql";
$cmd = "./create-partitions-test-run.pl " . $year . " XX > " . $filename;
print "\tCreating file: " . $filename . "\n";
push(@all_files, $filename);

if( 0 != system($cmd) ) {
    print "Error: Failed while running the following command:\n";
    print "\t$cmd\n";
    exit -1;
}

$filename = "tmp/" . $year . "-indexes.sql";
$cmd = "./create-partition-indexes.pl " . $year . " XX > " . $filename;
print "\tCreating file: " . $filename . "\n";
push(@all_files, $filename);

if( 0 != system($cmd) ) {
    print "Error: Failed while running the following command:\n";
    print "\t$cmd\n";
    exit -1;
}


$filename = "tmp/" . $year . "-triggers.sql";
$cmd = "../summary/create-partition-triggers.pl " . $year . " XX > " . $filename;
print "\tCreating file: " . $filename . "\n";
push(@all_files, $filename);

if( 0 != system($cmd) ) {
    print "Error: Failed while running the following command:\n";
    print "\t$cmd\n";
    exit -1;
}

#
# Tell the user how to update the DB
#
print "\n";
print "-"x70 . "\n";
print "Now you are ready to insert these into the database\n";
print "\n";
print "Check the database to make sure that the tables have not\n";
print "already been added for that year\n";
print "  psql ".$database_name." -U ".$database_user."\n";
print "  ".$database_name."=> \\dt\n";
print "  ".$database_name."=> \\di\n";
print "\n";
print "When you are ready run the following commands: \n";
print " (afterward you can delete the tmp directory)\n";
print "-"x70 . "\n";
foreach $filename (@all_files) {
    print "psql ".$database_name." -U ".$database_user." -f ".$filename. "\n"
}

exit 0;

# psql mtt -U mtt -f 2014-mpi-install.sql
# psql mtt -U mtt -f 2014-test-build.sql
# psql mtt -U mtt -f 2014-test-run.sql
# psql mtt -U mtt -f 2014-indexes.sql
# psql mtt -U mtt -f 2014-triggers.sql
