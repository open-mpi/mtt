#!/usr/bin/env perl

#
# Josh Hursey
# Note:
#  This script generates child tables for the test_build parent table.
#  The tables are broken down by week in a month. Rules are created per
#  week. It has been suggested that a single trigger might be better than
#  many individual rules, but it is unknown the performance tradeoffs at
#  this time.
#
use strict;

my $argc = scalar(@ARGV);

my $year;
my $month;

my $parent_table = "test_build";
my $child_table_base = "test_build_";


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

foreach $month (@month_array) {
  #
  # Create the partition tables
  #
  print "--\n";
  print "-- Creating ".$parent_table." tables for Weeks 1,2,3,4,5 for $year-$month\n";
  print "--\n";

  my $cur_wk = 0;
  for($cur_wk = 1; $cur_wk <= 5; ++$cur_wk) {
    print "CREATE TABLE ".$child_table_base."y" . $year . "_m" . $month . "_wk" . $cur_wk ." (\n";
    print "    CHECK ( start_timestamp >= DATE '".$year."-".$month."-01' + interval '".($cur_wk - 1)." weeks' and\n";
    print "            start_timestamp < \n";
    print "            case  when  (DATE '".$year."-".$month."-01'    + interval '".$cur_wk." weeks' < DATE '".$year."-".$month."-01' + interval '1 month')\n";
    print "                      then (DATE '".$year."-".$month."-01' + interval '".$cur_wk." weeks')\n";
    print "                  else  (DATE '".$year."-".$month."-01' + interval '1 month')\n";
    print "            end ),\n";
    print "\n";
    print "    PRIMARY KEY (test_build_id),\n";
    print "\n";
    print "    FOREIGN KEY (submit_id) REFERENCES submit(submit_id),\n";
    print "    FOREIGN KEY (compute_cluster_id) REFERENCES compute_cluster(compute_cluster_id),\n";
    print "    FOREIGN KEY (mpi_install_compiler_id) REFERENCES compiler(compiler_id),\n";
    print "    FOREIGN KEY (mpi_get_id) REFERENCES mpi_get(mpi_get_id),\n";
    print "    FOREIGN KEY (mpi_install_configure_id) REFERENCES mpi_install_configure_args(mpi_install_configure_id),\n";
    print "    -- PARTITION/FK PROBLEM: FOREIGN KEY (mpi_install_id) REFERENCES mpi_install(mpi_install_id),\n";
    print "    FOREIGN KEY (test_suite_id) REFERENCES test_suites(test_suite_id),\n";
    print "    FOREIGN KEY (test_build_compiler_id) REFERENCES compiler(compiler_id),\n";
    print "    FOREIGN KEY (description_id) REFERENCES description(description_id),\n";
    print "    FOREIGN KEY (environment_id) REFERENCES environment(environment_id),\n";
    print "    FOREIGN KEY (result_message_id) REFERENCES result_message(result_message_id)\n";
    print "\n";
    print ") INHERITS(".$parent_table.");\n";

    print "\n";
  }

  #
  # Create the indexes
  #
  print "\n";
  print "--\n";
  print "-- Creating Indexes for ".$parent_table." table Weeks 1,2,3,4,5 for $year-$month\n";
  print "--\n";

  for($cur_wk = 1; $cur_wk <= 5; ++$cur_wk) {
    print ("CREATE INDEX ".$child_table_base."y".$year."_m".$month."_wk".$cur_wk."_st ON ".
           $child_table_base."y".$year."_m".$month."_wk".$cur_wk." (start_timestamp);\n");
  }

  print "\n";

  #
  # Create the Rules
  #
  print "--\n";
  print "-- Creating Insert rules for ".$parent_table." tables for Weeks 1,2,3,4,5 for $year-$month\n";
  print "--\n";

  for($cur_wk = 1; $cur_wk <= 5; ++$cur_wk) {
    print "CREATE RULE ".$child_table_base."y" . $year . "_m" . $month . "_wk" . $cur_wk ."_insert AS \n";
    print "   ON INSERT to ".$parent_table." WHERE\n";
    print "           (start_timestamp >= DATE '".$year."-".$month."-01' + interval '".($cur_wk - 1)." weeks' and\n";
    print "            start_timestamp < \n";
    print "            case  when  (DATE '".$year."-".$month."-01'    + interval '".$cur_wk." weeks' < DATE '".$year."-".$month."-01' + interval '1 month')\n";
    print "                      then (DATE '".$year."-".$month."-01' + interval '".$cur_wk." weeks')\n";
    print "                  else  (DATE '".$year."-".$month."-01' + interval '1 month')\n";
    print "            end )\n";
    print "    DO INSTEAD\n";
    print "        INSERT INTO ".$child_table_base."y".$year."_m".$month."_wk".$cur_wk."\n";
    print "        (test_build_id,\n";
    print "         submit_id,\n";
    print "         compute_cluster_id,\n";
    print "         mpi_install_compiler_id,\n";
    print "         mpi_get_id,\n";
    print "         mpi_install_configure_id,\n";
    print "         mpi_install_id,\n";
    print "         test_suite_id,\n";
    print "         test_build_compiler_id,\n";
    print "         description_id,\n";
    print "         start_timestamp,\n";
    print "         test_result,\n";
    print "         trial,\n";
    print "         submit_timestamp,\n";
    print "         duration,\n";
    print "         environment_id,\n";
    print "         result_stdout,\n";
    print "         result_stderr,\n";
    print "         result_message_id,\n";
    print "         merge_stdout_stderr,\n";
    print "         exit_value,\n";
    print "         exit_signal,\n";
    print "         client_serial\n";
    print "        )\n";
    print "        VALUES\n";
    print "            ( NEW.test_build_id,\n";
    print "              NEW.submit_id,\n";
    print "              NEW.compute_cluster_id,\n";
    print "              NEW.mpi_install_compiler_id,\n";
    print "              NEW.mpi_get_id,\n";
    print "              NEW.mpi_install_configure_id,\n";
    print "              NEW.mpi_install_id,\n";
    print "              NEW.test_suite_id,\n";
    print "              NEW.test_build_compiler_id,\n";
    print "              NEW.description_id,\n";
    print "              NEW.start_timestamp,\n";
    print "              NEW.test_result,\n";
    print "              NEW.trial,\n";
    print "              NEW.submit_timestamp,\n";
    print "              NEW.duration,\n";
    print "              NEW.environment_id,\n";
    print "              NEW.result_stdout,\n";
    print "              NEW.result_stderr,\n";
    print "              NEW.result_message_id,\n";
    print "              NEW.merge_stdout_stderr,\n";
    print "              NEW.exit_value,\n";
    print "              NEW.exit_signal,\n";
    print "              NEW.client_serial)\n";
    print ";\n";
    print "\n";
  }

  #
  # Drop tables
  #
  print "--\n";
  print "-- Drop tables\n";
  print "--\n";
  for($cur_wk = 1; $cur_wk <= 5; ++$cur_wk) {
    print ("-- DROP TABLE ".$child_table_base."y".$year."_m".$month."_wk".$cur_wk." CASCADE;\n");
  }
}

exit 0;
