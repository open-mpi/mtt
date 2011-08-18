#!/usr/bin/env perl

#
# Josh Hursey
#  This script will generate sql to attach the update trigger to each partition table.
#
use strict;

my $argc = scalar(@ARGV);

my $year;
my $month;
my $cur_wk;

my $child_table_base;
my $idx_column;
my $sig;

my $working_create;
my $working_drop;
my $template_create = "CREATE TRIGGER update_summary_table_SUB_TABLE
AFTER INSERT ON SUB_TABLE
    FOR EACH ROW EXECUTE PROCEDURE update_summary_table();
";
my $template_drop = "DROP TRIGGER update_summary_table_SUB_TABLE on SUB_TABLE;";

my @base_tables = ("mpi_install", "test_build", "test_run");

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

#######################
# Foreach basetable
#######################
my $base_table;
foreach $base_table (@base_tables) {
  $child_table_base = $base_table . "_";

  print "\n\n";
  print "-"x50 ."\n";
  print "-- Create Partiion table indexes for $base_table\n";
  print "-"x50 ."\n";

  foreach $month (@month_array) {
    for($cur_wk = 1; $cur_wk <= 5; ++$cur_wk) {
      $sig = $child_table_base."y" . $year . "_m" . $month . "_wk" . $cur_wk;

      $working_create = $template_create;
      $working_drop = $template_drop;
      $working_create =~ s/SUB_TABLE/$sig/g;
      $working_drop =~ s/SUB_TABLE/$sig/g;

      print "$working_drop\n";
      print "$working_create\n";
    }
  }
}

exit;
