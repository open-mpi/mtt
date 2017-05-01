#!/usr/bin/env perl

# Josh Hursey
#
# A script to extract some general contribution stats for graphing
#

use strict;
use DBI;
use Class::Struct;
use Config::IniFiles;

# Flush I/O frequently
$| = 1;

my $config_filename = "../config.ini";
my $ini_section;

my $v_nlt = "\n\t";
my $v_nl  = "\n";
my $verbose = 0;

my $is_day   = "f";
my $is_week  = "f";
my $is_month = "t";
my $is_year  = "f";
my $is_limited_to_one_year = "f";
my $dbh_mtt;


#
# Parse any command line arguments
#
if( 0 != parse_cmd_line() ) {
  print_usage();
  exit -1;
}

my $ini = new Config::IniFiles(-file => $config_filename,
                               -nocase => 1,
                               -allowcontinue => 1);
if( !$ini ) {
    print "Error: Failed to read: $config_filename\n";
    exit 1;
}
# Check the contents of the config file
check_ini_section($ini, "database", ("user", "password", "hostname", "port", "dbname") );

# Read in config entries
$ini_section = "database";
my $mtt_user = resolve_value($ini, $ini_section, "user");;
my $mtt_pass = resolve_value($ini, $ini_section, "password");
my $mtt_hostname = resolve_value($ini, $ini_section, "hostname");
my $mtt_port = resolve_value($ini, $ini_section, "port");
my $mtt_dbname = resolve_value($ini, $ini_section, "dbname");


#
# Setup queries
#
my $sql_select_base =
  "  sum(num_mpi_install_pass + num_mpi_install_fail + ".$v_nl.
  "      num_test_build_pass  + num_test_build_fail  + ".$v_nl.
  "      num_test_run_pass    + num_test_run_fail    + num_test_run_timed + num_test_run_perf) as total, ".$v_nl.
  "  sum(num_mpi_install_pass + num_mpi_install_fail) as mpi_install, ".$v_nl.
  "  sum(num_test_build_pass + num_test_build_fail) as test_build, ".$v_nl.
  "  sum(num_test_run_pass + num_test_run_fail + num_test_run_timed) as test_run, ".$v_nl.
  "  sum(num_test_run_perf) as perf ".$v_nl.
  "FROM mtt_stats_contrib ".$v_nl.
  "WHERE is_day = 't' ";
my $sql_select_group_by =
  "GROUP BY foo_date ".$v_nl.
  "ORDER BY foo_date ";

my $sql_select_all_day   = ("SELECT to_date( date_trunc('day',   collection_date)::text, 'YYYY-MM-DD') as foo_date, " .$v_nl.
                            $sql_select_base . $v_nl.
                            " AND date_trunc('day', collection_date) < date_trunc('day', now()) ".$v_nl);
if( $is_limited_to_one_year eq "t" ) {
    $sql_select_all_day .= (" AND date_trunc('day', collection_date) >= date_trunc('day', now() - interval '1 year') ".$v_nl);
}
$sql_select_all_day     .= ($sql_select_group_by);

my $sql_select_all_week  = ("SELECT to_date( date_trunc('week',  collection_date)::text, 'YYYY-MM-DD') as foo_date, " .$v_nl.
                            $sql_select_base . $v_nl.
                            " AND date_trunc('week', collection_date) < date_trunc('week', now()) ".$v_nl);
if( $is_limited_to_one_year eq "t" ) {
    $sql_select_all_week .= (" AND date_trunc('week', collection_date) >= date_trunc('week', now() - interval '1 year') ".$v_nl);
}
$sql_select_all_week     .= ($sql_select_group_by);

my $sql_select_all_month = ("SELECT to_date( date_trunc('month', collection_date)::text, 'YYYY-MM-DD') as foo_date, " .$v_nl.
                            $sql_select_base . $v_nl.
                            " AND date_trunc('month', collection_date) < date_trunc('month', now()) ".$v_nl);
if( $is_limited_to_one_year eq "t" ) {
    $sql_select_all_month .= (" AND date_trunc('month', collection_date) >= date_trunc('month', now() - interval '1 year') ".$v_nl);
}
$sql_select_all_month     .= ($sql_select_group_by);

my $sql_select_all_year  = ("SELECT to_date( date_trunc('year',  collection_date)::text, 'YYYY-MM-DD') as foo_date, " .$v_nl.
                            $sql_select_base . $v_nl.
                            " AND date_trunc('year', collection_date) <= date_trunc('year', now()) ".$v_nl);
if( $is_limited_to_one_year eq "t" ) {
    $sql_select_all_year .= (" AND date_trunc('year', collection_date) >= date_trunc('year', now() - interval '1 year') ".$v_nl);
}
$sql_select_all_year     .= ($sql_select_group_by);


#
# Process option
#
if( $is_day   eq "t" ) {
  dump_data($sql_select_all_day);
}
elsif( $is_week eq "t" ) {
  dump_data($sql_select_all_week);
}
elsif( $is_month eq "t" ) {
  dump_data($sql_select_all_month);
}
else {
  dump_data($sql_select_all_year);
}

exit 0;

sub parse_cmd_line() {
  my $i = -1;
  my $argc = scalar(@ARGV);
  my $exit_value = 0;

  for($i = 0; $i < $argc; ++$i) {
    #
    # Gather Results for a single day
    #
    if( $ARGV[$i] eq "-day" ) {
      $is_day   = "t";
      $is_week  = "f";
      $is_month = "f";
      $is_year  = "f";
    }
    #
    # Gather Results by calendar week
    #
    elsif( $ARGV[$i] eq "-week" ) {
      $is_day   = "f";
      $is_week  = "t";
      $is_month = "f";
      $is_year  = "f";
    }
    #
    # Gather Results for a month
    #
    elsif( $ARGV[$i] eq "-month" ) {
      $is_day   = "f";
      $is_week  = "f";
      $is_month = "t";
      $is_year  = "f";
    }
    #
    # Gather Results for a year
    #
    elsif( $ARGV[$i] eq "-year" ) {
      $is_day   = "f";
      $is_week  = "f";
      $is_month = "f";
      $is_year  = "t";
    }
    elsif( $ARGV[$i] eq "-h" ) {
      $exit_value = -1;
    }
    #
    # Verbose level
    #
    elsif( $ARGV[$i] eq "-v" ) {
      ++$i;
      $verbose = $ARGV[$i];
    }
    elsif( $ARGV[$i] eq "-l" ) {
      $is_limited_to_one_year = "t";
    }
    #
    # Config file to use
    #
    elsif( $ARGV[$i] =~ /-config/ ) {
      $i++;
      if( $i < $argc ) {
        $config_filename = $ARGV[$i];
      } else {
        print_update("Error: -config requires a file argument\n");
        return -1;
      }
    }
    #
    # Invalid options produce a usage message
    #
    else {
      print "ERROR: Unknown argument [".$ARGV[$i]."]\n";
      $exit_value = -1;
    }
  }

  #
  # Process the command line arguments
  #
  if( 0 == $exit_value ) {
    ;
  }

  return $exit_value;
}

sub print_usage() {
  print "="x50 . "\n";
  print "Usage: ./make_raw_data.pl [-day] [-month] [-year] [-v LEVEL] [-h] [-l]\n";
  print "  Default: -month -v 0\n";
  print "="x50 . "\n";

  return 0;
}

sub connect_db() {
  my $stmt;

  # Connect to the DB
  $dbh_mtt = DBI->connect("dbi:Pg:dbname=".$mtt_dbname.";host=".$mtt_hostname.";port=".$mtt_port,  $mtt_user, $mtt_pass);

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

  if( $verbose > 0 ) {
    print($sql_select . "\n");
  }

  connect_db();

  $stmt = $dbh_mtt->prepare($sql_select);
  $stmt->execute();

  while($row_ref = $stmt->fetchrow_arrayref ) {
    print($row_ref->[$stmt->{NAME_lc_hash}{foo_date}] . "\t" .
          $row_ref->[$stmt->{NAME_lc_hash}{total}] . "\t" .
          $row_ref->[$stmt->{NAME_lc_hash}{mpi_install}] . "\t" .
          $row_ref->[$stmt->{NAME_lc_hash}{test_build}] . "\t" .
          $row_ref->[$stmt->{NAME_lc_hash}{test_run}] . "\t" .
          $row_ref->[$stmt->{NAME_lc_hash}{perf}] . "\n");
  }

  disconnect_db();
}

sub resolve_value() {
    my $ini = shift(@_);
    my $section = shift(@_);
    my $key = shift(@_);
    my $value;
    
    $value = $ini->val($section, $key);
    if( !defined($value) ) {
        print "Error: Failed to find \"$key\" in section \"$section\"\n";
        exit 1;
    }
    $value =~ s/^\"//;
    $value =~ s/\"$//;

    if( $value =~ /^run/ ) {
        $value = $';
        $value =~ s/^\(//;
        $value =~ s/\)$//;
        $value = `$value`;
        chomp($value);
    }

    return $value;
}

sub check_ini_section() {
    my $ini = shift(@_);
    my $section = shift(@_);
    my @keys = @_;

    if( !$ini->SectionExists($section) ) {
        print "Error: INI file does not contain a $section field\n";
        exit 1;
    }

    foreach my $key (@keys) {
        if( !$ini->exists($section, $key) ) {
            print "Error: INI file missing $section key named $key\n";
            exit 1;
        }
    }

    return 0;
}
