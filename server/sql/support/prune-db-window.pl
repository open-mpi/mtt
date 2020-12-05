#!/usr/bin/env perl

#
# Josh Hursey
#
# Usage:
#  ./prune-db-window.pl 18
#
# May want to watch:
#  SELECT pg_size_pretty(pg_database_size('mtt')), pg_database_size('mtt');
#  SELECT collection_date, size_db, pg_size_pretty(size_db) from mtt_stats_database;
#
use strict;
use DBI;
use Class::Struct;
use Config::IniFiles;
use DateTime;

# Flush I/O frequently
$| = 1;

my $dbh_mtt;

my $argc = scalar(@ARGV);
my $sql;

# Change to '0' for a trial run
my $drop_table = 1;

my $exclude_before_year = 2014;

# Update to the location of the config file for your MTT server
my $config_filename = "server-php-cron-config.ini";
my $mtt_dbname   = "";
my $mtt_hostname = "";
my $mtt_port     = "";
my $mtt_user     = "";
my $mtt_pass     = "";


if ( $argc < 1 ) {
  print "Error: Number of months to keep required\n";
  print "Usage: ./prune-db-window.pl N\n";
  exit -1;
}

my $num_months = $ARGV[0];
if ( $num_months !~ /^\d+$/ ||
     $num_months < 1 ) {
  print "Invalid number of months: <$num_months> Must be a positive integer greater than 0";
  exit -2;
}

my $cur_dt = DateTime->today();
my $last_dt = DateTime->today()->subtract( months => $num_months+1 );

my $ini = new Config::IniFiles(-file => $config_filename,
                               -nocase => 1,
                               -allowcontinue => 1);
if( !$ini ) {
    print "Error: Failed to read: $config_filename\n";
    exit 1;
}

$mtt_dbname   = clean_ini($ini->val("database", "dbname"));
$mtt_hostname = clean_ini($ini->val("database", "hostname"));
$mtt_port     = clean_ini($ini->val("database", "port"));
$mtt_user     = clean_ini($ini->val("database", "user"));
$mtt_pass     = clean_ini($ini->val("database", "password"));

if( !defined($mtt_dbname) ||
    !defined($mtt_hostname) ||
    !defined($mtt_port) ||
    !defined($mtt_user) ||
    !defined($mtt_pass) ) {
    print "Error: Config file deoes not contain the necessary keys: $config_filename\n";
    exit 1;
}

#
# Connect to the DB
#
connect_db();

#
#
#
my $db_before = get_db_size($mtt_dbname);
my @base_names = ("mpi_install", "test_build", "test_run");
my $total_saved = 0;
for my $base_name (@base_names) {
    my @all_tables = extract_table_names($base_name);
    my $tmp_saved = 0;

    printf("-- \n");
    printf("-- Base Table: %s\n", $base_name);
    for my $table (@all_tables) {
        my $tbl_month = 0;
        my $tbl_year  = 0;
        if( $table =~ /y(\d+)_m(\d+)/ ) {
            $tbl_year = $1;
            $tbl_month = $2;
        }
        else {
            next;
        }

        # Some old tables we just need to keep
        if( $tbl_year <= $exclude_before_year ) {
            next;
        }

        my $tbl_dt = DateTime->new(year => $tbl_year, month => $tbl_month);
        # Skip tables that are too 'new'
        if ( 0 != dt_is_less_than($tbl_dt, $last_dt) ) {
            next;
        }

        my $tbl_size = extract_table_size($table);
        $tmp_saved += $tbl_size;
        
        printf("-- Remove Table : %s %20d Bytes (%s)\n", $table, $tbl_size, bytes_to_human($tbl_size) );
        if( 1 == $drop_table  ) {
            run_sql_cmd("DROP TABLE ".$table." CASCADE;");
        } else {
            print("DROP TABLE ".$table." CASCADE;\n");
        }
    }
    $total_saved += $tmp_saved;
    printf("-- Total Size Reduced by : %20d Bytes (%s)\n", $tmp_saved, bytes_to_human($tmp_saved));
}

my $db_after = get_db_size($mtt_dbname);

printf("-- \n");
printf("-- Summary:\n");
printf("-- \t Keep Start : %4d-%02d\n", $cur_dt->year, $cur_dt->month);
printf("-- \t Kepp End   : %4d-%02d\n", $last_dt->year, $last_dt->month);
printf("-- \t Keep Months: %4d\n", $num_months);
printf("-- \t DB Size Before        : %20d Bytes (%s)\n", $db_before, bytes_to_human($db_before));
printf("-- \t Total Size Reduced by : %20d Bytes (%s)\n", $total_saved, bytes_to_human($total_saved));
printf("-- \t DB Size After         : %20d Bytes (%s)\n", $db_after, bytes_to_human($db_after));
printf("-- \n");

#
# Disconnect from the DB
#
disconnect_db();

exit 0;

sub connect_db() {
  my $stmt;

  # Connect to the DB
  $dbh_mtt = DBI->connect("dbi:Pg:dbname=".$mtt_dbname.";host=".$mtt_hostname.";port=".$mtt_port, $mtt_user, $mtt_pass);

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

sub get_db_size() {
  my $db = shift(@_);
  my $sql_query;
  my $stmt;
  my $db_size = -1;
  my $row_ref;

  $sql_query = "SELECT pg_database_size('$db');";
  $stmt = $dbh_mtt->prepare($sql_query);
  $stmt->execute();

  while($row_ref = $stmt->fetchrow_arrayref ) {
      $db_size        = $row_ref->[$stmt->{NAME_lc_hash}{pg_database_size}];
  }

  return $db_size;
}

sub display_db_size() {
  my $db = shift(@_);
  my $sql_query;
  my $stmt;
  my $db_size_pretty = -1;
  my $db_size = -1;
  my $row_ref;

  $sql_query = "SELECT pg_size_pretty(pg_database_size('$db')), pg_database_size('$db');";
  $stmt = $dbh_mtt->prepare($sql_query);
  $stmt->execute();

  while($row_ref = $stmt->fetchrow_arrayref ) {
      $db_size_pretty = $row_ref->[$stmt->{NAME_lc_hash}{pg_size_pretty}];
      $db_size        = $row_ref->[$stmt->{NAME_lc_hash}{pg_database_size}];
  }

  printf("-- \t Current DB Size (%s) : %20d Bytes (%s)\n", $db, $db_size, $db_size_pretty);
  
  return $db_size;
}

sub extract_table_names() {
  my $table_prefix = shift(@_);
  my $sql_query;
  my $stmt;
  my $table_size = -1;
  my $row_ref;
  my @all_tables = ();

  $sql_query  = "SELECT tablename FROM pg_catalog.pg_tables WHERE tableowner = 'mtt' AND ";
  $sql_query .= "tablename ~ '^" . $table_prefix . "_y' order by tablename;";
  $stmt = $dbh_mtt->prepare($sql_query);
  $stmt->execute();

  while($row_ref = $stmt->fetchrow_arrayref ) {
      push(@all_tables, $row_ref->[$stmt->{NAME_lc_hash}{tablename}]);
  }

  return @all_tables;
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

sub clean_ini() {
    my $value = shift(@_);
    $value =~ s/^\"//;
    $value =~ s/\"$//;
    return $value;
}

sub dt_is_less_than() {
    my $dt_cmp = shift(@_);
    my $dt_end = shift(@_);
    my $value_cmp = $dt_cmp->year * 100 + $dt_cmp->month;
    my $end_cmp = $dt_end->year * 100 + $dt_end->month;

    if( $value_cmp < $end_cmp ) {
        return 0;
    }
    return 1;
}
