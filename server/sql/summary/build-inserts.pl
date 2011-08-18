#!/bin/env perl

use strict;

my $template = "
INSERT INTO summary_SUB_TABLE (
    start_timestamp,
    end_timestamp,
    submit_http_username,
    compute_cluster_platform_name,
    compute_cluster_platform_hardware,
    compute_cluster_os_name,
    mpi_get_mpi_name,
    mpi_get_mpi_version,
    mpi_install_configure_args_bitness,
    mpi_install_configure_args_endian,
    compiler_compiler_name,
    compiler_compiler_version,
    test_suites_suite_name,
    np,
    pass,
    fail
    SUB_ADD_TR_FIELD
    )
select
    date_trunc('hour', (now() - interval 'SUB_START_TIME')) as start_timestamp,
    date_trunc('hour', (now() - interval 'SUB_END_TIME')) as end_timestamp,
    http_username, platform_name, platform_hardware, os_name, mpi_name, mpi_version,
    bitness,
    endian,
    compiler_name,
    compiler_version,
    suite_name,
    np,
    pass, fail
    SUB_ADD_TR_SELECT
FROM (
    select 
        http_username, platform_name, platform_hardware, os_name, mpi_name, mpi_version,
        bitness,
        endian,
        compiler_name,
        compiler_version,
        SUB_SUITE,
        SUB_NP,
        SUM(case when test_result = 1 then 1 else 0 end) as pass,
        SUM(case when test_result = 0 then 1 else 0 end) as fail
        SUB_ADD_TR_SUM
    FROM  SUB_TABLE
    NATURAL JOIN submit
    NATURAL JOIN compute_cluster
    NATURAL JOIN mpi_get
    NATURAL JOIN mpi_install_configure_args
    JOIN compiler ON (compiler.compiler_id = SUB_TABLE.mpi_install_compiler_id)
    SUB_ADD_TABLES
    WHERE
        start_timestamp >= date_trunc('hour', (now() - interval 'SUB_START_TIME')) AND
        start_timestamp < date_trunc('hour', (now() - interval 'SUB_END_TIME'))
    GROUP BY
        http_username,
        platform_name,
        platform_hardware,
        os_name,
        mpi_name,
        mpi_version,
        bitness,
        endian,
        compiler_name,
        compiler_version,
        suite_name,
        np
) as foo;
";


my $tmp_insert;
my $i;
my $j;
my $str;
my $mpi_install_insert = $template;
$mpi_install_insert =~ s/SUB_TABLE/mpi_install/g;
$mpi_install_insert =~ s/SUB_ADD_TR_FIELD//g;
$mpi_install_insert =~ s/SUB_ADD_TR_SELECT//g;
$mpi_install_insert =~ s/SUB_ADD_TR_SUM//g;
$str = "(NULL) as suite_name";
$mpi_install_insert =~ s/SUB_SUITE/$str/g;
$str = "(-1) as np";
$mpi_install_insert =~ s/SUB_NP/$str/g;
$mpi_install_insert =~ s/SUB_ADD_TABLES//g;
my $test_build_insert = $template;
$test_build_insert =~ s/SUB_TABLE/test_build/g;
$test_build_insert =~ s/SUB_ADD_TR_FIELD//g;
$test_build_insert =~ s/SUB_ADD_TR_SELECT//g;
$test_build_insert =~ s/SUB_ADD_TR_SUM//g;
$str = "suite_name";
$test_build_insert =~ s/SUB_SUITE/$str/g;
$str = "(-1) as np";
$test_build_insert =~ s/SUB_NP/$str/g;
$str = "NATURAL JOIN test_suites";
$test_build_insert =~ s/SUB_ADD_TABLES/$str/g;
my $test_run_insert = $template;
$test_run_insert =~ s/SUB_TABLE/test_run/g;
$str = ",skip, timeout, perf";
$test_run_insert =~ s/SUB_ADD_TR_FIELD/$str/g;
$str = ",skip, timeout, perf";
$test_run_insert =~ s/SUB_ADD_TR_SELECT/$str/g;
$str = (",\n".
        "SUM(case when test_result = 2 then 1 else 0 end) as skip,\n".
        "SUM(case when test_result = 3 then 1 else 0 end) as timeout,\n".
        "SUM(case when test_run.performance_id > 0 then 1 else 0 end) as perf");
$test_run_insert =~ s/SUB_ADD_TR_SUM/$str/g;
$str = "suite_name";
$test_run_insert =~ s/SUB_SUITE/$str/g;
$str = "np";
$test_run_insert =~ s/SUB_NP/$str/g;
$str = "NATURAL JOIN test_suites";
$test_run_insert =~ s/SUB_ADD_TABLES/$str/g;

print "--\n";
print "-- MPI Install\n";
print "--\n";

for($i = 0; $i <= 24; ++$i) {
  $j = $i - 1;

  $tmp_insert = $mpi_install_insert;
  #print "$i -> $j\n";
  $tmp_insert =~ s/SUB_START_TIME/$i hours/g;
  $tmp_insert =~ s/SUB_END_TIME/$j hours/g;
  print $tmp_insert ."\n\n";
}

print "--\n";
print "-- Test Build\n";
print "--\n";

for($i = 0; $i <= 24; ++$i) {
  $j = $i - 1;

  $tmp_insert = $test_build_insert;
  #print "$i -> $j\n";
  $tmp_insert =~ s/SUB_START_TIME/$i hours/g;
  $tmp_insert =~ s/SUB_END_TIME/$j hours/g;
  print $tmp_insert ."\n\n";
}

print "--\n";
print "-- Test Run\n";
print "--\n";

for($i = 0; $i <= 24; ++$i) {
  $j = $i - 1;

  $tmp_insert = $test_run_insert;
  #print "$i -> $j\n";
  $tmp_insert =~ s/SUB_START_TIME/$i hours/g;
  $tmp_insert =~ s/SUB_END_TIME/$j hours/g;
  print $tmp_insert ."\n\n";
}

exit 0;
