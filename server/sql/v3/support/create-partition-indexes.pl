#!/usr/bin/env perl

#
# Josh Hursey
# Note:
#  This script will generate indexes for the partition tables since they are
#  *not* inherited.
#
use strict;

my $argc = scalar(@ARGV);

my $year;
my $month;
my $cur_wk;

my $child_table_base;
my $idx_column;
my $sig;

my @mpi_install_idx_columns = ("test_result");

my @test_build_idx_columns = ("test_result",
                              "test_suite_id");

my @test_run_idx_columns = ("test_result",
                            "test_suite_id",
                            "test_name_id",
                            "performance_id",
                            "test_run_command_id");

my @month_array = ( "01", "02", "03", "04", "05", "06",
                    "07", "09", "10", "11", "12");
# JJH don't generate Aug indexes since we still need to dump data here and 
#     indexes just slow down this process considerably
#                    "07", "08", "09", "10", "11", "12");

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

#######################
# MPI Install
#######################
$child_table_base = "mpi_install_";

print "\n\n";
print "-"x50 ."\n";
print "-- Create Partiion table indexes for MPI Install\n";
print "-"x50 ."\n";

foreach $idx_column (@mpi_install_idx_columns) {
  print "\n";
  print "--\n";
  print "-- Create Index on $idx_column for MPI Install Partition tables\n";
  print "--\n";

  foreach $month (@month_array) {
    for($cur_wk = 1; $cur_wk <= 5; ++$cur_wk) {
      $sig = $child_table_base."y" . $year . "_m" . $month . "_wk" . $cur_wk;

      print ("DROP   INDEX idx_".$sig."_".$idx_column.";\n");
      print ("CREATE INDEX idx_".$sig."_".$idx_column." ON ".$sig." (".$idx_column.");\n");
    }
  }
}

#######################
# Test Build
#######################
$child_table_base = "test_build_";

print "\n\n";
print "-"x50 ."\n";
print "-- Create Partiion table indexes for Test Build\n";
print "-"x50 ."\n";

foreach $idx_column (@test_build_idx_columns) {
  print "\n";
  print "--\n";
  print "-- Create Index on $idx_column for Test Build Partition tables\n";
  print "--\n";

  foreach $month (@month_array) {
    for($cur_wk = 1; $cur_wk <= 5; ++$cur_wk) {
      $sig = $child_table_base."y" . $year . "_m" . $month . "_wk" . $cur_wk;

      print ("DROP   INDEX idx_".$sig."_".$idx_column.";\n");
      print ("CREATE INDEX idx_".$sig."_".$idx_column." ON ".$sig." (".$idx_column.");\n");
    }
  }
}

#######################
# Test Run
#######################
$child_table_base = "test_run_";

print "\n\n";
print "-"x50 ."\n";
print "-- Create Partiion table indexes for Test Run\n";
print "-"x50 ."\n";

foreach $idx_column (@test_run_idx_columns) {
  print "\n";
  print "--\n";
  print "-- Create Index on $idx_column for Test Run Partition tables\n";
  print "--\n";

  foreach $month (@month_array) {
    for($cur_wk = 1; $cur_wk <= 5; ++$cur_wk) {
      $sig = $child_table_base."y" . $year . "_m" . $month . "_wk" . $cur_wk;

      print ("DROP   INDEX idx_".$sig."_".$idx_column.";\n");
      print ("CREATE INDEX idx_".$sig."_".$idx_column." ON ".$sig." (".$idx_column.");\n");
    }
  }
}

exit;
