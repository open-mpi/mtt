#!/usr/bin/env perl

# Josh Hursey
#
# A script to extract some general contribution stats for graphing
#

use strict;
use DBI;
use Class::Struct;

# Flush I/O frequently
$| = 1;

my $v_nlt = "\n\t";
my $v_nl  = "\n";
my $verbose = 0;

my $dbh_mtt;

my $sql_select = 
  "SELECT ".$v_nlt.
  "  collection_date as date, size_db as size, num_tuples as tuples, date(date_trunc('week',collection_date)) as week ".$v_nl.
  "FROM ".$v_nlt.
  "  mtt_stats_database ".$v_nl.
  "ORDER BY ".$v_nlt.
  "  collection_date";

dump_data($sql_select);

exit 0;


sub connect_db() {
  my $stmt;
  my $mtt_user     = "mtt";
  my $mtt_password;

  # Connect to the DB
  if( defined($mtt_password) ) {
    $dbh_mtt = DBI->connect("dbi:Pg:dbname=mtt",  $mtt_user, $mtt_password);
  }
  else {
    $dbh_mtt = DBI->connect("dbi:Pg:dbname=mtt",  $mtt_user);
  }

  # Set an optimizer flag
  $stmt = $dbh_mtt->prepare("set constraint_exclusion = on");
  $stmt->execute();

  # Set Sort Memory
  $stmt = $dbh_mtt->prepare("set sort_mem = '128MB'");
  $stmt->execute();

  return 0;
}

sub disconnect_db() {
  $dbh_mtt->disconnect;
  return 0;
}

sub dump_data($) {
  my $sql_select = shift(@_);
  my $stmt;
  my $row_ref;
  my $cur_date;
  my $date_last;
  my $size_start;
  my $size_end;
  my $size_last;
  my $tuples_start;
  my $tuples_end;
  my $tuples_last;

  if( $verbose > 0 ) {
    print($sql_select . "\n");
  }

  connect_db();

  $stmt = $dbh_mtt->prepare($sql_select);
  $stmt->execute();

  while($row_ref = $stmt->fetchrow_arrayref ) {
    if( !defined($cur_date) ) {
      $cur_date = $row_ref->[$stmt->{NAME_lc_hash}{week}];
      $size_start = int($row_ref->[$stmt->{NAME_lc_hash}{size}]);
      $tuples_start = int($row_ref->[$stmt->{NAME_lc_hash}{tuples}]);
    }

    if( ! ($cur_date eq $row_ref->[$stmt->{NAME_lc_hash}{week}]) ) {
      $size_end = $size_last;
      $tuples_end = $tuples_last;

      printf("Week: %10s \t %7d MB \t %7d K\n", $date_last,
             (($size_end - $size_start)/(1024*1024)),
             (($tuples_end - $tuples_start)/(1000)) );

      $size_start = $size_end;
      $tuples_start = $tuples_end;
      $cur_date = $row_ref->[$stmt->{NAME_lc_hash}{week}];
    }

    #print($row_ref->[$stmt->{NAME_lc_hash}{date}] . "\t(" .
    #       $row_ref->[$stmt->{NAME_lc_hash}{size}] . ")\t" .
    #       $row_ref->[$stmt->{NAME_lc_hash}{week}] . "\n");

    $size_last = int($row_ref->[$stmt->{NAME_lc_hash}{size}]);
    $tuples_last = int($row_ref->[$stmt->{NAME_lc_hash}{tuples}]);
    $date_last = $row_ref->[$stmt->{NAME_lc_hash}{week}];
  }

  $size_end = $size_last;
  $tuples_end = $tuples_last;
      printf("Week: %10s \t %7d MB \t %7d K\n", $date_last,
             (($size_end - $size_start)/(1024*1024)),
             (($tuples_end - $tuples_start)/(1000)) );

  disconnect_db();
}
