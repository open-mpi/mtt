#!/usr/bin/env perl

#
# Josh Hursey
#
use strict;
use DBI;

my $argc = scalar(@ARGV);

my $year;
my $month;

my @month_array = ( "01", "02", "03", "04", "05", "06",
                    "07", "08", "09", "10", "11", "12");

my @year_array = (2006, 2007);

my $mtt_user = "mtt";
my $dbh_mtt = DBI->connect("dbi:Pg:dbname=mtt",  $mtt_user);
my $stmt;

#my $vacuum_type = "VACUUM FULL";
my $vacuum_type = "VACUUM";

$stmt = $dbh_mtt->prepare("set vacuum_mem = ".(32 * 1024));
$stmt->execute();
$stmt->finish;

foreach $year (@year_array) {
  my @cur_month_array = ();
  if( $year == 2006 ) {
    push(@cur_month_array, 11);
    push(@cur_month_array, 12);
  }
  else {
    @cur_month_array = @month_array;
  }

  foreach $month (@cur_month_array) {
    my $cur_wk = 0;
    for($cur_wk = 1; $cur_wk <= 5; ++$cur_wk) {
      my $post_fix = "y" . $year . "_m" . $month . "_wk" . $cur_wk;
      print("Looking at $post_fix...\n");
      $stmt = $dbh_mtt->prepare($vacuum_type." mpi_install_".$post_fix);
      $stmt->execute();
      $stmt->finish;

      $stmt = $dbh_mtt->prepare($vacuum_type." test_build_".$post_fix);
      $stmt->execute();
      $stmt->finish;

      $stmt = $dbh_mtt->prepare($vacuum_type." test_run_".$post_fix);
      $stmt->execute();
      $stmt->finish;
    }
  }
}

print("Finally Analyze...\n");
$stmt = $dbh_mtt->prepare("ANALYZE");
$stmt->execute();
$stmt->finish;

$dbh_mtt->disconnect;

exit 0;
