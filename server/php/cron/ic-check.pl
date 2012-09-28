#!/usr/bin/env perl

#
# Josh Hursey
#
# A few integrity checks on the database.
# Any result from these tests indicate bad data in the database
#
use strict;
use DBI;
use Mail::Sendmail;
use Class::Struct;

# Flush I/O frequently
$| = 1;

my $verbose;
my $debug;
my $debug_no_email;

#my $to_email_address     = "FILL THIS IN";
#my $from_email_address   = "FILL THIS IN";
my $to_email_address     = "mtt-devel-core\@open-mpi.org";
my $from_email_address   = "mtt-devel-core\@open-mpi.org";
my $current_mail_subject = "MTT Database Maintenance: IC Check";
my $current_mail_header  = "";
my $current_mail_body    = "";
my $current_mail_footer  = "\n\n-- MTT Development Team";

my $require_email = 0;
my $nl  = "\n";
my $nlt = "\n\t";
my $start_time = 0;
my $end_time   = 0;

my $dbh_mtt;

my $date_range_start;
my $date_range_end;
my $cur_year  = `date +\%Y`;
my $cur_month = `date +\%m`;
my $cur_day   = `date +\%d`;
chomp($cur_year);
chomp($cur_month);
chomp($cur_day);

# Set date range to limit our scope
$date_range_end = "'".$cur_year."-".$cur_month."-".$cur_day."'";
if( ($cur_month + 0) == 1 ) {
  $date_range_start = "'".($cur_year-1)."-12-01'";
} else {
  $date_range_start = "'".$cur_year."-".($cur_month-1)."-01'";
}

set_mail_header();

connect_db();

#
# Check for misfiled test_suite x test_name combos
#
check_test_names();

#
# Check for mismatched test_suite, test_name combos in test_run and test_build
#
check_test_names_mismatch();

disconnect_db();

if( $require_email != 0 ) {
  send_status_mail();
} else {
  print_update("All Checks Passed!");
  send_status_mail();
}

exit;

sub check_test_names() {
  my $select_ts_x_tn = ("SELECT count(*) ".$nl.
                        "FROM test_suites NATURAL JOIN test_names ".$nl.
                        "WHERE test_suite_id = 0 and test_name_id != 0");
  my $select_ts_undef_tb = ("SELECT count(*) ".$nl.
                            "FROM test_build ".$nl.
                            "WHERE test_suite_id = 0 and test_build_id != 0");
  my $select_ts_undef = ("SELECT count(*) ".$nl.
                        "FROM test_run ".$nl.
                        "WHERE test_suite_id = 0 and test_run_id != 0");
  my $select_tn_undef = ("SELECT count(*) ".$nl.
                         "FROM test_run ".$nl.
                         "WHERE test_name_id = 0 and test_run_id != 0");
  my $rtn;

  # Check for tests filed in the 'undef' suite
  print_verbose(1, "Checking: test_suite x test_name\n");
  $rtn = sql_scalar_stmt($select_ts_x_tn);
  if($rtn > 0 ) {
    print_begin_group();
    print_update("Check Failed: test_suite x test_name\n");
    print_update("              # Entries: $rtn\n");
    print_update_sql($select_ts_x_tn);
    print_end_group();
    $require_email = 1;
  }

  # Check for test_build entries that reference the 'undef' test_suite
  print_verbose(1, "Checking: 'undef' test_suite refs in test_build\n");
  $rtn = sql_scalar_stmt($select_ts_undef_tb);
  if($rtn > 0 ) {
    print_begin_group();
    print_update("Check Failed: 'undef' test_suite refs in test_build\n");
    print_update("              # Entries: $rtn\n");
    print_update_sql($select_ts_undef_tb);
    print_end_group();
    $require_email = 1;
  }

  # Check for test_run entries that reference the 'undef' test_suite
  print_verbose(1, "Checking: 'undef' test_suite refs in test_run\n");
  $rtn = sql_scalar_stmt($select_ts_undef);
  if($rtn > 0 ) {
    print_begin_group();
    print_update("Check Failed: 'undef' test_suite refs in test_run\n");
    print_update("              # Entries: $rtn\n");
    print_update_sql($select_ts_undef);
    print_end_group();
    $require_email = 1;
  }

  # Check for test_run entries that reference the 'undef' test_name
  print_verbose(1, "Checking: 'undef' test_name refs in test_run\n");
  $rtn = sql_scalar_stmt($select_tn_undef);
  if($rtn > 0 ) {
    print_begin_group();
    print_update("Check Failed: 'undef' test_name refs in test_run\n");
    print_update("              # Entries: $rtn\n");
    print_update_sql($select_tn_undef);
    print_end_group();
    $require_email = 1;
  }

  return 0;
}

sub check_test_names_mismatch() {
  my $select_test_run = ("SELECT count(*) ".$nl.
                         "FROM test_run JOIN test_names ON test_run.test_name_id = test_names.test_name_id ".$nl.
                         "WHERE test_names.test_suite_id != test_run.test_suite_id ".$nl.
                         "AND test_run.start_timestamp > $date_range_start AND test_run.start_timestamp < $date_range_end");
  my $select_tr_x_tb = ("SELECT count(*) ".$nl.
                        "FROM test_run JOIN test_build ON test_run.test_build_id = test_build.test_build_id ".$nl.
                        "WHERE test_build.test_suite_id != test_run.test_suite_id ".$nl.
                        "AND test_run.start_timestamp > $date_range_start AND test_run.start_timestamp < $date_range_end");
  my $rtn;

  # Check for test_run entries in which there is a suite mismatch
  # e.g., test_names.test_suite_id != test_run.test_suite_id
  print_verbose(1, "Checking: Mismatched test_suite_id between test_names and test_run\n");
  $rtn = sql_scalar_stmt($select_test_run);
  if($rtn > 0 ) {
    print_begin_group();
    print_update("Check Failed: Mismatched test_suite_id between test_names and test_run\n");
    print_update("              # Entries: $rtn\n");
    print_update_sql($select_test_run);
    print_end_group();
    $require_email = 1;
  }

  # Check for test_build x test_run entries that do not match in test_suite
  # e.g., test_build.test_suite_id != test_run.test_suite_id
  print_verbose(1, "Checking: Mismatched test_suite_id between test_build and test_run\n");
  $rtn = sql_scalar_stmt($select_tr_x_tb);
  if($rtn > 0 ) {
    print_begin_group();
    print_update("Check Failed: Mismatched test_suite_id between test_build and test_run\n");
    print_update("              # Entries: $rtn\n");
    print_update_sql($select_tr_x_tb);
    print_end_group();
    $require_email = 1;
  }


  return 0;
}

sub sql_scalar_stmt() {
  my $cmd = shift(@_);
  my $stmt;
  my $rtn = 0;
  my @row;

  if( defined($debug) ) {
    return 42;
  }

  $stmt = $dbh_mtt->prepare($cmd);

  if( !$stmt->execute() ) {
    print "-- \n$cmd\n--\n";
    return undef($rtn);
  }
  while(@row = $stmt->fetchrow_array ) {
    $rtn = $row[0];
  }

  $stmt->finish;

  return $rtn;
}

sub connect_db() {
  my $mtt_user = "mtt";
  my $stmt;

  $dbh_mtt = DBI->connect("dbi:Pg:dbname=mtt",  $mtt_user);

  $stmt = $dbh_mtt->prepare("set sort_mem = '512MB'");
  $stmt->execute();
  $stmt->finish;

  $stmt = $dbh_mtt->prepare("set constraint_exclusion = on");
  $stmt->execute();
  $stmt->finish;

  return 0;
}

sub disconnect_db() {
  $dbh_mtt->disconnect;

  return 0;
}

sub print_verbose() {
  my $vl = shift(@_);
  my $str = shift(@_);

  if( $vl > $verbose ) {
    return 0;
  }

  print $str;

  return 0;
}

sub set_mail_header() {
  my $cur_date = `date`;
  chomp($cur_date);

  $current_mail_header .= "-"x40 . "\n";
  $current_mail_header .= "Start Time: ".$cur_date."\n";
}

sub print_update_sql() {
  my $str = shift(@_);

  print_update("--------- SQL Begin -----------\n");
  print_update($str . "\n");
  print_update("--------- SQL End -------------\n");
}

sub print_begin_group() {
  print_update( "*"x40 . "\n");
}

sub print_end_group() {
  print_update( "\n\n\n");
}

sub print_update() {
  my $str = shift(@_);

  $current_mail_body .= $str;
}

sub print_update_time() {
  my $command = shift(@_);
  my $diff;
  my $str;

  $end_time = time();
  $diff = $end_time - $start_time;
  $str = sprintf("%5d : %s\n", $diff, $command);

  $current_mail_body .= $str;
}

sub send_status_mail() {
  my %mail;
  my $cur_date = `date`;
  chomp($cur_date);

  $current_mail_header .= "End   Time: ".$cur_date."\n";
  $current_mail_header .= "-"x40 . "\n\n";

  $current_mail_body = $current_mail_header . $current_mail_body . $current_mail_footer;

  if( defined($debug_no_email) ) {
    print "To:      ".$to_email_address."\n";
    print "From:    ".$from_email_address."\n";
    print "Subject: ".$current_mail_subject."\n";
    print "Body:\n";
    print "------------------------------------\n";
    print $current_mail_body . "\n";
    print "------------------------------------\n";
    return 0;
  }

  %mail = ( To      => $to_email_address,
            From    => $from_email_address,
            Subject => $current_mail_subject,
            Message => $current_mail_body
          );

  if( !sendmail(%mail) ) {
    print "Error: Unable to send status email! (".$Mail::Sendmail::error.")\n";
    return -1;
  }

  return 0;
}
