#!/usr/bin/env perl

#
# Josh Hursey
#
# Daily:
#   VACUUM  - Current Month, Last Month (no args)
#   ANALYZE - Entire Database (no args)
# Weekly:
#   VACUUM  - Current Month, Last Month, Base Tables (no args)
#   ANALYZE - Entire Database (no args)
# Monthly:
#   VACUUM  - Current Month, Last Month, Base Tables (FULL)
#   ANALYZE - Entire Database (no args)
# Yearly:
#   VACUUM  - Entire Database (FULL)
#   ANALYZE - Entire Database (no args)
#   - Email partition tables reminder (JJH TODO)
#
use strict;
use DBI;

my $debug;

my $MAIN_DAY   = 0;
my $MAIN_WEEK  = 1;
my $MAIN_MONTH = 2;
my $MAIN_YEAR  = 3;

my $cur_main = $MAIN_DAY;
my $cur_year  = `date +\%Y`;
my $cur_month = `date +\%m`;
chomp($cur_year);
chomp($cur_month);

my $dbh_mtt;

my $epoch_year = "2006";
my @epoch_months = ("11", "12");

my @week_array = ( "1", "2", "3", "4", "5");
my @part_table_postfix = ();

my @main_part_tables = ("mpi_install",
                        "test_build",
                        "test_run");
my @main_base_tables = ("compiler",
                        "compute_cluster",
                        "description",
                        "environment",
                        "interconnects",
                        "latency_bandwidth",
                        "mpi_get",
                        "performance",
                        "permalinks",
                        "result_message",
                        "submit",
                        "test_names",
                        "test_suites",
                        "test_run_command",
                        "test_run_networks",
                        "mtt_stats_contrib",
                        "mtt_stats_database");

#
# Parse Command Line Arguments
#
if( 0 != parse_args() ) {
  exit -1;
}

set_date_ranges();

#
# VACUUM database
#
if( 0 != do_vacuum() ) {
  exit -1;
}

#
# ANALYZE database
#
if( 0 != do_analyze() ) {
  exit -1;
}

exit 0;

sub parse_args() {
  my $argc = scalar(@ARGV);
  my $i;

  for( $i = 0; $i < $argc; ++$i) {
    if( $ARGV[$i] =~ /-daily/ ||
        $ARGV[$i] =~ /-day/ ) {
      $cur_main = $MAIN_DAY;
    }
    elsif( $ARGV[$i] =~ /-week/ ) {
      $cur_main = $MAIN_WEEK;
    }
    elsif( $ARGV[$i] =~ /-month/ ) {
      $cur_main = $MAIN_MONTH;
    }
    elsif( $ARGV[$i] =~ /-year/ ) {
      $cur_main = $MAIN_YEAR;
    }
    else {
      print "Unknown ARG $i) <".$ARGV[$i].">\n";
    }
  }

  return 0;
}

sub set_date_ranges() {
  my ($y, $m);

  if( defined($debug) ) {
    print "Current Year/Month: <$cur_year> <$cur_month>\n";
  }

  # Daily:   Current Month, Last Month
  # Weekly:  Current Month, Last Month
  # Monthly: Current Month, Last Month
  if( $MAIN_DAY   == $cur_main ||
      $MAIN_WEEK  == $cur_main ||
      $MAIN_MONTH == $cur_main ) {
    if( ($cur_month + 0) == 1 ) {
      push(@part_table_postfix, get_part_table_postfix($cur_year-1, "12"));
    } else {
      push(@part_table_postfix, get_part_table_postfix($cur_year,   $cur_month - 1));
    }
    push(@part_table_postfix, get_part_table_postfix($cur_year,   $cur_month));
  }
  # Yearly: All Months
  elsif( $MAIN_YEAR == $cur_main ) {
    my @year_array = ($epoch_year);
    # Extend the year array
    for( $y = $year_array[0] + 1; $y <= $cur_year; ++$y) {
      push(@year_array, $y);
    }
    foreach $y (@year_array) {
      my @cur_month_array = ();
      @cur_month_array = get_month_set($y);
      foreach $m (@cur_month_array) {
        push(@part_table_postfix, get_part_table_postfix($y, $m));
      }
    }

  }

  return 0;
}

sub do_vacuum() {
  my $vac_cmd = "VACUUM";

  if(    $MAIN_DAY   == $cur_main ) { $vac_cmd = "VACUUM"; }
  elsif( $MAIN_WEEK  == $cur_main ) { $vac_cmd = "VACUUM"; }
  elsif( $MAIN_MONTH == $cur_main ) { $vac_cmd = "VACUUM FULL"; }
  elsif( $MAIN_YEAR  == $cur_main ) { $vac_cmd = "VACUUM FULL"; }

  connect_db();

  # Process the partition tables (does not include master partition tables)
  forall_part_tables($vac_cmd);

  # Process the base tables (include master partition tables)
  if( $MAIN_DAY   != $cur_main ) {
    forall_base_tables($vac_cmd);
  }

  disconnect_db();

  return 0;
}

sub do_analyze() {
  my $stmt;

  if( defined($debug) ) {
    return 0;
  }

  connect_db();

  print("Analyze...\n");
  $stmt = $dbh_mtt->prepare("ANALYZE");
  $stmt->execute();
  $stmt->finish;

  disconnect_db();

  return 0;
}

sub connect_db() {
  my $mtt_user = "mtt";
  my $stmt;

  if( defined($debug) ) {
    return 0;
  }

  $dbh_mtt = DBI->connect("dbi:Pg:dbname=mtt",  $mtt_user);

  $stmt = $dbh_mtt->prepare("set vacuum_mem = ".(32 * 1024));
  $stmt->execute();
  $stmt->finish;

  return 0;
}

sub disconnect_db() {
  if( defined($debug) ) {
    return 0;
  }

  $dbh_mtt->disconnect;

  return 0;
}

sub forall_part_tables() {
  my $base_cmd = shift(@_);
  my $cmd;
  my $stmt;
  my $week;
  my $p;
  my $base_table;

  foreach $base_table (@main_part_tables) {
    foreach $p (@part_table_postfix) {
      foreach $week (@week_array) {
        my $post_fix = get_part_table_postfix_append_week($p, $week);
        if( defined($debug) ) {
          print("Processing Command <".$base_cmd." ".$base_table."_".$post_fix.">\n");
        } else {
          print($base_cmd."'ing table ".$base_table."_".$p."\n");
          $stmt = $dbh_mtt->prepare($base_cmd." ".$base_table."_".$post_fix);
          $stmt->execute();
          $stmt->finish;
        }
      }
    }
  }

  return 0;
}

sub forall_base_tables() {
  my $base_cmd = shift(@_);
  my $cmd;
  my $stmt;
  my $base_table;
  my @all_tables = ();

  push(@all_tables, @main_part_tables);
  push(@all_tables, @main_base_tables);

  foreach $base_table (@all_tables) {
    if( defined($debug) ) {
      print("Processing Command <".$base_cmd." ".$base_table.">\n");
    } else {
      print($base_cmd."'ing table ".$base_table."\n");
      $stmt = $dbh_mtt->prepare($base_cmd." ".$base_table);
      $stmt->execute();
      $stmt->finish;
    }
  }

  return 0;
}

sub get_month_set() {
  my $year = shift(@_);
  my $m;
  my @tmp_array = ();
  my @loc_month_array = ( "01", "02", "03", "04", "05", "06",
                          "07", "08", "09", "10", "11", "12");

  #
  # If epoch, only add the epoch months
  #
  if( $year == $epoch_year ) {
    foreach $m (@epoch_months) {
      push(@tmp_array, $m);
    }
  }
  #
  # If this is the current year then add only the active months
  #
  elsif( $year == $cur_year ) {
    foreach $m (@loc_month_array) {
      push(@tmp_array, $m);
      if( $m eq $cur_month ) {
        last;
      }
    }
  }
  #
  # Otherwise add all months
  #
  else {
    @tmp_array = @loc_month_array;
  }

  return @tmp_array;
}

sub get_part_table_postfix() {
  my $year = shift(@_);
  my $month = shift(@_);
  my $week  = shift(@_);

  if( ($month + 0) < 10 ) {
    $month = "0" . ($month + 0);
  }

  if( !defined($week) ) {
    return ("y".$year. "_m".$month);
  } else {
    return ("y".$year. "_m".$month."_wk".$week);
  }
}

sub get_part_table_postfix_append_week() {
  my $postfix = shift(@_);
  my $week = shift(@_);

  if( $postfix =~ /_wk$/ ) {
    return $postfix . $week;
  }
  elsif( $postfix =~ /_wk\d$/ ) {
    return $postfix;
  }
  else {
    return $postfix . "_wk" . $week;
  }
}
