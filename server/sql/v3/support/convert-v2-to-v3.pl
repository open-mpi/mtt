#!/usr/bin/env perl

use strict;

use DBI;

# Perform flush after each write to STDOUT
$| = 1;

my $script_start_time;
my $script_start_conv_time;
my $script_start_conv_tr_time;
my $script_end_time;

my @row;
my $sql_cmd;
my $stmt;

my $new_sql_cmd;
my $new_stmt;
my $table;

if( !defined($ARGV[0])) {
  print "Error: Must Supply a SQL date range!\n";
  exit -1;
}
my $start_interval = $ARGV[0];

my $interval_results_table = "jjh_results";

$script_start_time = time();

print("Processing Date Range:\n");
print $start_interval . "\n\n";

####################################
# Collect Results Range
# Note: Can be done without being attached to DB
####################################
print_header("Collecting results range");
collect_result_range();

##################################
# Connect to mtt3 for reading
#            mtt  for writing
##################################
my $mtt_user     = "mtt";
my $mtt_password;
my $dbh_mtt3;
my $dbh_mtt3_new;
if( defined($mtt_password) ) {
  $dbh_mtt3     = DBI->connect("dbi:Pg:dbname=mtt3", $mtt_user);
  $dbh_mtt3_new = DBI->connect("dbi:Pg:dbname=mtt",  $mtt_user);
}
else {
  $dbh_mtt3     = DBI->connect("dbi:Pg:dbname=mtt3", $mtt_user, $mtt_password);
  $dbh_mtt3_new = DBI->connect("dbi:Pg:dbname=mtt",  $mtt_user, $mtt_password);
}

#$dbh_mtt3->{RaiseError} = 1;
#$dbh_mtt3_new->{RaiseError} = 1;
#$dbh_mtt3_new->{TraceLevel} = "1|SQL";

# Postgresql system options
# Set Sort Memory
my $stmt = $dbh_mtt3->prepare("set sort_mem = '128MB'");
$stmt->execute();
my $stmt = $dbh_mtt3_new->prepare("set sort_mem = '128MB'");
$stmt->execute();


#
# Some generic statements that we want to declare only once.
#
### Normalization select/inserts
my $adone_tr_select = $dbh_mtt3_new->prepare("select 1 from temp_conv_test_run where " .
                                             "old_results_id = ?");

my $adone_tb_select = $dbh_mtt3_new->prepare("select 1 from temp_conv_test_build where " .
                                             "old_results_id = ?");

my $adone_mi_select = $dbh_mtt3_new->prepare("select 1 from temp_conv_mpi_install where " .
                                             "old_results_id = ?");
## Already done checks
my $adone_permalink =
  $dbh_mtt3_new->prepare("SELECT 1 from permalinks where permalink_id = ?");
my $adone_compute_cluster =
  $dbh_mtt3_new->prepare("SELECT 1 from compute_cluster where compute_cluster_id = ?");
my $adone_compiler =
  $dbh_mtt3_new->prepare("SELECT 1 from compiler where compiler_id = ?");
my $adone_mpi_get =
  $dbh_mtt3_new->prepare("SELECT 1 from mpi_get where mpi_get_id = ?");
my $adone_submit =
  $dbh_mtt3_new->prepare("SELECT 1 from submit where submit_id = ?");

####
my $conv_rm_insert = $dbh_mtt3_new->prepare("INSERT into result_message " .
                                            "(result_message_id, " .
                                            " result_message)" .
                                            " VALUES (DEFAULT,?)");
my $conv_rm_select = $dbh_mtt3_new->prepare("select result_message_id from result_message where " .
                                            "result_message = ?");

my $conv_env_insert = $dbh_mtt3_new->prepare("INSERT into environment " .
                                             "(environment_id, " .
                                             " environment)" .
                                             " VALUES (DEFAULT,?)");
my $conv_env_select = $dbh_mtt3_new->prepare("select environment_id from environment where " .
                                            "environment = ?");

my $conv_perf_insert = $dbh_mtt3_new->prepare("INSERT into performance " .
                                             "(performance_id, " .
                                             " latency_bandwidth_id)" .
                                             " VALUES (DEFAULT,?)");
my $conv_perf_select = $dbh_mtt3_new->prepare("select performance_id from performance where " .
                                              "latency_bandwidth_id = ?");

### MPI Install
my $mpi_install_conf_insert = $dbh_mtt3_new->prepare("INSERT into mpi_install_configure_args " .
                                                     "(mpi_install_configure_id, " .
                                                     " vpath_mode, " .
                                                     " bitness, " .
                                                     " endian, " .
                                                     " configure_arguments)" .
                                                     " VALUES (DEFAULT,?,?,?,?)");
my $mpi_install_conf_select = $dbh_mtt3_new->prepare("select mpi_install_configure_id from mpi_install_configure_args where " .
                                                     "vpath_mode = ? and " .
                                                     "bitness = ? and " .
                                                     "endian = ? and " .
                                                     "configure_arguments = ?");

### Test Build
my $test_build_mi_id_select = $dbh_mtt3_new->prepare("select new_mpi_install_id from temp_conv_mpi_install ".
                                                     " where old_mpi_install_id = ?");
my $test_build_mi_conf_select = $dbh_mtt3_new->prepare("select mpi_install_configure_id, compute_cluster_id, mpi_get_id, mpi_install_compiler_id " .
                                                       " from mpi_install ".
                                                       " where mpi_install_id = ?");

my $test_build_ts_insert = $dbh_mtt3_new->prepare("INSERT into test_suites " .
                                                  "(test_suite_id, " .
                                                  " suite_name)" .
                                                  " VALUES (DEFAULT,?)");
my $test_build_ts_select = $dbh_mtt3_new->prepare("select test_suite_id from test_suites where " .
                                                  "suite_name = ?");

### Test Run
my $test_run_tn_insert = $dbh_mtt3_new->prepare("INSERT into test_names " .
                                                "(test_name_id, " .
                                                " test_suite_id, " .
                                                " test_name)" .
                                                " VALUES (DEFAULT,?,?)");
my $test_run_tn_select = $dbh_mtt3_new->prepare("select test_name_id from test_names where " .
                                                "test_name = ? and test_suite_id = ?");

my $test_run_tb_id_select = $dbh_mtt3_new->prepare("select new_test_build_id from temp_conv_test_build " .
                                                   "where old_test_build_id = ?");
my $test_run_tb_conf_ids_select = $dbh_mtt3_new->prepare("select compute_cluster_id, mpi_install_compiler_id, mpi_get_id, mpi_install_configure_id, mpi_install_id, " .
                                                         "test_suite_id, test_build_compiler_id " .
                                                         "from test_build where test_build_id = ?");

my $test_run_command_insert = $dbh_mtt3_new->prepare("INSERT into test_run_command " .
                                                     "(test_run_command_id, " .
                                                     " launcher, " .
                                                     " parameters) " .
                                                     " VALUES (DEFAULT,?,?)");
my $test_run_command_select = $dbh_mtt3_new->prepare("select test_run_command_id from test_run_command where " .
                                                     "launcher = ? and parameters = ?");

#
# NOTE:
#  If we are going to do this in segments then we have to make sure we
#  do not copy data into the new database more than once. Some of the
#  tables are moved over in their entirety each time. We really only want
#  to move those tuples that we haven't inserted yet. These can be easily
#  identified by selecting only those 'ids' that we haven't already inserted.
#
$script_start_conv_time = time();

print_header("Converting table: permalinks");
copy_permalinks();

print_header("Converting table: compute_cluster");
copy_compute_cluster();

print_header("Converting table: compiler");
copy_compiler();

print_header("Converting table: mpi_get");
copy_mpi_get();

print_header("Converting table: submit");
copy_submit();

print_header("Converting table: mpi_install");
copy_mpi_install();

print_header("Converting table: test_build");
copy_test_build();

print_header("Converting table: latency_bandwidth");
copy_lat_bw();

$script_start_conv_tr_time = time();
print_header("Converting table: test_run");
copy_test_run();

$dbh_mtt3->disconnect;
$dbh_mtt3_new->disconnect;

$script_end_time = time();

print "\nCompleted Interval:\n";
print "\t" . $start_interval . "\n";
print "\n";
printf("\tTest Run Time  : %5.2f min.\n", (($script_end_time - $script_start_conv_tr_time)/60.0) );
printf("\tConversion Time: %5.2f min.\n", (($script_end_time - $script_start_conv_time)/60.0) );
printf("\tTotal Time     : %5.2f min.\n", (($script_end_time - $script_start_time)/60.0) );

exit 0;

########################
# test_run
########################
sub copy_test_run() {
  my $row_ref;
  my $insert_stmt_test_run;
  my $i;
  my $count;
  # Transfer data
  my $compute_cluster_id;
  my $mpi_install_compiler_id;
  my $mpi_get_id;
  my $configure_id;
  my $mpi_install_id;
  my $test_suite_id;
  my $test_build_compiler_id;
  my $test_build_id;
  my $latency_bandwidth_id = 0;
  my $performance_id = 0;
  my $new_rm_id;
  my $new_env_id;
  my $new_des_id;

  my $test_name_id;
  my $command_id;
  my $new_test_run_id;

  $count = get_num_tuples($dbh_mtt3,
                          ("select  distinct on (test_run.test_run_id,".$interval_results_table.".results_id) test_run_id " .
                           " from test_run join ".$interval_results_table.
                           " on ".$interval_results_table.".phase = 3 and ".$interval_results_table.".phase_id = test_run.test_run_id " .
                           " group by test_run.test_run_id,".$interval_results_table.".results_id"));

  $sql_cmd = ("select  distinct on (test_run.test_run_id,".$interval_results_table.".results_id) * " .
              " from test_run join ".$interval_results_table.
              " on ".$interval_results_table.".phase = 3 and ".$interval_results_table.".phase_id = test_run.test_run_id " .
              "");

  $stmt = $dbh_mtt3->prepare($sql_cmd);
  $stmt->execute();

  $insert_stmt_test_run = $dbh_mtt3_new->prepare("INSERT into test_run " .
                                                 "(test_run_id, " .
                                                 " submit_id, ".
                                                 " compute_cluster_id, ".
                                                 " mpi_install_compiler_id, ".
                                                 " mpi_get_id, ".
                                                 " mpi_install_configure_id, ".
                                                 " mpi_install_id, " .
                                                 " test_suite_id, " .
                                                 " test_build_compiler_id, ".
                                                 " test_build_id," .
                                                 " test_name_id, " .
                                                 " performance_id, " .
                                                 " test_run_command_id, " .
                                                 " np, " .
                                                 " full_command, " .
                                                 " description_id, ".
                                                 " start_timestamp, ".
                                                 " test_result, ".
                                                 " trial, ".
                                                 " submit_timestamp, ".
                                                 " duration, ".
                                                 " environment_id, ".
                                                 " result_stdout, ".
                                                 " result_stderr, ".
                                                 " result_message_id, ".
                                                 " merge_stdout_stderr, ".
                                                 " exit_value, ".
                                                 " exit_signal, ".
                                                 " client_serial)" .
                                                 "VALUES (DEFAULT,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");

  $i = 0;
  my $tt   = 0;
  my $tt_p = 0;
  my $ad   = 0;
  while($row_ref = $stmt->fetchrow_arrayref ) {
    if( $i % 500 == 0 ) {
      $tt_p = $tt;
      $tt = ((time() - $script_start_conv_tr_time)/60.0);
      printf("Inserting %4d of %4d (ad %5d)\t", $i, $count, $ad);
      printf("(%5.2f min. Elapsed)\t", $tt);
      if( $i <= 0 || 0 >= ($tt - $tt_p) ) {
        printf("\n");
      }
      else {
        printf("[%5.2f : %5.2f tuples/min.]\n", (500/($tt - $tt_p)) , ($i/$tt) );
      }
    }

    #
    # Check to see if we have already processed this row
    #
    if( 0 == already_done($row_ref->[$stmt->{NAME_lc_hash}{results_id} ],
                          $adone_tr_select) ) {
      $ad++;
      #printf("Already finished [%d]\n",
      #       $row_ref->[$stmt->{NAME_lc_hash}{results_id} ]);
      ++$i;
      next;
    }

    #
    # Get the test_build information to transfer over
    #
    ($compute_cluster_id, $mpi_install_compiler_id, $mpi_get_id, $configure_id, $mpi_install_id,
     $test_suite_id, $test_build_compiler_id, $test_build_id) =
       test_run_get_test_build_ids($row_ref->[$stmt->{NAME_lc_hash}{test_build_id} ]);

    if( $test_build_id < 0 || $configure_id < 0 ) {
      next;
    }

    #
    # Translate the test names
    #
    $test_name_id = test_run_create_test_name_id($test_suite_id, $row_ref->[$stmt->{NAME_lc_hash}{test_name} ]);

    #
    # Translate the 'command' field
    #
    $command_id = test_run_create_command_id($row_ref->[$stmt->{NAME_lc_hash}{test_name} ],
                                             $row_ref->[$stmt->{NAME_lc_hash}{command} ]);

    #
    # Translate the 'result_message' field
    #
    $new_rm_id = conv_result_message($row_ref->[$stmt->{NAME_lc_hash}{result_message} ]);

    #
    # Translate the 'environment' field
    #
    $new_env_id = conv_environment($row_ref->[$stmt->{NAME_lc_hash}{environment} ]);

    #
    # Translate the 'description' field (no valid entries yet)
    #
    $new_des_id = 0; # conv_description("");

    #
    # Translate the 'latency bandwidth' or 'performance' field
    #
    $performance_id = conv_perf($row_ref->[$stmt->{NAME_lc_hash}{latency_bandwidth_id} ]);

    #
    # Insert the test_run result
    #
    $insert_stmt_test_run->execute($row_ref->[$stmt->{NAME_lc_hash}{submit_id} ],
                                   $compute_cluster_id,
                                   $mpi_install_compiler_id,
                                   $mpi_get_id,
                                   $configure_id,
                                   $mpi_install_id,
                                   $test_suite_id,
                                   $test_build_compiler_id,
                                   $test_build_id,
                                   $test_name_id,
                                   $performance_id,
                                   $command_id,
                                   $row_ref->[$stmt->{NAME_lc_hash}{np} ],
                                   $row_ref->[$stmt->{NAME_lc_hash}{command} ],
                                   $new_des_id,
                                   $row_ref->[$stmt->{NAME_lc_hash}{start_timestamp} ],
                                   $row_ref->[$stmt->{NAME_lc_hash}{test_result} ],
                                   $row_ref->[$stmt->{NAME_lc_hash}{trial} ],
                                   $row_ref->[$stmt->{NAME_lc_hash}{submit_timestamp} ],
                                   $row_ref->[$stmt->{NAME_lc_hash}{duration} ],
                                   $new_env_id,
                                   $row_ref->[$stmt->{NAME_lc_hash}{result_stdout} ],
                                   $row_ref->[$stmt->{NAME_lc_hash}{result_stderr} ],
                                   $new_rm_id,
                                   $row_ref->[$stmt->{NAME_lc_hash}{merge_stdout_stderr} ],
                                   $row_ref->[$stmt->{NAME_lc_hash}{exit_value} ],
                                   $row_ref->[$stmt->{NAME_lc_hash}{exit_signal} ],
                                   $row_ref->[$stmt->{NAME_lc_hash}{client_serial} ]);

    $new_test_run_id = get_last_insert($dbh_mtt3_new, "test_run_test_run_id_seq");

    #
    # Insert the test_run translation to the new id
    # ---------------------+---------------------+-----------------
    # test_run_id (new)  | test_run_id (old) | results_id (old)
    # ---------------------+---------------------+-----------------
    #
    temp_id_translation($new_test_run_id,
                        $row_ref->[$stmt->{NAME_lc_hash}{test_run_id} ],
                        $row_ref->[$stmt->{NAME_lc_hash}{results_id} ],
                        "temp_conv_test_run");

    $i++;
  }

  printf("Inserted: %7d tuples (total %7d or count %7d [%5d ad])\n", $i, get_count($dbh_mtt3_new, "test_run"), $count, $ad);

  #
  # Invalidate some statements to save memory
  #
  $stmt->finish;
  $insert_stmt_test_run->finish;

  $test_run_tn_insert->finish;
  $test_run_tn_select->finish;

  $test_run_tb_id_select->finish;
  $test_run_tb_conf_ids_select->finish;

  $test_run_command_insert->finish;
  $test_run_command_select->finish;

  $adone_tr_select->finish;
}

sub test_run_create_test_name_id() {
  my $test_suite_id = shift(@_);
  my $test_name = shift(@_);

  my $test_name_id = -1;

  my @row_ref;

  #
  # Try to find an existing tuple first
  #
  $test_run_tn_select->execute($test_name, $test_suite_id);
  while(@row = $test_run_tn_select->fetchrow_array ) {
    $test_name_id = $row[0];
  }

  if($test_name_id >= 0 ) {
    ;#print "Test Name <$test_name [$test_suite_id]>  FOUND.\n";
  }
  else {
    print "Inserting a new Test Name <$test_name [$test_suite_id]>.\n";

    $test_run_tn_insert->execute($test_suite_id, $test_name);

    $test_name_id = get_last_insert($dbh_mtt3_new, "test_names_test_name_id_seq");
  }

  return $test_name_id;
}

sub test_run_create_command_id() {
  my $test_name = shift(@_);
  my $old_command = shift(@_);
  my $tmp_command;

  my $launcher;
  my $params;

  my $command_id = -1;

  my @row_ref;

  # Known Parameters list
  my %known_params = ( '--mca'  => 2,
                       '-mca'   => 2,
                       '--gmca' => 2,
                       '-gmca'  => 2,
                       '-am'    => 1,
                       '--ssi'  => 2);
  my $key;
  my $value;
  my $p_search;

  #
  # JJH: For now do nothing and use the empty ID = 0
  # JJH: we will fixup the data post conversion.
  #
  return 0;

  $tmp_command = $old_command;

  # Strip off beginning whitespace, if any
  $old_command =~ s/^\s*//;

  # Extract launcher
  if( $old_command =~ /\s+/ ) {
    $launcher = $`;
    $old_command =~ s/^$launcher\s*//;
  }

  # Strip off --prefix argument, if any
  $old_command =~ s/(--prefix)\s+\S+\s+//;

  # Strip off --host list argument, if any
  $old_command =~ s/(--host)\s+\S+\s+//;

  #
  # Pull out the parameters we are concerned with
  #
  $params = "";
  for $key (keys %known_params) {
    $value = $known_params{$key};
    if( $value <= 0 ) {
      $p_search = "($key)";
    }
    elsif( $value == 1 ) {
      $p_search = "($key)\\s+\\S+";
    }
    elsif( $value == 2 ) {
      $p_search = "($key)\\s+\\S+\\s+\\S+";
    }

    #print "Key <$key> Value <".$known_params{$key}."> [$p_search]\n";

    while($old_command =~ /$p_search/ ) {
      $params .= " " . $&;
      $old_command = $';
    }
  }

  #
  # Cleanup arguments by stripping off whitespace before and after
  #
  $params =~ s/^\s*//;
  $params =~ s/\s*$//;
  $launcher =~ s/^\s*//;
  $launcher =~ s/\s*$//;

  #
  # Try to find an existing tuple first
  #
  $test_run_command_select->execute($launcher, $params);
  while(@row = $test_run_command_select->fetchrow_array ) {
    $command_id = $row[0];
  }

  if($command_id >= 0 ) {
    ;#print "Command <$launcher> <$params>  FOUND.\n";
  }
  else {
    print "Inserting a new Command <$launcher> <$params> [$test_name].\n";
    print "Full Command <$tmp_command>\n\n";

    $test_run_command_insert->execute($launcher, $params);

    $command_id = get_last_insert($dbh_mtt3_new, "test_run_command_test_run_command_id_seq");
  }

  return $command_id;
}

sub test_run_get_test_build_ids() {
  my $test_build_id = shift(@_);
  my $new_test_build_id = -1;
  # Transfer data
  my $compute_cluster_id = -1;
  my $mpi_install_compiler_id = -1;
  my $mpi_get_id = -1;
  my $configure_id = -1;
  my $mpi_install_id = -1;
  my $test_suite_id = -1;
  my $test_build_compiler_id = -1;

  my $val = -1;

  #
  # Get new mpi_install_id
  $test_run_tb_id_select->execute($test_build_id);
  while(@row = $test_run_tb_id_select->fetchrow_array ) {
    $new_test_build_id = $row[0];
    last;
  }

  if(  $new_test_build_id < 0 ) {
    print "ERROR: Failed to get test_build_id [old = $test_build_id ]\n";
    return (-1, -1, -1, -1, -1, -1, -1, -1);
  }

  #
  # Get configure_id
  $test_run_tb_conf_ids_select->execute($new_test_build_id);

  while(@row = $test_run_tb_conf_ids_select->fetchrow_array ) {
    $compute_cluster_id = $row[0];
    $mpi_install_compiler_id = $row[1];
    $mpi_get_id = $row[2];
    $configure_id = $row[3];
    $mpi_install_id = $row[4];
    $test_suite_id = $row[5];
    $test_build_compiler_id = $row[6];

    last;
  }

  return ($compute_cluster_id, $mpi_install_compiler_id, $mpi_get_id, $configure_id, $mpi_install_id,
          $test_suite_id, $test_build_compiler_id, $new_test_build_id);
}

########################
# test_build
########################
sub copy_test_build() {
  my $row_ref;
  my $insert_stmt_test_build;
  my $i;
  my $configure_id;
  my $mpi_install_id;
  my $mpi_install_compiler_id;
  my $test_suite_id;
  my $new_test_build_id;
  my $mpi_get_id;
  my $compute_cluster_id;
  my $count;
  my $new_rm_id;
  my $new_env_id;
  my $new_des_id;

  $count = get_num_tuples($dbh_mtt3,
                          ("select  distinct on (test_build.test_build_id,".$interval_results_table.".results_id) test_build_id " .
                           " from test_build join ".$interval_results_table.
                           " on ".$interval_results_table.".phase = 2 and ".$interval_results_table.".phase_id = test_build.test_build_id " .
                           " group by test_build.test_build_id,".$interval_results_table.".results_id"));

  $sql_cmd = ("select  distinct on (test_build.test_build_id,".$interval_results_table.".results_id) * " .
              " from test_build join ".$interval_results_table.
              " on ".$interval_results_table.".phase = 2 and ".$interval_results_table.".phase_id = test_build.test_build_id " .
              "");
  $stmt = $dbh_mtt3->prepare($sql_cmd);
  $stmt->execute();

  $insert_stmt_test_build = $dbh_mtt3_new->prepare("INSERT into test_build " .
                                                   "(test_build_id, " .
                                                   " submit_id, ".
                                                   " compute_cluster_id, ".
                                                   " mpi_install_compiler_id, ".
                                                   " mpi_get_id, ".
                                                   " mpi_install_configure_id, ".
                                                   " mpi_install_id, " .
                                                   " test_suite_id, " .
                                                   " test_build_compiler_id, ".
                                                   " description_id, ".
                                                   " start_timestamp, ".
                                                   " test_result, ".
                                                   " trial, ".
                                                   " submit_timestamp, ".
                                                   " duration, ".
                                                   " environment_id, ".
                                                   " result_stdout, ".
                                                   " result_stderr, ".
                                                   " result_message_id, ".
                                                   " merge_stdout_stderr, ".
                                                   " exit_value, ".
                                                   " exit_signal, ".
                                                   " client_serial)" .
                                                   "VALUES (DEFAULT,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");

  $i = 0;
  my $ad = 0;
  while($row_ref = $stmt->fetchrow_arrayref ) {
    if( $i % 200 == 0) {
      printf("Inserting %4d of %4d (ad %5d)\n", $i, $count, $ad);
    }

    #
    # Check to see if we have already processed this row
    #
    if( 0 == already_done($row_ref->[$stmt->{NAME_lc_hash}{results_id} ],
                          $adone_tb_select) ) {
      ++$ad;
      #printf("Already finished [%d]\n",
      #       $row_ref->[$stmt->{NAME_lc_hash}{results_id} ]);
      ++$i;
      next;
    }

    #
    # Translate the configuration arguments
    #
    $test_suite_id = test_build_create_test_suite_id($row_ref->[$stmt->{NAME_lc_hash}{suite_name} ]);
    ($mpi_install_id, $configure_id, $compute_cluster_id, $mpi_get_id, $mpi_install_compiler_id) =
      test_build_get_mpi_install_ids($row_ref->[$stmt->{NAME_lc_hash}{mpi_install_id} ]);

    if( $mpi_install_id < 0 || $configure_id < 0 ) {
      next;
    }

    #
    # Translate the 'result_message' field
    #
    $new_rm_id = conv_result_message($row_ref->[$stmt->{NAME_lc_hash}{result_message} ]);

    #
    # Translate the 'environment' field
    #
    $new_env_id = conv_environment($row_ref->[$stmt->{NAME_lc_hash}{environment} ]);

    #
    # Translate the 'description' field (no valid entries yet)
    #
    $new_des_id = 0; # conv_description("");

    #
    # Insert the test_build result
    #
    $insert_stmt_test_build->execute($row_ref->[$stmt->{NAME_lc_hash}{submit_id} ],
                                     $compute_cluster_id,
                                     $mpi_install_compiler_id,
                                     $mpi_get_id,
                                     $configure_id,
                                     $mpi_install_id,
                                     $test_suite_id,
                                     $row_ref->[$stmt->{NAME_lc_hash}{compiler_id} ],
                                     $new_des_id,
                                     $row_ref->[$stmt->{NAME_lc_hash}{start_timestamp} ],
                                     $row_ref->[$stmt->{NAME_lc_hash}{test_result} ],
                                     $row_ref->[$stmt->{NAME_lc_hash}{trial} ],
                                     $row_ref->[$stmt->{NAME_lc_hash}{submit_timestamp} ],
                                     $row_ref->[$stmt->{NAME_lc_hash}{duration} ],
                                     $new_env_id,
                                     $row_ref->[$stmt->{NAME_lc_hash}{result_stdout} ],
                                     $row_ref->[$stmt->{NAME_lc_hash}{result_stderr} ],
                                     $new_rm_id,
                                     $row_ref->[$stmt->{NAME_lc_hash}{merge_stdout_stderr} ],
                                     $row_ref->[$stmt->{NAME_lc_hash}{exit_value} ],
                                     $row_ref->[$stmt->{NAME_lc_hash}{exit_signal} ],
                                     $row_ref->[$stmt->{NAME_lc_hash}{client_serial} ]);

    $new_test_build_id = get_last_insert($dbh_mtt3_new, "test_build_test_build_id_seq");

    #
    # Insert the test_build translation to the new id
    # ---------------------+---------------------+-----------------
    # test_build_id (new)  | test_build_id (old) | results_id (old)
    # ---------------------+---------------------+-----------------
    #
    temp_id_translation($new_test_build_id,
                        $row_ref->[$stmt->{NAME_lc_hash}{test_build_id} ],
                        $row_ref->[$stmt->{NAME_lc_hash}{results_id} ],
                        "temp_conv_test_build");

    $i++;
  }

  printf("Inserted: %4d tuples (total %4d or count %4d [%5d ad])\n", $i, get_count($dbh_mtt3_new, "test_build"), $count, $ad);

  #
  # Invalidate some statements to save memory
  #
  $stmt->finish;
  $insert_stmt_test_build->finish;

  $test_build_mi_id_select->finish;
  $test_build_mi_conf_select->finish;

  $test_build_ts_insert->finish;
  $test_build_ts_select->finish;

  $adone_tb_select->finish;

}

sub test_build_create_test_suite_id() {
  my $suite_name = shift(@_);
  my $test_suite_id = -1;

  my @row_ref;

  #
  # Try to find an existing tuple first
  #
  $test_build_ts_select->execute($suite_name);
  while(@row = $test_build_ts_select->fetchrow_array ) {
    $test_suite_id = $row[0];
  }

  if($test_suite_id >= 0 ) {
    ;#print "Test Suite <$suite_name>  FOUND.\n";
  }
  else {
    print "Inserting a new Test Suite <$suite_name>.\n";
    $test_build_ts_insert->execute($suite_name);

    $test_suite_id = get_last_insert($dbh_mtt3_new, "test_suites_test_suite_id_seq");
  }

  return $test_suite_id;
}

sub test_build_get_mpi_install_ids() {
  my $mpi_install_id = shift(@_);
  my $new_mpi_install_id = -1;
  my $configure_id = -1;
  my $compute_cluster_id = -1;
  my $mpi_get_id = -1;
  my $compiler_id = -1;
  my $val = -1;

  #
  # Get new mpi_install_id
  $test_build_mi_id_select->execute($mpi_install_id);

  while(@row = $test_build_mi_id_select->fetchrow_array ) {
    $new_mpi_install_id = $row[0];
    last;
  }

  if(  $new_mpi_install_id < 0 ) {
    print "ERROR: Failed to get mpi_install_id [old = $mpi_install_id ]\n";
    return (-1, -1);
  }
  #
  # Get configure_id
  $test_build_mi_conf_select->execute($new_mpi_install_id);

  while(@row = $test_build_mi_conf_select->fetchrow_array ) {
    $configure_id = $row[0];
    $compute_cluster_id = $row[1];
    $mpi_get_id = $row[2];
    $compiler_id = $row[3];
    last;
  }

  return ($new_mpi_install_id, $configure_id, $compute_cluster_id, $mpi_get_id, $compiler_id);
}

########################
# mpi_install
########################
sub copy_mpi_install() {
  my $row_ref;
  my $insert_stmt_mpi_install;
  my $i;
  my $configure_id;
  my $new_mpi_install_id;
  my $new_rm_id;
  my $new_env_id;
  my $new_des_id;
  my $count;

  $count = get_num_tuples($dbh_mtt3,
                          ("select  distinct on (mpi_install.mpi_install_id,".$interval_results_table.".results_id) mpi_install_id " .
                           " from mpi_install join ".$interval_results_table.
                           " on ".$interval_results_table.".phase = 1 and ".$interval_results_table.".phase_id = mpi_install.mpi_install_id " .
                           " group by mpi_install.mpi_install_id,".$interval_results_table.".results_id"));

  $sql_cmd = ("select  distinct on (mpi_install.mpi_install_id,".$interval_results_table.".results_id) * " .
              " from mpi_install join ".$interval_results_table.
              " on ".$interval_results_table.".phase = 1 and ".$interval_results_table.".phase_id = mpi_install.mpi_install_id " .
              "");
  $stmt = $dbh_mtt3->prepare($sql_cmd);
  $stmt->execute();

  $insert_stmt_mpi_install = $dbh_mtt3_new->prepare("INSERT into mpi_install " .
                                     "(mpi_install_id, " .
                                     " submit_id, ".
                                     " compute_cluster_id, ".
                                     " mpi_install_compiler_id, ".
                                     " mpi_get_id, ".
                                     " mpi_install_configure_id, ".
                                     " description_id, ".
                                     " start_timestamp, ".
                                     " test_result, ".
                                     " trial, ".
                                     " submit_timestamp, ".
                                     " duration, ".
                                     " environment_id, ".
                                     " result_stdout, ".
                                     " result_stderr, ".
                                     " result_message_id, ".
                                     " merge_stdout_stderr, ".
                                     " exit_value, ".
                                     " exit_signal, ".
                                     " client_serial)" .
                                     "VALUES (DEFAULT,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");

  $i = 0;
  my $ad = 0;
  while($row_ref = $stmt->fetchrow_arrayref ) {
    if( $i % 100 == 0) {
      printf("Inserting %4d of %4d (ad %5d)\n", $i, $count, $ad);
    }

    #
    # Check to see if we have already processed this row
    #
    if( 0 == already_done($row_ref->[$stmt->{NAME_lc_hash}{results_id} ],
                          $adone_mi_select) ) {
      ++$ad;
      #printf("Already finished [%d]\n",
      #       $row_ref->[$stmt->{NAME_lc_hash}{results_id} ]);
      ++$i;
      next;
    }

    #
    # Translate the configuration arguments
    #
    $configure_id = mpi_install_create_configure_id(
                       $row_ref->[$stmt->{NAME_lc_hash}{vpath_mode} ],
                       $row_ref->[$stmt->{NAME_lc_hash}{bitness} ],
                       $row_ref->[$stmt->{NAME_lc_hash}{endian} ],
                       $row_ref->[$stmt->{NAME_lc_hash}{configure_arguments} ]);

    #
    # Translate the 'result_message' field
    #
    $new_rm_id = conv_result_message($row_ref->[$stmt->{NAME_lc_hash}{result_message} ]);

    #
    # Translate the 'environment' field
    #
    $new_env_id = conv_environment($row_ref->[$stmt->{NAME_lc_hash}{environment} ]);

    #
    # Translate the 'description' field (no valid entries yet)
    #
    $new_des_id = 0; # conv_description("");

    #
    # Insert the mpi_install result
    #
    $insert_stmt_mpi_install->execute($row_ref->[$stmt->{NAME_lc_hash}{submit_id} ],
                                      $row_ref->[$stmt->{NAME_lc_hash}{compute_cluster_id} ],
                                      $row_ref->[$stmt->{NAME_lc_hash}{compiler_id} ],
                                      $row_ref->[$stmt->{NAME_lc_hash}{mpi_get_id} ],
                                      $configure_id,
                                      $new_des_id,
                                      $row_ref->[$stmt->{NAME_lc_hash}{start_timestamp} ],
                                      $row_ref->[$stmt->{NAME_lc_hash}{test_result} ],
                                      $row_ref->[$stmt->{NAME_lc_hash}{trial} ],
                                      $row_ref->[$stmt->{NAME_lc_hash}{submit_timestamp} ],
                                      $row_ref->[$stmt->{NAME_lc_hash}{duration} ],
                                      $new_env_id,
                                      $row_ref->[$stmt->{NAME_lc_hash}{result_stdout} ],
                                      $row_ref->[$stmt->{NAME_lc_hash}{result_stderr} ],
                                      $new_rm_id,
                                      $row_ref->[$stmt->{NAME_lc_hash}{merge_stdout_stderr} ],
                                      $row_ref->[$stmt->{NAME_lc_hash}{exit_value} ],
                                      $row_ref->[$stmt->{NAME_lc_hash}{exit_signal} ],
                                      $row_ref->[$stmt->{NAME_lc_hash}{client_serial} ]);

    $new_mpi_install_id = get_last_insert($dbh_mtt3_new, "mpi_install_mpi_install_id_seq");

    #
    # Insert the mpi_install translation to the new id
    # ----------------------+----------------------+-----------------
    # mpi_install_id (new)  | mpi_install_id (old) | results_id (old)
    # ----------------------+----------------------+-----------------
    #
    temp_id_translation($new_mpi_install_id,
                               $row_ref->[$stmt->{NAME_lc_hash}{mpi_install_id} ],
                               $row_ref->[$stmt->{NAME_lc_hash}{results_id} ],
                               "temp_conv_mpi_install");

    $i++;
  }

  printf("Inserted: %4d tuples (total %4d or count %4d [%5d ad])\n", $i, get_count($dbh_mtt3_new, "mpi_install"), $count, $ad);

  #
  # Invalidate some statements to save memory
  #
  $stmt->finish;
  $insert_stmt_mpi_install->finish;

  $mpi_install_conf_insert->finish;
  $mpi_install_conf_select->finish;

  $adone_mi_select->finish;

}

sub mpi_install_create_configure_id() {
  my $old_vpath_mode = shift(@_);
  my $old_bitness = shift(@_);
  my $old_endian = shift(@_);
  my $old_config = shift(@_);
  my $new_vpath_mode = "00";
  my $new_bitness = "000000";
  my $new_endian;
  my $configure_id = -1;

  my @row_ref;

  #
  # Convert vpath mode
  #
  if(    (($old_vpath_mode+0) & (0 | (1 << 0)) ) != 0 ) { $new_vpath_mode = "01"; }
  elsif( (($old_vpath_mode+0) & (0 | (1 << 1)) ) != 0 ) { $new_vpath_mode = "10"; }
  else {                                                  $new_vpath_mode = "00"; }

  #
  # Convert bitness
  #
  if( (($old_bitness+0) ^ (0 | (1 << 2) | (1 << 3)))  == 0 ) { $new_bitness = "001100"; }
  elsif( (($old_bitness+0) & (0 | (1 << 0)) ) != 0 ) {         $new_bitness = "000001"; }
  elsif( (($old_bitness+0) & (0 | (1 << 1)) ) != 0 ) {         $new_bitness = "000010"; }
  elsif( (($old_bitness+0) & (0 | (1 << 2)) ) != 0 ) {         $new_bitness = "000100"; }
  elsif( (($old_bitness+0) & (0 | (1 << 3)) ) != 0 ) {         $new_bitness = "001000"; }
  elsif( (($old_bitness+0) & (0 | (1 << 4)) ) != 0 ) {         $new_bitness = "010000"; }
  else {                                                       $new_bitness = "000000"; }

  #
  # Convert endian
  #
  if(    (($old_endian+0) ^ (0 | (1 << 0) | (1 << 1)))  == 0 ) { $new_endian = "11"; }
  elsif( (($old_endian+0) & (0 | (1 << 0)) ) != 0 ) { $new_endian = "01"; }
  elsif( (($old_endian+0) & (0 | (1 << 1)) ) != 0 ) { $new_endian = "10"; }
  else {                                              $new_endian = "00"; }

  #
  # Try to find an existing tuple first
  #
  $mpi_install_conf_select->execute($new_vpath_mode, $new_bitness, $new_endian, $old_config);
  while(@row = $mpi_install_conf_select->fetchrow_array ) {
    $configure_id = $row[0];
  }

  if($configure_id >= 0 ) {
    ;#print "Row FOUND. Return duplicate ID\n";
  }
  else {
    print "Inserting a new configuration...\n";
    $mpi_install_conf_insert->execute($new_vpath_mode, $new_bitness, $new_endian, $old_config);

    $configure_id = get_last_insert($dbh_mtt3_new, "mpi_install_configure_args_mpi_install_configure_id_seq");
  }

  return $configure_id;
}

######################
# Normalization tables
#######################
sub conv_result_message() {
  my $result_message = shift(@_);
  my $rm_id = -1;
  my @row_ref;

  #
  # Try to find an existing tuple first
  #
  $conv_rm_select->execute($result_message);
  while(@row = $conv_rm_select->fetchrow_array ) {
    $rm_id = $row[0];
  }

  if($rm_id >= 0 ) {
    ;#print "Row FOUND. Return duplicate ID\n";
  }
  else {
    print "Inserting a Result Message <$result_message>...\n";
    $conv_rm_insert->execute($result_message);

    $rm_id = get_last_insert($dbh_mtt3_new, "result_message_result_message_id_seq");
  }

  return $rm_id;
}

sub conv_environment() {
  my $env = shift(@_);
  my $env_id = -1;
  my @row_ref;

  #
  # Try to find an existing tuple first
  #
  $conv_env_select->execute($env);
  while(@row = $conv_env_select->fetchrow_array ) {
    $env_id = $row[0];
  }

  if($env_id >= 0 ) {
    ;#print "Row FOUND. Return duplicate ID\n";
  }
  else {
    print "Inserting a New Environment <$env>...\n";
    $conv_env_insert->execute($env);

    $env_id = get_last_insert($dbh_mtt3_new, "environment_environment_id_seq");
  }

  return $env_id;
}

sub conv_perf() {
  my $lat_bw = shift(@_);
  my $perf_id = -1;
  my @row_ref;

  # Simple case, when no perf data is available
  # 73851 is eq to 0
  if( $lat_bw <= 0 || $lat_bw == 73851) {
    return 0;
  }

  #
  # Try to find an existing tuple first
  #
  $conv_perf_select->execute($lat_bw);
  while(@row = $conv_perf_select->fetchrow_array ) {
    $perf_id = $row[0];
  }

  if($perf_id >= 0 ) {
    ;#print "Row FOUND. Return duplicate ID\n";
  }
  else {
    print "Inserting a New Performance (Latency Bandwith) Entry...\n";
    $conv_perf_insert->execute($lat_bw);

    $perf_id = get_last_insert($dbh_mtt3_new, "performance_performance_id_seq");
  }

  return $perf_id;
}

########################
# submit
########################
sub copy_submit() {
  my $row_ref;
  my $new_stmt;
  my $i;
  my $count;
  my $ad = 0;

  $count = get_num_tuples($dbh_mtt3,
                          ("select * from submit"));

  $sql_cmd = ("select * from submit");

  $stmt = $dbh_mtt3->prepare($sql_cmd);
  $stmt->execute();

  $new_stmt = $dbh_mtt3_new->prepare("INSERT into submit " .
                                     "(submit_id, hostname, local_username, http_username, mtt_client_version)" .
                                     "VALUES (?,?,?,?,?)");

  $i = 0;
  while($row_ref = $stmt->fetchrow_arrayref ) {
    if( $i % 100 == 0) {
      printf("Inserting %4d of %4d [%5d]\n", $i, $count, $ad);
    }

    #
    # If this tuple is accounted for then skip it, ow add it new
    #
    if( 0 <= already_done($row_ref->[$stmt->{NAME_lc_hash}{submit_id} ],
                          $adone_submit) ) {
      ++$ad;
    }
    else {
      $new_stmt->execute($row_ref->[$stmt->{NAME_lc_hash}{submit_id} ],
                         $row_ref->[$stmt->{NAME_lc_hash}{hostname} ],
                         $row_ref->[$stmt->{NAME_lc_hash}{local_username} ],
                         $row_ref->[$stmt->{NAME_lc_hash}{http_username} ],
                         $row_ref->[$stmt->{NAME_lc_hash}{mtt_client_version} ]);
    }
    $i++;
  }

  # Make sure to update the sequence number
  system("psql -U iu -d mtt -c \"select setval('submit_submit_id_seq',(select max(submit_id) from submit))\"");

  printf("Inserted: %4d tuples (total %4d or count %4d [%5d])\n", $i, get_count($dbh_mtt3_new, "submit"), $count, $ad);

  $adone_submit->finish;
}

########################
# Collect result range = stabilize for quick lookups.
########################
sub collect_result_range() {
  my $row_ref;
  my $new_stmt;

  system("psql -U iu -d mtt3 -c 'drop table ".$interval_results_table."'");
  system("psql -U iu -d mtt3 -c \"SELECT * INTO ".$interval_results_table." FROM results WHERE " . $start_interval . "\"");
  system("psql -U iu -d mtt3 -c \"select count(*),min(start_timestamp),max(start_timestamp) from ".$interval_results_table."\"");
}

########################
# latency_bandwidth
########################
sub copy_lat_bw() {
  my $last_id = -1;

  $last_id = get_last_id($dbh_mtt3_new, "latency_bandwidth", "latency_bandwidth_id");

  # Below query only valid in 8.0 series of Postgresql, so we have to do it the long way
  #system("psql -U iu -d mtt3   -c 'COPY (select * from latency_bandwidth where latency_bandwidth_id > '".$last_id."'   TO STDOUT' | ".
  #       "psql -U iu -d mtt -c 'COPY latency_bandwidth   FROM STDIN'");

  # Get the range in a tmp table
  system("psql -U iu -d mtt3   -c \"select * into jjh_lb from latency_bandwidth where ".
         "latency_bandwidth_id != 73851 and latency_bandwidth_id > $last_id\"");

  # Transfer over the tmp table
  system("psql -U iu -d mtt3   -c 'COPY jjh_lb   TO STDOUT' | ".
         "psql -U iu -d mtt -c 'COPY latency_bandwidth   FROM STDIN'");

  # Make sure to update the sequence number
  system("psql -U iu -d mtt -c \"select setval('latency_bandwidth_latency_bandwidth_id_seq',(select max(latency_bandwidth_id) from latency_bandwidth))\"");

  printf("Inserted: %4d tuples (total = %4d)\n", get_count($dbh_mtt3, "jjh_lb"), get_count($dbh_mtt3_new, "latency_bandwidth"));

  # Drop the table
  system("psql -U iu -d mtt3   -c 'drop table jjh_lb'");
}

########################
# mpi_get
########################
sub copy_mpi_get() {
  my $row_ref;
  my $new_stmt;
  my $count;
  my $i;
  my $ad = 0;

  $count = get_count($dbh_mtt3, "mpi_get"),

  $sql_cmd = "select * from mpi_get";
  $stmt = $dbh_mtt3->prepare($sql_cmd);
  $stmt->execute();

  $new_stmt = $dbh_mtt3_new->prepare("INSERT into mpi_get " .
                                     "(mpi_get_id, mpi_name, mpi_version)" .
                                     "VALUES (?,?,?)");

  $i = 0;
  while($row_ref = $stmt->fetchrow_arrayref ) {
    if( $i % 100 == 0) {
      printf("Inserting %4d of %4d [%5d]\n", $i, $count, $ad);
    }

    #
    # If this tuple is accounted for then skip it, ow add it new
    #
    if( 0 <= already_done($row_ref->[$stmt->{NAME_lc_hash}{mpi_get_id} ],
                          $adone_mpi_get) ) {
      ++$ad;
    }
    else {
      $new_stmt->execute($row_ref->[$stmt->{NAME_lc_hash}{mpi_get_id} ],
                         $row_ref->[$stmt->{NAME_lc_hash}{mpi_name} ],
                         $row_ref->[$stmt->{NAME_lc_hash}{mpi_version} ]);
    }

    $i++;
  }

  # Make sure to update the sequence number
  system("psql -U iu -d mtt -c \"select setval('mpi_get_mpi_get_id_seq',(select max(mpi_get_id) from mpi_get))\"");

  printf("Inserted: %4d tuples (total = %4d [%5d])\n", $i, get_count($dbh_mtt3_new, "mpi_get"), $ad);

  $adone_mpi_get->finish;
}

########################
# permalinks
########################
sub copy_permalinks() {
  my $row_ref;
  my $new_stmt;
  my $count;
  my $i;
  my $prep_permalink;
  my $ad = 0;

  $count = get_count($dbh_mtt3, "permalinks"),

  $sql_cmd = "select * from permalinks";
  $stmt = $dbh_mtt3->prepare($sql_cmd);
  $stmt->execute();

  $new_stmt = $dbh_mtt3_new->prepare("INSERT into permalinks " .
                                     "(permalink_id, permalink, created)" .
                                     "VALUES (?,?,?)");

  $i = 0;
  while($row_ref = $stmt->fetchrow_arrayref ) {
    if( $i % 100 == 0) {
      printf("Inserting %4d of %4d [%5d]\n", $i, $count, $ad);
    }

    #
    # If this tuple is accounted for then skip it, ow add it new
    #
    if( 0 <= already_done($row_ref->[$stmt->{NAME_lc_hash}{permalink_id} ],
                          $adone_permalink) ) {
      ++$ad;
    }
    else {
      $prep_permalink = $row_ref->[$stmt->{NAME_lc_hash}{permalink} ];

      $new_stmt->execute($row_ref->[$stmt->{NAME_lc_hash}{permalink_id} ],
                         $prep_permalink,
                         $row_ref->[$stmt->{NAME_lc_hash}{created} ]);
    }

    $i++;
  }

  # Make sure to update the sequence number
  system("psql -U iu -d mtt -c \"select setval('permalinks_permalink_id_seq',(select max(permalink_id) from permalinks))\"");

  printf("Inserted: %4d tuples (total = %4d [%5d])\n", $i, get_count($dbh_mtt3_new, "permalinks"), $ad);

  $adone_permalink->finish;
}

########################
# compiler
########################
sub copy_compiler() {
  my $row_ref;
  my $new_stmt;
  my $count;
  my $i;
  my $ad = 0;

  $count = get_count($dbh_mtt3, "compiler"),

  $sql_cmd = "select * from compiler";
  $stmt = $dbh_mtt3->prepare($sql_cmd);
  $stmt->execute();

  $new_stmt = $dbh_mtt3_new->prepare("INSERT into compiler " .
                                     "(compiler_id, compiler_name, compiler_version)" .
                                     "VALUES (?,?,?)");

  $i = 0;
  while($row_ref = $stmt->fetchrow_arrayref ) {
    if( $i % 10 == 0) {
      printf("Inserting %4d of %4d [%5d]\n", $i, $count, $ad);
    }

    #
    # If this tuple is accounted for then skip it, ow add it new
    #
    if( 0 <= already_done($row_ref->[$stmt->{NAME_lc_hash}{compiler_id} ],
                          $adone_compiler) ) {
      ++$ad;
    }
    else {
      $new_stmt->execute($row_ref->[$stmt->{NAME_lc_hash}{compiler_id} ],
                         $row_ref->[$stmt->{NAME_lc_hash}{compiler_name} ],
                         $row_ref->[$stmt->{NAME_lc_hash}{compiler_version} ]);
    }

    $i++;
  }

  # Make sure to update the sequence number
  system("psql -U iu -d mtt -c \"select setval('compiler_compiler_id_seq',(select max(compiler_id) from compiler))\"");

  printf("Inserted: %4d tuples (total = %4d [%5d])\n", $i, get_count($dbh_mtt3_new, "compiler"), $ad);

  $adone_compiler->finish;
}

########################
# compute_cluster
########################
sub copy_compute_cluster() {
  my $row_ref;
  my $new_stmt;
  my $count;
  my $i;
  my $ad = 0;

  $count = get_count($dbh_mtt3, "compute_cluster"),

  $sql_cmd = "select * from compute_cluster";
  $stmt = $dbh_mtt3->prepare($sql_cmd);
  $stmt->execute();

  $new_stmt = $dbh_mtt3_new->prepare("INSERT into compute_cluster " .
                                     "(compute_cluster_id, platform_name, platform_hardware, platform_type, os_name, os_version)" .
                                     "VALUES (?,?,?,?,?,?)");

  $i = 0;
  while($row_ref = $stmt->fetchrow_arrayref ) {
    if( $count > 100  && $i % 10 == 0) {
      printf("Inserting %4d of %4d [%5d]\n", $i, $count, $ad);
    }

    #
    # If this tuple is accounted for then skip it, ow add it new
    #
    if( 0 <= already_done($row_ref->[$stmt->{NAME_lc_hash}{compute_cluster_id} ],
                          $adone_compute_cluster) ) {
      ++$ad;
    }
    else {
      $new_stmt->execute($row_ref->[$stmt->{NAME_lc_hash}{compute_cluster_id} ],
                         $row_ref->[$stmt->{NAME_lc_hash}{platform_name} ],
                         $row_ref->[$stmt->{NAME_lc_hash}{platform_hardware} ],
                         $row_ref->[$stmt->{NAME_lc_hash}{platform_type} ],
                         $row_ref->[$stmt->{NAME_lc_hash}{os_name} ],
                         $row_ref->[$stmt->{NAME_lc_hash}{os_version} ]);
    }
    $i++;
  }

  # Make sure to update the sequence number
  system("psql -U iu -d mtt -c \"select setval('compute_cluster_compute_cluster_id_seq',(select max(compute_cluster_id) from compute_cluster))\"");

  printf("Inserted: %4d tuples (total = %4d [%5d])\n", $i, get_count($dbh_mtt3_new, "compute_cluster"), $ad);

  $adone_compute_cluster->finish;
}

##########################
# Support Functions
##########################
sub already_done_tr() {
  my $value = shift(@_);
  my $row_ref;
  my $rtn_val = 1;

  $adone_tr_select->execute($value);
  while($row_ref = $adone_tr_select->fetchrow_arrayref ) {
    $rtn_val = 0;
    last;
  }

  return $rtn_val;
}

sub already_done_tb() {
  my $value = shift(@_);
  my $row_ref;
  my $rtn_val = 1;

  $adone_tb_select->execute($value);
  while($row_ref = $adone_tb_select->fetchrow_arrayref ) {
    $rtn_val = 0;
    last;
  }

  return $rtn_val;
}

sub already_done_mi() {
  my $value = shift(@_);
  my $row_ref;
  my $rtn_val = 1;

  $adone_mi_select->execute($value);
  while($row_ref = $adone_mi_select->fetchrow_arrayref ) {
    $rtn_val = 0;
    last;
  }

  return $rtn_val;
}

sub get_count() {
  my $dbh = shift(@_);
  my $table = shift(@_);
  my $val = -1;
  my $tmp_stmt;

  # Get the count first
  $sql_cmd = "select count(*) from " . $table;
  $tmp_stmt = $dbh->prepare($sql_cmd);
  $tmp_stmt->execute();

  while(@row = $tmp_stmt->fetchrow_array ) {
    $val = $row[0];
  }

  return $val;
}

sub get_num_tuples() {
  my $dbh = shift(@_);
  my $tmp_sql_cmd = shift(@_);
  my $val = -1;
  my $tmp_stmt;

  # Get the count first
  $tmp_stmt = $dbh->prepare($tmp_sql_cmd);
  $tmp_stmt->execute();

  $val = 0;
  while(@row = $tmp_stmt->fetchrow_array ) {
    $val++;
  }

  return $val;
}

sub get_last_insert() {
  my $dbh = shift(@_);
  my $table = shift(@_);
  my $val = -1;
  my $tmp_stmt;

  # Get the count first
  $sql_cmd = "select last_value from " . $table;
  $tmp_stmt = $dbh->prepare($sql_cmd);
  $tmp_stmt->execute();

  while(@row = $tmp_stmt->fetchrow_array ) {
    $val = $row[0];
  }

  return $val;
}

sub get_last_id() {
  my $dbh = shift(@_);
  my $table = shift(@_);
  my $idx = shift(@_);
  my $val = -1;
  my $tmp_stmt;

  $sql_cmd = "select max(".$idx.") from " . $table;
  $tmp_stmt = $dbh->prepare($sql_cmd);
  $tmp_stmt->execute();

  while(@row = $tmp_stmt->fetchrow_array ) {
    $val = $row[0] + 0;
  }

  return $val;
}

sub temp_id_translation() {
  my $new_id = shift(@_);
  my $old_id = shift(@_);
  my $result_id = shift(@_);
  my $table = shift(@_);
  my $val = -1;
  my $tmp_stmt;

  # Get the count first
  $sql_cmd = ("insert into " . $table . " VALUES (" .
              "'".$new_id."', '".$old_id."', '".$result_id."')");
  $tmp_stmt = $dbh_mtt3_new->prepare($sql_cmd);
  return $tmp_stmt->execute();
}

sub print_header() {
  my $str = shift(@_);

  print "\n";
  print $str . "\n";
  print "-"x40 . "\n";
}

sub already_done() {
  my $value   = shift(@_);
  my $ad_stmt = shift(@_);
  my $row;
  my $rtn_val = -1;

  $ad_stmt->execute($value);
  while($row = $ad_stmt->fetchrow_array ) {
    $rtn_val = $row[0];
    last;
  }

  return $rtn_val;
}
