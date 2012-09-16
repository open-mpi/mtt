#!/usr/bin/env perl

#
# Josh Hursey
# Note:
#  For each relation found for the date ranges provided this script:
#    - Display the 'size' of that table in bytes
#    - Archives the table to disk
#    - Removes the table from the database
#
# Usage:
#  archive-paritions.pl 2006 11 | tee output-archive-2006.txt
#  archive-paritions.pl 2007 XX | tee output-archive-2006.txt
#
# May want to watch:
#  SELECT pg_size_pretty(pg_database_size('mtt')), pg_database_size('mtt');
#  SELECT collection_date, size_db, pg_size_pretty(size_db) from mtt_stats_database;
#
use strict;
use DBI;
use Class::Struct;

# Flush I/O frequently
$| = 1;


my $dbh_mtt;

my $argc = scalar(@ARGV);
my $sql;

my $year;
my $month;

my @table_cat = ("mpi_install", "test_build", "test_run");
my $parent_table = "mpi_install";
my $child_table;
my $child_table_base = "mpi_install_";

my $child_table_size;
my $total_size = 0;
my $archive_filename;

my $monthly_archive_file_list;
my $monthly_archive_file;

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

#
# Display date
#
my $date_str_start;
my $date_str_end;

$date_str_start = `date`;
chomp($date_str_start);
print "--\n";
print "-- Start: $date_str_start\n";
print "--\n";

#
# Connect to the DB
#
connect_db();

#
# For each type of table
#
foreach $parent_table (@table_cat) {
  $child_table_base = $parent_table . "_";

  #
  # For each month in the year
  #
  foreach $month (@month_array) {
    my $monthly_archive_file = "archive-of-".$child_table_base."y" . $year . "_m" . $month . ".tar.gz";
    my $monthly_archive_file_list = "";

    #
    # For each week in the month (5 weeks)
    #
    my $cur_wk = 0;
    for($cur_wk = 1; $cur_wk <= 5; ++$cur_wk) {
      #
      # Display the table being investigated
      #
      $child_table = $child_table_base."y" . $year . "_m" . $month . "_wk" . $cur_wk;
      print "-- \n";
      print "-- Archiving Table: $child_table\n";

      #
      # Display the number of bytes taken up by this table
      #
      $child_table_size = extract_table_size($child_table);
      if( $child_table_size < 0 ) {
        print "Error: Table size returned was ($child_table_size)!\n";
        exit(-1);
      }
      $total_size += $child_table_size;
      printf("-- Table size     : %20d Bytes (%s)\n", $child_table_size, bytes_to_human($child_table_size) );

      #
      # Store the relation to the archive folder
      #
      $archive_filename = archive_table($child_table);
      $monthly_archive_file_list = $monthly_archive_file_list . " " . $archive_filename;
      print "-- Table archive  : $archive_filename\n";

      #
      # Remove the partition table
      #
      run_sql_cmd("DROP TABLE ".$child_table." CASCADE;");
      print "-- Table dropped!\n";

      #
      # Remove the rules -- Cascade will cover this
      #
      #$sql = "DELTE RULE ".$child_table."_insert";

      #
      # Remove the indexes -- Cascade will cover this too
      #
      #$sql = "DELETE INDEX ".$child_table."_st";

      print "-- \n";
    }

    #
    # Compress the month
    #
    compress_archive($monthly_archive_file, $monthly_archive_file_list);
  }
}

#
# Disconnect from the DB
#
disconnect_db();

$date_str_end = `date`;
chomp($date_str_end);

printf("-- \n");
printf("-- Summary:\n");
printf("-- \t Start: %s\n", $date_str_start);
printf("-- \t End  : %s\n", $date_str_end);
printf("-- \t Total Size Reduced by : %20d Bytes (%s)\n", $total_size, bytes_to_human($total_size));
printf("-- \n");

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

sub extract_table_size() {
  my $table = shift(@_);
  my $sql_query;
  my $stmt;
  my $table_size = -1;
  my $row_ref;

  $sql_query = "select pg_relation_size('$table');";
  $stmt = $dbh_mtt->prepare($sql_query);
  $stmt->execute();

  while($row_ref = $stmt->fetchrow_arrayref ) {
    $table_size = $row_ref->[$stmt->{NAME_lc_hash}{pg_relation_size}];
  }

  return $table_size;
}

sub run_sql_cmd() {
  my $sql_cmd = shift(@_);
  my $stmt;

  $stmt = $dbh_mtt->prepare($sql_cmd);
  return $stmt->execute();
}

sub archive_table() {
  my $table = shift(@_);
  my $filename;
  my $cmd;

  $filename = "archive-$year-$table.data";
  $cmd = "pg_dump mtt -U mtt -t $table -f $filename";
  system($cmd);

  return $filename;
}

sub bytes_to_human() {
  my $num_bytes = shift(@_);

  if( $num_bytes < 1024 ) {
    return $num_bytes ." B";
  }
  elsif( $num_bytes < (1024*1024) ) {
    return ($num_bytes / 1024) . " KB";
  }
  elsif( $num_bytes < (1024*1024*1024) ) {
    return ($num_bytes / (1024*1024)) . " MB";
  }
  elsif( $num_bytes < (1024*1024*1024*1024) ) {
    return ($num_bytes / (1024*1024*1024)) . " GB";
  }

  return "Unknown";
}

sub compress_archive() {
  my $archive_file = shift(@_);
  my $archive_file_list = shift(@_);
  my $cmd;

  $cmd = "tar -zcf $archive_file $archive_file_list";
  system($cmd);

  $cmd = "rm $archive_file_list";
  system($cmd);
}
