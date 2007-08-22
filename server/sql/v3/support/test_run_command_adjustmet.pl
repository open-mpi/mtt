#!/usr/bin/env perl

#
# Josh Hursey
# Note:
#  This script generates a SQL script that will remove the test_run_command
#  foreign key from the test_run partition tables. It is to be used as a
#  tool to help updating table structure when the update to the table is
#  significant enough to warrent the following method:
#   1) Drop all foreign keys referencing table X
#   2) Drop table X, Replace with a new version
#   3) Update all the partition table keys to point to a valid id (usually 0)
#   4) Add back the foreign key constraint referencing table X
#
use strict;

my $argc = scalar(@ARGV);

my $year;
my $month;
my $cur_wk;

my $child_table_base = "test_run_";

# 0 == Drop
# 1 == Add
my $a_or_d = 1;

my @month_array = ( "01", "02", "03", "04", "05", "06",
                    "07", "08", "09", "10", "11", "12");

if ( $argc < 2 ) {
  print "Error: Argument of year and month required\n";
  print "Usage: ./create-partitions YYYY MM\n";
  exit -1;
}

$year  = $ARGV[0];
$month = $ARGV[1];

if ( $year !~ /^\d{4}$/ ||
     $year < 2006 || $year > 2020) {
  print "Invalid year: <$year> Format YYYY, Range 2006 to 2020\n";
  exit -2;
}

if ( $month ne "XX" ) {
  if ( $month !~ /^\d{2}$/ ||
       $month < 1 || $month > 12) {
    print "Invalid month: <$month>. Format MM, Range 01 to 12\n";
    exit -2;
  } else {
    @month_array = ();
    push(@month_array, $month);
  }
}

if( 0 == $a_or_d ) {
  print "--\n";
  print "-- Drop old Foreign Keys\n";
  print "--\n";
  foreach $month (@month_array) {
    for($cur_wk = 1; $cur_wk <= 5; ++$cur_wk) {
      print ("ALTER TABLE ".$child_table_base."y" . $year . "_m" . $month . "_wk" . $cur_wk ." " .
             " DROP CONSTRAINT " .
             " ".$child_table_base."y" . $year . "_m" . $month . "_wk" . $cur_wk ."_test_run_command_id_fkey;\n");
    }
  }
} else {
  print "--\n";
  print "-- Add Foreign Keys\n";
  print "--\n";
  foreach $month (@month_array) {
    for($cur_wk = 1; $cur_wk <= 5; ++$cur_wk) {
      print ("ALTER TABLE ".$child_table_base."y" . $year . "_m" . $month . "_wk" . $cur_wk ." " .
             " ADD FOREIGN KEY (test_run_command_id) REFERENCES test_run_command(test_run_command_id);\n");
    }
  }
}

exit 0;
