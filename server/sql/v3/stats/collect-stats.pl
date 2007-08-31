#!/usr/bin/env perl

# UPDATE a row with invalid values :(

# Josh Hursey
#
# A script to be run periodically to collect stats on MTT submissions.
# The goal is to acquire contribution and coverage stats for easy
# reference.
#

use strict;
use DBI;
use Class::Struct;

# Flush I/O frequently
$| = 1;

my $replace_where_field       = "<REPLACE_WHERE>";
my $replace_insert_keys_field = "<REPLACE_INSERT_KEYS>";
my $replace_insert_vals_field = "<REPLACE_INSERT_VALS>";
my $replace_update_field      = "<REPLACE_UPDATE_SET>";
my $replace_update_id_field   = "<REPLACE_UPDATE_ID>";

my $v_nlt = "\n\t";
my $v_nl  = "\n";

#
# A single data item paired down to its essential values
#
struct Stat_Datum => {
                      name        => '$',
                      select_stmt => '$',
                      select_stmt_mi => '$',
                      select_stmt_tb => '$',
                      select_stmt_tr => '$',
                      select_stmt_stat => '$',
                      update_stmt => '$',
                      insert_keys => '$',
                      insert_vals => '$',
                     };

#
# A collection of arrays to store stat_data_items
#
my @all_orgs          = ();
my @all_platforms     = ();
my @all_os            = ();
my @all_mi_compilers  = ();
my @all_tb_compilers  = ();
my @all_mpi_gets      = ();
my @all_mi_configs    = ();
my @all_test_suites   = ();
my @all_launchers     = ();
my @all_resource_mgrs = ();
my @all_networks      = ();

#
# A reference to the current index into each of
# the data store arrays above;
#
my $cur_org           = -1;
my $cur_platform      = -1;
my $cur_os            = -1;
my $cur_mi_compiler   = -1;
my $cur_tb_compiler   = -1;
my $cur_mpi_get       = -1;
my $cur_mi_config     = -1;
my $cur_test_suite    = -1;
my $cur_launcher      = -1;
my $cur_resource_mgr  = -1;
my $cur_network       = -1;

#
# SQL Predefined Statement Holders
#
my $select_all_cmd_org;
my $select_all_cmd_platform;
my $select_all_cmd_os;
my $select_all_cmd_mi_compiler;
my $select_all_cmd_tb_compiler;
my $select_all_cmd_mpi_get;
my $select_all_cmd_mi_config;
my $select_all_cmd_test_suite;
my $select_all_cmd_launcher;
my $select_all_cmd_resource_mgr;
my $select_all_cmd_network;

my $select_agg_cmd_tests;
my $select_agg_cmd_params;
my $select_agg_cmd_mi_pf;
my $select_agg_cmd_tb_pf;
my $select_agg_cmd_tr_pfst;
my $select_agg_cmd_tr_perf;

my $select_stat_cmd;
my $insert_stat_cmd;
my $update_stat_cmd;

my $insert_stat_cmd_add_keys_mi =
  ("test_build_compiler_name,".$v_nlt.
   "test_build_compiler_version,".$v_nlt.
   "test_suite,".$v_nlt.
   "launcher,".$v_nlt.
   "resource_mgr,".$v_nlt.
   "network,".$v_nlt.
   "num_tests,".$v_nlt.
   "num_parameters,".$v_nlt.
   "num_test_build_pass,".$v_nlt.
   "num_test_build_fail,".$v_nlt.
   "num_test_run_pass,".$v_nlt.
   "num_test_run_fail,".$v_nlt.
   "num_test_run_skip,".$v_nlt.
   "num_test_run_timed,".$v_nlt.
   "num_test_run_perf"
);
my $insert_stat_cmd_add_vals_mi =
  ("'',".$v_nlt.
   "'',".$v_nlt.
   "'',".$v_nlt.
   "'',".$v_nlt.
   "'',".$v_nlt.
   "'',".$v_nlt.
   "0,".$v_nlt.
   "0,".$v_nlt.
   "0,".$v_nlt.
   "0,".$v_nlt.
   "0,".$v_nlt.
   "0,".$v_nlt.
   "0,".$v_nlt.
   "0,".$v_nlt.
   "0"
  );
my $update_stat_cmd_add_mi =
  ("test_build_compiler_name = '',".$v_nlt.
   "test_build_compiler_version = '',".$v_nlt.
   "test_suite = '',".$v_nlt.
   "launcher = '',".$v_nlt.
   "resource_mgr = '',".$v_nlt.
   "network = '',".$v_nlt.
   "num_tests = 0,".$v_nlt.
   "num_parameters = 0,".$v_nlt.
   "num_test_build_pass = 0,".$v_nlt.
   "num_test_build_fail = 0,".$v_nlt.
   "num_test_run_pass = 0,".$v_nlt.
   "num_test_run_fail = 0,".$v_nlt.
   "num_test_run_skip = 0,".$v_nlt.
   "num_test_run_timed = 0,".$v_nlt.
   "num_test_run_perf = 0"
);
undef($update_stat_cmd_add_mi); # JJH Don't actually need this, will case a bug.

my $insert_stat_cmd_add_keys_tb =
  ("launcher,".$v_nlt.
   "resource_mgr,".$v_nlt.
   "network,".$v_nlt.
   "num_tests,".$v_nlt.
   "num_parameters,".$v_nlt.
   "num_test_run_pass,".$v_nlt.
   "num_test_run_fail,".$v_nlt.
   "num_test_run_skip,".$v_nlt.
   "num_test_run_timed,".$v_nlt.
   "num_test_run_perf"
);
my $insert_stat_cmd_add_vals_tb =
  ("'',".$v_nlt.
   "'',".$v_nlt.
   "'',".$v_nlt.
   "0,".$v_nlt.
   "0,".$v_nlt.
   "0,".$v_nlt.
   "0,".$v_nlt.
   "0,".$v_nlt.
   "0,".$v_nlt.
   "0"
  );
my $update_stat_cmd_add_tb =
  ("launcher = '',".$v_nlt.
   "resource_mgr = '',".$v_nlt.
   "network = '',".$v_nlt.
   "num_tests = 0,".$v_nlt.
   "num_parameters = 0,".$v_nlt.
   "num_test_run_pass = 0,".$v_nlt.
   "num_test_run_fail = 0,".$v_nlt.
   "num_test_run_skip = 0,".$v_nlt.
   "num_test_run_timed = 0,".$v_nlt.
   "num_test_run_perf = 0"
);
$update_stat_cmd_add_tb = ""; # JJH Don't actually need this, will case a bug.

my $cur_stat_id = -1;
my $total_inserts = 0;
my $total_updates = 0;

#
# Predefined SQL placeholders for DB stats
#
my $db_select_num_tuples;
my $db_select_num_tuples_mi;
my $db_select_num_tuples_tb;
my $db_select_num_tuples_tr;
my $db_select_size;

my $db_submit_select;
my $db_submit_insert;
my $db_submit_update;


#
# Verbosity Level
#  0 = quiet
#  1 = Basic Timing Information
#  2 = All Timing Information
#  3 = 'Gathering' Info
#  4 = Level prints
#  5 = Max (SQL Stmts)
#
my $verbose = 0;

#
# Time segment parameters
#
my $is_day   = "t";
my $is_month = "f";
my $is_year  = "f";
my $past_n_time_segs = 0;
my $nth_time_seg     = 0;

#
# If collecting contribution or database stats
#
my $collect_contrib  = "t";
my $collect_database = "t";

#
# Parse any command line arguments
#
if( 0 != parse_cmd_line() ) {
  print_usage();
  exit -1;
}

#######
# Some programmatic defines
my $dbh_mtt;

my $progress_cur   = 0;
my $progress_upper = 0;

my %timer_start_val = ();
my %timer_end_val   = ();
my $month_start;
my $month_end;
my ($today, $yesterday);
my ($days_epoch, $months_epoch);

my $ACCUM_ALL = "all";
my $ACCUM_MI  = "mi";
my $ACCUM_TB  = "tb";
my $ACCUM_TR  = "tr";


if( $collect_database eq "t" ) {
  collect_database_stats();
}

if( $collect_contrib eq "t" ) {
  collect_contribution_stats();
}

exit 0;

sub collect_database_stats() {
  my %stat_values = ();
  my $cur_db_stat_id = 0;
  my $loc_update_args = "";
  my $loc_insert_keys_args = "";
  my $loc_insert_vals_args = "";

  #
  # Connect to the database
  #
  if( 0 != connect_db() ) {
    return -1;
  }

  #
  # Create query statements
  #
  sql_create_db_queries();

  start_timer('total');

  print_verbose(1, "-"x65 . "\n");
  print_verbose(1, "-"x6 . " Database Stats Collection: " . resolve_date("'now'")." "."-"x20 ."\n");

  #
  # Gather the stat data
  #
  $stat_values{'num_tuples'}    = sql_scalar_cmd($db_select_num_tuples, "");
  print_verbose(2, "Stat) Num Tuples    = ".$stat_values{'num_tuples'}."\n");
  $stat_values{'num_tuples_tr'} = sql_scalar_cmd($db_select_num_tuples_tr, "");
  print_verbose(2, "Stat) Num Tuples TR = ".$stat_values{'num_tuples_tr'}."\n");
  $stat_values{'num_tuples_tb'} = sql_scalar_cmd($db_select_num_tuples_tb, "");
  print_verbose(2, "Stat) Num Tuples TB = ".$stat_values{'num_tuples_tb'}."\n");
  $stat_values{'num_tuples_mi'} = sql_scalar_cmd($db_select_num_tuples_mi, "");
  print_verbose(2, "Stat) Num Tuples MI = ".$stat_values{'num_tuples_mi'}."\n");
  $stat_values{'db_size'}       = sql_scalar_cmd($db_select_size, "");
  print_verbose(2, "Stat) Database Size = ".$stat_values{'db_size'}."\n");
  #
  # Construct insert/update vals
  #
  $loc_insert_vals_args = ("'".$stat_values{'db_size'}."', $v_nlt".
                           "'".$stat_values{'num_tuples'}."', $v_nlt".
                           "'".$stat_values{'num_tuples_mi'}."', $v_nlt".
                           "'".$stat_values{'num_tuples_tb'}."', $v_nlt".
                           "'".$stat_values{'num_tuples_tr'}."'");
  $loc_update_args = ("size_db = ".               $stat_values{'db_size'}      .", ".$v_nlt.
                      "num_tuples = ".            $stat_values{'num_tuples'}   .", ".$v_nlt.
                      "num_tuples_mpi_install = ".$stat_values{'num_tuples_mi'}.", ".$v_nlt.
                      "num_tuples_test_build = ". $stat_values{'num_tuples_tb'}.", ".$v_nlt.
                      "num_tuples_test_run = ".   $stat_values{'num_tuples_tr'}." " .$v_nlt);

  #
  # Insert the stat.
  #
  $cur_db_stat_id = find_stat_tuple($db_submit_select, "");
  if( 0 <= $cur_db_stat_id ) {
    update_stat_tuple($db_submit_update,
                      $loc_update_args,
                      $cur_db_stat_id);
    print_verbose(5, "****UPDATED**** Current ID <$cur_db_stat_id>\n");
    print_verbose(5, "*"x60 . "\n");
  }
  else {
    $cur_db_stat_id = insert_stat_tuple($db_submit_insert,
                                        "",
                                        $loc_insert_vals_args);
    #
    # If insert didn't give us a valid ID, take a guess at it.
    #
    if( 0 > $cur_db_stat_id) {
      $cur_db_stat_id = find_stat_tuple($db_submit_select, "");
    }
    print_verbose(5, "****INSERTED**** Current ID <$cur_db_stat_id>\n");
    print_verbose(5, "*"x60 . "\n");
  }

  #
  # Detach from the database
  #
  disconnect_db();

  end_timer('total');
  print_verbose(1, "*"x65 . "\n");
  print_verbose(2, sprintf("Database Stats) All Finished:\t\t %s\n", display_timer('total')));

  return 0;
}

sub collect_contribution_stats() {
  #
  # Connect to the database
  #
  if( 0 != connect_db() ) {
    return -1;
  }

  #
  # Render time segments
  #
  my $time_24_cycle = " 21:00:00"; # 9 pm
  my $epoch = "2006-11-24 " . $time_24_cycle;
  ($today, $yesterday)         = get_times_today();
  ($days_epoch, $months_epoch) = get_times_epoch($epoch, $today);
  $today     = $today     . $time_24_cycle;
  $yesterday = $yesterday . $time_24_cycle;

  if(0 > $past_n_time_segs) {
    if(    $is_day   eq "t" ) { $past_n_time_segs = $days_epoch;   }
    elsif( $is_month eq "t" ) { $past_n_time_segs = $months_epoch; }
    else {
      print "ERROR: Unsupported. Must provide exact number of months/years in past\n";
      return -1;
    }
  }

  #
  # Create query statements
  #
  sql_create_queries();

  start_timer('total');

  #
  # Create a Stat_Datum to accumulate where clauses
  #
  my $accum_where_datum = Stat_Datum->new();

  $accum_where_datum->name("Bogus");
  $accum_where_datum->select_stmt("");
  $accum_where_datum->select_stmt_mi("");
  $accum_where_datum->select_stmt_tb("");
  $accum_where_datum->select_stmt_tr("");
  $accum_where_datum->select_stmt_stat("");
  $accum_where_datum->update_stmt("");
  $accum_where_datum->insert_keys("");
  $accum_where_datum->insert_vals("");

  my $last_datum = dup_datum($accum_where_datum);

  #######################
  # For each time segment
  #######################
  for($nth_time_seg = $past_n_time_segs; $nth_time_seg >= 0; --$nth_time_seg) {
    my ($start_seg, $end_seg, $where_sub) = get_segment($nth_time_seg);
    my ($start_stat_seg, $end_stat_seg, $where_stat_sub) = get_segment_stat($nth_time_seg);

    # Clear out the datum before starting again.
    $accum_where_datum = dup_datum($last_datum);
    $accum_where_datum->select_stmt(   $where_sub);
    $accum_where_datum->select_stmt_mi($where_sub);
    $accum_where_datum->select_stmt_tb($where_sub);
    $accum_where_datum->select_stmt_tr($where_sub);
    $accum_where_datum  = init_datum_stat($start_seg, $end_seg, $accum_where_datum);

    print_verbose(1, "-"x65 . "\n");
    print_verbose(1, "-"x20 . " " . resolve_date($start_seg)." - ".resolve_date($end_seg)." ". "-"x20 ."\n");

    start_timer('segment');
    ######################
    # Gather all Orgs
    ######################
    @all_orgs = gather_all_orgs($start_seg, $end_seg, $accum_where_datum);
    my $last_datum_org = dup_datum($accum_where_datum);
    for($cur_org = 0; $cur_org < scalar(@all_orgs); ++$cur_org) {
      # Clear out the datum before starting again.
      $accum_where_datum = dup_datum($last_datum_org);

      $accum_where_datum = append_datum_where($accum_where_datum,
                                              $ACCUM_ALL,
                                              $all_orgs[$cur_org]);

      print_verbose(1,  "Analyzing: ".$all_orgs[$cur_org]->name."\n");
      start_timer('org');
      ######################
      # Gather all Platforms
      ######################
      @all_platforms = gather_all_platforms($start_seg, $end_seg, $accum_where_datum);
      my $last_datum_platform = dup_datum($accum_where_datum);
      for($cur_platform = 0; $cur_platform < scalar(@all_platforms); ++$cur_platform) {
        # Clear out the datum before starting again.
        $accum_where_datum = dup_datum($last_datum_platform);
        $accum_where_datum = append_datum_where($accum_where_datum,
                                                $ACCUM_ALL,
                                                $all_platforms[$cur_platform]);

        print_verbose(2, "\tPlatform: ".$all_platforms[$cur_platform]->name."\n");
        start_timer('platform');
        ######################
        # Gather all OSs
        ######################
        @all_os = gather_all_os($start_seg, $end_seg, $accum_where_datum);
        my $last_datum_os = dup_datum($accum_where_datum);
        reset_progress_upper(0);
        for($cur_os = 0; $cur_os < scalar(@all_os); ++$cur_os) {
          $accum_where_datum = dup_datum($last_datum_os);
          $accum_where_datum = append_datum_where($accum_where_datum,
                                                  $ACCUM_ALL,
                                                  $all_os[$cur_os]);

          print_verbose(4, "\tOS: ".$all_os[$cur_os]->name."\n");
          ##################################
          # Gather all MPI Install Compilers
          ##################################
          @all_mi_compilers = gather_all_mi_compilers($start_seg, $end_seg, $accum_where_datum);
          my $last_datum_mi_compiler = dup_datum($accum_where_datum);
          for($cur_mi_compiler = 0; $cur_mi_compiler < scalar(@all_mi_compilers); ++$cur_mi_compiler) {
            $accum_where_datum = dup_datum($last_datum_mi_compiler);
            $accum_where_datum = append_datum_where($accum_where_datum,
                                                    $ACCUM_ALL,
                                                    $all_mi_compilers[$cur_mi_compiler]);

            print_verbose(4, "\tMPI In. Compiler: ".$all_mi_compilers[$cur_mi_compiler]->name."\n");
            ######################
            # Gather all MPI Gets
            ######################
            @all_mpi_gets = gather_all_mpi_gets($start_seg, $end_seg, $accum_where_datum);
            my $last_datum_mpi_get = dup_datum($accum_where_datum);
            for($cur_mpi_get = 0; $cur_mpi_get < scalar(@all_mpi_gets); ++$cur_mpi_get) {
              $accum_where_datum = dup_datum($last_datum_mpi_get);
              $accum_where_datum = append_datum_where($accum_where_datum,
                                                      $ACCUM_ALL,
                                                      $all_mpi_gets[$cur_mpi_get]);

              print_verbose(4, "\tMPI Get: ".$all_mpi_gets[$cur_mpi_get]->name."\n");
              #######################################
              # Gather all MPI Install Configurations
              #######################################
              @all_mi_configs = gather_all_mi_configs($start_seg, $end_seg, $accum_where_datum);
              my $last_datum_mi_config = dup_datum($accum_where_datum);
              # Setup Progress
              print_verbose(4, "Progress Update Values: ".
                            scalar(@all_os)." * ".
                            scalar(@all_mi_compilers)." * ".
                            scalar(@all_mpi_gets)." * ".
                            scalar(@all_mi_configs)."\n");
              set_progress_upper(scalar(@all_os) *
                                 scalar(@all_mi_compilers) *
                                 scalar(@all_mpi_gets) *
                                 scalar(@all_mi_configs));
              for($cur_mi_config = 0; $cur_mi_config < scalar(@all_mi_configs); ++$cur_mi_config) {
                $accum_where_datum = dup_datum($last_datum_mi_config);
                $accum_where_datum = append_datum_where($accum_where_datum,
                                                        $ACCUM_ALL,
                                                        $all_mi_configs[$cur_mi_config]);

                print_verbose(4, "\tMPI Config: ".$all_mi_configs[$cur_mi_config]->name."\n");

                #
                # Save MPI Install stat information
                #
                print_verbose(3,
                              sprintf("Gathering MI: %6s -- %10s -- %10s -- %5s\n",
                                      $all_os[$cur_os]->name,
                                      $all_mi_compilers[$cur_mi_compiler]->name,
                                      $all_mpi_gets[$cur_mpi_get]->name,
                                      $all_mi_configs[$cur_mi_config]->name) );
                my ($agg_mi_pass, $agg_mi_fail) =
                  gather_agg_mi_pf($accum_where_datum);
                $accum_where_datum = append_datum_where_keys($accum_where_datum,
                                                             $ACCUM_TR,
                                                             "num_mpi_install_pass",
                                                             $agg_mi_pass);
                $accum_where_datum = append_datum_where_keys($accum_where_datum,
                                                             $ACCUM_TR,
                                                             "num_mpi_install_fail",
                                                             $agg_mi_fail);
                #################################
                # Gather all Test Build Compilers
                #################################
                @all_tb_compilers = gather_all_tb_compilers($start_seg, $end_seg, $accum_where_datum);
                # If there are no test_build tuples for this mpi_install, save the mpi_install and move on
                $cur_stat_id = -1; # Force select
                if( 0 >= scalar(@all_tb_compilers) ) {
                  submit_stat($ACCUM_MI, $accum_where_datum);
                }
                my $last_datum_tb_compiler = dup_datum($accum_where_datum);
                for($cur_tb_compiler = 0; $cur_tb_compiler < scalar(@all_tb_compilers); ++$cur_tb_compiler) {
                  $accum_where_datum = dup_datum($last_datum_tb_compiler);
                  $accum_where_datum = append_datum_where($accum_where_datum,
                                                          $ACCUM_TB,
                                                          $all_tb_compilers[$cur_tb_compiler]);

                  print_verbose(4, "\tTest Build Compiler: ".$all_tb_compilers[$cur_tb_compiler]->name."\n");
                  ########################
                  # Gather all Test Suites
                  ########################
                  @all_test_suites = gather_all_test_suites($start_seg, $end_seg, $accum_where_datum);
                  my $last_datum_test_suite = dup_datum($accum_where_datum);
                  for($cur_test_suite = 0; $cur_test_suite < scalar(@all_test_suites); ++$cur_test_suite) {
                    $accum_where_datum = dup_datum($last_datum_test_suite);
                    $accum_where_datum = append_datum_where($accum_where_datum,
                                                            $ACCUM_TB,
                                                            $all_test_suites[$cur_test_suite]);

                    print_verbose(4, "\tTest Suite: [".$all_test_suites[$cur_test_suite]->name."]\n");
                    print_verbose(3, sprintf("Gathering TB: %6s -- %10s -- %10s -- %5s -- %10s -- %10s\n",
                                             $all_os[$cur_os]->name,
                                             $all_mi_compilers[$cur_mi_compiler]->name,
                                             $all_mpi_gets[$cur_mpi_get]->name,
                                             $all_mi_configs[$cur_mi_config]->name,
                                             $all_tb_compilers[$cur_tb_compiler]->name,
                                             $all_test_suites[$cur_test_suite]->name) );

                    my ($agg_tb_pass, $agg_tb_fail) =
                      gather_agg_tb_pf($accum_where_datum);
                    $accum_where_datum = append_datum_where_keys($accum_where_datum,
                                                                 $ACCUM_TR,
                                                                 "num_test_build_pass",
                                                                 $agg_tb_pass);
                    $accum_where_datum = append_datum_where_keys($accum_where_datum,
                                                                 $ACCUM_TR,
                                                                 "num_test_build_fail",
                                                                 $agg_tb_fail);
                    ######################
                    # Gather all Launchers
                    ######################
                    @all_launchers = gather_all_launchers($start_seg, $end_seg, $accum_where_datum);
                    my $last_datum_launcher = dup_datum($accum_where_datum);
                    # If there are no test_row tuples for this test_build, save the test_build and move on
                    $cur_stat_id = -1; # Force select
                    if( 0 >= scalar(@all_launchers) ) {
                      submit_stat($ACCUM_TB, $accum_where_datum);
                    }

                    for($cur_launcher = 0; $cur_launcher < scalar(@all_launchers); ++$cur_launcher) {
                      $accum_where_datum = dup_datum($last_datum_launcher);
                      $accum_where_datum = append_datum_where($accum_where_datum,
                                                              $ACCUM_TR,
                                                              $all_launchers[$cur_launcher]);

                      print_verbose(4, "\tLauncher: ".$all_launchers[$cur_launcher]->name."\n");
                      ##########################
                      # Gather all Resource Mgrs
                      ##########################
                      @all_resource_mgrs = gather_all_resource_mgrs($start_seg, $end_seg, $accum_where_datum);
                      my $last_datum_resource_mgr = dup_datum($accum_where_datum);
                      for($cur_resource_mgr = 0; $cur_resource_mgr < scalar(@all_resource_mgrs); ++$cur_resource_mgr) {
                        $accum_where_datum = dup_datum($last_datum_resource_mgr);
                        $accum_where_datum = append_datum_where($accum_where_datum,
                                                                $ACCUM_TR,
                                                                $all_resource_mgrs[$cur_resource_mgr]);

                        print_verbose(4, "\tResource Mgr.: ".$all_resource_mgrs[$cur_resource_mgr]->name."\n");
                        ######################
                        # Gather all Networks
                        ######################
                        @all_networks = gather_all_networks($start_seg, $end_seg, $accum_where_datum);
                        my $last_datum_network = dup_datum($accum_where_datum);
                        for($cur_network = 0; $cur_network < scalar(@all_networks); ++$cur_network) {
                          $accum_where_datum = dup_datum($last_datum_network);
                          $accum_where_datum = append_datum_where($accum_where_datum,
                                                                  $ACCUM_TR,
                                                                  $all_networks[$cur_network]);

                          print_verbose(4,  "\tNetwork: ".$all_networks[$cur_network]->name."\n");
                          print_verbose(3, sprintf("Gathering TR: %6s -- %10s -- %10s -- %5s -- %10s -- %10s -- %10s -- %2s -- %2s\n",
                                                   $all_os[$cur_os]->name,
                                                   $all_mi_compilers[$cur_mi_compiler]->name,
                                                   $all_mpi_gets[$cur_mpi_get]->name,
                                                   $all_mi_configs[$cur_mi_config]->name,
                                                   $all_tb_compilers[$cur_tb_compiler]->name,
                                                   $all_test_suites[$cur_test_suite]->name,
                                                   $all_launchers[$cur_launcher]->name,
                                                   $all_resource_mgrs[$cur_resource_mgr]->name,
                                                   $all_networks[$cur_network]->name) );

                          my $agg_tests   = gather_agg_tests( $accum_where_datum);
                          my $agg_params  = gather_agg_params($accum_where_datum);

                          my ($agg_tr_pass, $agg_tr_fail, $agg_tr_skip, $agg_tr_time) =
                            gather_agg_tr_pfst($accum_where_datum);

                          my $agg_tr_perf = gather_agg_tr_perf($accum_where_datum);

                          $accum_where_datum = append_datum_where_keys($accum_where_datum,
                                                                       $ACCUM_TR,
                                                                       "num_tests",
                                                                       $agg_tests);
                          $accum_where_datum = append_datum_where_keys($accum_where_datum,
                                                                       $ACCUM_TR,
                                                                       "num_parameters",
                                                                       $agg_params);
                          $accum_where_datum = append_datum_where_keys($accum_where_datum,
                                                                       $ACCUM_TR,
                                                                       "num_test_run_pass",
                                                                       $agg_tr_pass);
                          $accum_where_datum = append_datum_where_keys($accum_where_datum,
                                                                       $ACCUM_TR,
                                                                       "num_test_run_fail",
                                                                       $agg_tr_fail);
                          $accum_where_datum = append_datum_where_keys($accum_where_datum,
                                                                       $ACCUM_TR,
                                                                       "num_test_run_skip",
                                                                       $agg_tr_skip);
                          $accum_where_datum = append_datum_where_keys($accum_where_datum,
                                                                       $ACCUM_TR,
                                                                       "num_test_run_timed",
                                                                       $agg_tr_time);
                          $accum_where_datum = append_datum_where_keys($accum_where_datum,
                                                                       $ACCUM_TR,
                                                                       "num_test_run_perf",
                                                                       $agg_tr_perf);
                          $cur_stat_id = -1; # Force select
                          submit_stat($ACCUM_ALL, $accum_where_datum);
                        } # End Network
                      } # End Resource Mgrs
                    } # End Launchers
                    print_verbose(2,". ");
                  } # End Test Suites
                  print_verbose(2,"\n");
                } # End Test Build Compiler
                inc_progress();
              } # End MPI Install Configs
              if( 4 <= $verbose ) {
                print_progress("**");
              }
            } # End MPI Gets
          } # End MPI Install Compiler
        } # End OSs

        end_timer('platform');
        print_verbose(2, sprintf("\t <-> Finished Platform: (%s)\t %s\n",
                                 $all_platforms[$cur_platform]->name,
                                 display_timer('platform')));
        print_verbose(2, "\t"."-"x60 . "\n");
      } # End Platforms

      end_timer('org');
      print_verbose(2, sprintf(" <-> Finished Org.: (%s)\t\t %s\n",
                               $all_orgs[$cur_org]->name,
                               display_timer('org')));
    } # End Org

    end_timer('segment');
    print_verbose(1, "-"x20 . " " . resolve_date($start_seg)." - ".resolve_date($end_seg)." ". "-"x20 ."\n");
    print_verbose(1, sprintf("Finished Segment: [%s - %s]\t %s\n",
                             resolve_date($start_seg),
                             resolve_date($end_seg),
                             display_timer('segment')));
    print_verbose(2, "-"x65 . "\n");

  } # End Time segment

  end_timer('total');
  print_verbose(1, "*"x65 . "\n");
  print_verbose(2, sprintf("Contrib Stats) All Finished:\t\t %s\n", display_timer('total')));
  print_verbose(2, sprintf("DB Stats: %6d Inserts, %6d updates\n", $total_inserts, $total_updates));

  #
  # Detach from the database
  #
  disconnect_db();

  return 0;
}

sub reset_progress_upper() {
  $progress_upper = shift(@_);
  $progress_cur   = 0;
  start_timer('progress');
}

sub set_progress_upper() {
  my $tmp = shift(@_);

  if( $tmp > $progress_upper) {
    $progress_upper = $tmp;
  }
  else {
    print_verbose(4, " <**> Ignore update [$progress_cur] [$progress_upper => $tmp] <**>\n");
  }

  if( 4 <= $verbose ) {
    print_progress("  ");
  }
}

sub inc_progress() {
  my $perc;
  ++$progress_cur;

  $perc = (($progress_upper - $progress_cur)/($progress_upper))*100;
  if( $progress_cur >= $progress_upper ||
      $perc % 1 == 0 ) {
    print_progress("..");
  }
}
# JJH
sub print_progress() {
  my $loc_str = shift(@_);
  my $perc;

  $perc = (1.0-(($progress_upper - $progress_cur)/($progress_upper)))*100;

  end_timer('progress');

  print_verbose(2,
                sprintf("%sProgress (%2d/%2d = %3d % Complete) \t",
                        $loc_str,
                        $progress_cur,
                        $progress_upper,
                        $perc)
               );
  if($loc_str eq "  ") {
    print_verbose(2, sprintf("--------------------------------\n") );
  } else {
    print_verbose(2, sprintf("%s\n", display_timer('progress')) );
  }
}


sub print_verbose($$) {
  my $v   = shift(@_);
  my $str = shift(@_);

  if( $v <= $verbose ) {
    print $str;
  }

  return 0;
}

sub print_usage() {
  print "="x50 . "\n";
  print "Usage: ./collect-stats.pl [-day] [-month] [-year] [-past N] [-refresh] [-no-db] [-no-contrib] [-v LEVEL]\n";
  print "  Default: -day -past 0 -v 0\n";
  print "="x50 . "\n";

  return 0;
}

sub parse_cmd_line() {
  my $i = -1;
  my $argc = scalar(@ARGV);
  my $exit_value = 0;

  for($i = 0; $i < $argc; ++$i) {
    #
    # Gather Results for a single day (Default)
    #
    if( $ARGV[$i] eq "-day" ) {
      $is_day   = "t";
      $is_month = "f";
      $is_year  = "f";
    }
    #
    # Gather Results for a month
    #
    elsif( $ARGV[$i] eq "-month" ) {
      $is_day   = "f";
      $is_month = "t";
      $is_year  = "f";

      # XXX Currently Unsupported -- Well supported but terribly slow
      print "ERROR: Year aggregation is currently not supported!\n";
      $exit_value = -1;
    }
    #
    # Gather Results for a year
    #
    elsif( $ARGV[$i] eq "-year" ) {
      $is_day   = "f";
      $is_month = "f";
      $is_year  = "t";

      # XXX Currently Unsupported
      print "ERROR: Year aggregation is currently not supported!\n";
      $exit_value = -1;
    }
    #
    # Go back N segments in the past, and come to the current date
    # Good for refreshing small segments of the stats
    #
    elsif( $ARGV[$i] eq "-past" ) {
      $i++;
      if( $ARGV[$i] >= 0 ) {
        $past_n_time_segs = $ARGV[$i];
      }
    }
    #
    # Refresh from epoch - current date
    # Good for seeding the stats table, but will take a long time.
    #
    elsif( $ARGV[$i] eq "-refresh" ) {
      $past_n_time_segs = -1;
    }
    #
    # Do not collect database stats
    #
    elsif( $ARGV[$i] eq "-no-db" ) {
      $collect_database = "f";
    }
    #
    # Do not collect contribution stats
    #
    elsif( $ARGV[$i] eq "-no-contrib" ) {
      $collect_contrib  = "f";
    }
    #
    # Display usage information and exit
    #
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

sub start_timer() {
  my $ref = shift(@_);
  $timer_start_val{$ref} = time();
  return 0;
}

sub end_timer() {
  my $ref = shift(@_);
  $timer_end_val{$ref} = time();
  return 0;
}

sub display_timer() {
  my $ref = shift(@_);
  my $sec;
  my $min;
  my $hr;
  my $day;
  my $str;

  $sec = ( ($timer_end_val{$ref}) - ($timer_start_val{$ref}));
  $min = $sec / 60.0;
  $hr  = $min / 60.0;
  $day = $hr  / 24.0;

  $str = sprintf("(%6.2f min : %6.2f hr : %6.2f days : %10.1f sec)",
                 $min, $hr, $day, $sec);

  return $str;
}

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
  sql_destroy_queries();
  $dbh_mtt->disconnect;
  return 0;
}

sub sql_create_db_queries() {
  #
  # Number of tuples
  #
  $db_select_num_tuples =
    ("SELECT sum(csum) FROM (SELECT sum(count) as csum FROM ".
     "(SELECT count(*) as count FROM mpi_install) as a UNION ".
     "(SELECT count(*) as count FROM test_build) UNION ".
     "(SELECT count(*) as count FROM test_run)) as ab");
#    ("SELECT cast(sum(reltuples) as bigint) ".
#     "FROM pg_class ".
#     "WHERE relname ~* 'pkey' AND ".
#     "(relname ~* 'test_run' or relname ~* 'mpi_install' or relname ~* 'test_build')");

  #
  # Number of tuples (MPI Install)
  #
  $db_select_num_tuples_mi =
    ("SELECT count(*) as count ".
     "FROM mpi_install");
#    ("SELECT cast(sum(reltuples) as bigint) ".
#     "FROM pg_class ".
#     "WHERE relname ~* 'pkey' AND ".
#     "relname ~* 'mpi_install'");

  #
  # Number of tuples (Test Build)
  #
  $db_select_num_tuples_tb =
    ("SELECT count(*) as count ".
     "FROM test_build");
#    ("SELECT cast(sum(reltuples) as bigint) ".
#     "FROM pg_class ".
#     "WHERE relname ~* 'pkey' AND ".
#     "relname ~* 'test_build'");

  #
  # Number of tuples (Test Run)
  #
  $db_select_num_tuples_tr =
    ("SELECT count(*) as count ".
     "FROM mpi_install");
#    ("SELECT cast(sum(reltuples) as bigint) ".
#     "FROM pg_class ".
#     "WHERE relname ~* 'pkey' AND ".
#     "relname ~* 'test_run'");

  #
  # DB size in Bytes
  #
  $db_select_size =
    ("SELECT pg_database_size('mtt')");

  #
  # Select Existing DB Stat
  #
  $db_submit_select =
    ("SELECT mtt_stats_database_id ".
     "FROM mtt_stats_database ".
     "WHERE collection_date = DATE 'now'");

  #
  # Insert New DB stat
  #
  $db_submit_insert =
    ("INSERT into mtt_stats_database ".
     "(mtt_stats_database_id, ".
     " collection_date, ".
     " size_db, ".
     " num_tuples, ".
     " num_tuples_mpi_install, ".
     " num_tuples_test_build, ".
     " num_tuples_test_run) ".
     "VALUES (DEFAULT, DEFAULT,".$replace_insert_vals_field.")");

  #
  # Update an existing DB stat
  #
  $db_submit_update =
    ("UPDATE mtt_stats_database SET ".
     " ".$replace_update_field." ".$v_nl.
     " WHERE mtt_stats_database_id = ".$replace_update_id_field);

  return 0;
}

sub sql_create_queries() {
  #
  # Orgs
  #
  $select_all_cmd_org =
    ("SELECT distinct(http_username) ".$v_nl.
     "FROM  mpi_install NATURAL JOIN submit ".$v_nl.
     "WHERE ".$replace_where_field." AND ".$v_nl.
     "      http_username != '' AND ".$v_nl.
     "      http_username != 'bogus'");

  #
  # Platforms
  #
  $select_all_cmd_platform =
    ("SELECT distinct(platform_name) ".$v_nl.
     "FROM mpi_install NATURAL JOIN submit ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "WHERE ".$replace_where_field." ");

  #
  # OSs
  #
  $select_all_cmd_os =
    ("SELECT distinct(os_name) ".$v_nl.
     "FROM mpi_install NATURAL JOIN submit ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "WHERE ".$replace_where_field." ");

  #
  # MPI Install Compiler
  #
  $select_all_cmd_mi_compiler =
    ("SELECT distinct on (compiler_name,compiler_version) compiler_name, compiler_version ".$v_nl.
     "FROM mpi_install NATURAL JOIN submit ".$v_nl.
     "     JOIN compiler ON mpi_install.mpi_install_compiler_id = compiler.compiler_id ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "WHERE ".$replace_where_field." AND ".$v_nl.
     "       compiler_name != 'bogus'");

  #
  # MPI Get
  #
  $select_all_cmd_mpi_get =
    ("SELECT distinct on (mpi_name,mpi_version) mpi_name, mpi_version ".$v_nl.
     "FROM mpi_install NATURAL JOIN submit ".$v_nl.
     "     JOIN compiler ON mpi_install.mpi_install_compiler_id = compiler.compiler_id ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "     NATURAL JOIN mpi_get ".$v_nl.
     "WHERE ".$replace_where_field." ");

  #
  # MPI Install Configuration
  #
  $select_all_cmd_mi_config =
    ("SELECT distinct(mpi_install_configure_id) ".$v_nl.
     "FROM mpi_install NATURAL JOIN submit ".$v_nl.
     "     JOIN compiler ON mpi_install.mpi_install_compiler_id = compiler.compiler_id ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "     NATURAL JOIN mpi_get ".$v_nl.
     "     NATURAL JOIN mpi_install_configure_args ".$v_nl.
     "WHERE ".$replace_where_field." ");

  #
  # Aggregate MPI Install pass/fail
  #
  $select_agg_cmd_mi_pf =
    ("SELECT test_result, count(*) ".$v_nl.
     "FROM mpi_install NATURAL JOIN submit ".$v_nl.
     "     JOIN compiler ON mpi_install.mpi_install_compiler_id = compiler.compiler_id ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "     NATURAL JOIN mpi_get ".$v_nl.
     "     NATURAL JOIN mpi_install_configure_args ".$v_nl.
     "WHERE ".$replace_where_field." AND ".$v_nl.
     "      test_result >= 0 ".$v_nl.
     "GROUP BY test_result ".$v_nl.
     "ORDER BY test_result");


  #
  # Test Build Compiler
  #
  $select_all_cmd_tb_compiler =
    ("SELECT distinct on (compiler_name,compiler_version) compiler_name, compiler_version ".$v_nl.
     "FROM test_build NATURAL JOIN submit ".$v_nl.
     "     JOIN compiler ON test_build.test_build_compiler_id = compiler.compiler_id ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "     NATURAL JOIN mpi_get ".$v_nl.
     "     NATURAL JOIN mpi_install_configure_args ".$v_nl.
     "WHERE ".$replace_where_field." AND ".$v_nl.
     "       compiler_name != 'bogus'");


  #
  # Test Suites
  #
  $select_all_cmd_test_suite =
    ("SELECT distinct(suite_name) ".$v_nl.
     "FROM test_build NATURAL JOIN submit ".$v_nl.
     "     JOIN compiler ON test_build.test_build_compiler_id = compiler.compiler_id ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "     NATURAL JOIN mpi_get ".$v_nl.
     "     NATURAL JOIN mpi_install_configure_args ".$v_nl.
     "     NATURAL JOIN test_suites ".$v_nl.
     "WHERE ".$replace_where_field." ");

  #
  # Aggregate Test Build pass/fail
  #
  $select_agg_cmd_tb_pf =
    ("SELECT test_result, count(*) ".$v_nl.
     "FROM test_build NATURAL JOIN submit ".$v_nl.
     "     JOIN compiler ON test_build.test_build_compiler_id = compiler.compiler_id ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "     NATURAL JOIN mpi_get ".$v_nl.
     "     NATURAL JOIN mpi_install_configure_args ".$v_nl.
     "     NATURAL JOIN test_suites ".$v_nl.
     "WHERE ".$replace_where_field." AND ".$v_nl.
     "      test_result >= 0 ".$v_nl.
     "GROUP BY test_result ".$v_nl.
     "ORDER BY test_result");


  #
  # Launchers
  #
  $select_all_cmd_launcher =
    ("SELECT distinct(launcher) ".$v_nl.
     "FROM test_run NATURAL JOIN submit ".$v_nl.
     "     JOIN compiler ON test_run.mpi_install_compiler_id = compiler.compiler_id ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "     NATURAL JOIN mpi_get ".$v_nl.
     "     NATURAL JOIN mpi_install_configure_args ".$v_nl.
     "     NATURAL JOIN test_suites ".$v_nl.
     "     NATURAL JOIN test_run_command ".$v_nl.
     "WHERE ".$replace_where_field." ");

  #
  # Resource Managers
  #
  $select_all_cmd_resource_mgr =
    ("SELECT distinct(resource_mgr) ".$v_nl.
     "FROM test_run NATURAL JOIN submit ".$v_nl.
     "     JOIN compiler ON test_run.mpi_install_compiler_id = compiler.compiler_id ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "     NATURAL JOIN mpi_get ".$v_nl.
     "     NATURAL JOIN mpi_install_configure_args ".$v_nl.
     "     NATURAL JOIN test_suites ".$v_nl.
     "     NATURAL JOIN test_run_command ".$v_nl.
     "WHERE ".$replace_where_field." ");

  #
  # Networks
  #
  $select_all_cmd_network =
    ("SELECT distinct(network) ".$v_nl.
     "FROM test_run NATURAL JOIN submit ".$v_nl.
     "     JOIN compiler ON test_run.mpi_install_compiler_id = compiler.compiler_id ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "     NATURAL JOIN mpi_get ".$v_nl.
     "     NATURAL JOIN mpi_install_configure_args ".$v_nl.
     "     NATURAL JOIN test_suites ".$v_nl.
     "     NATURAL JOIN test_run_command ".$v_nl.
     "WHERE ".$replace_where_field." ");


  #
  # Aggregate # Distinct Tests
  #
  $select_agg_cmd_tests =
    ("SELECT count(distinct(test_name)) ".$v_nl.
     "FROM test_run NATURAL JOIN submit ".$v_nl.
     "     JOIN compiler ON test_run.mpi_install_compiler_id = compiler.compiler_id ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "     NATURAL JOIN mpi_get ".$v_nl.
     "     NATURAL JOIN mpi_install_configure_args ".$v_nl.
     "     NATURAL JOIN test_suites ".$v_nl.
     "     NATURAL JOIN test_run_command ".$v_nl.
     "     NATURAL JOIN test_names ".$v_nl.
     "WHERE ".$replace_where_field." ");

  #
  # Aggregate # Distinct Parameters
  #
  $select_agg_cmd_params =
    ("SELECT count(distinct(parameters)) ".$v_nl.
     "FROM test_run NATURAL JOIN submit ".$v_nl.
     "     JOIN compiler ON test_run.mpi_install_compiler_id = compiler.compiler_id ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "     NATURAL JOIN mpi_get ".$v_nl.
     "     NATURAL JOIN mpi_install_configure_args ".$v_nl.
     "     NATURAL JOIN test_suites ".$v_nl.
     "     NATURAL JOIN test_run_command ".$v_nl.
     "WHERE ".$replace_where_field." ");

  #
  # Aggregate Test Run pass/fail/skip/timed
  # test_result translation:
  # 0 = fail
  # 1 = pass
  # 2 = skipped
  # 3 = timed_out
  $select_agg_cmd_tr_pfst =
    ("SELECT test_result, count(*) ".$v_nl.
     "FROM test_run NATURAL JOIN submit ".$v_nl.
     "     JOIN compiler ON test_run.mpi_install_compiler_id = compiler.compiler_id ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "     NATURAL JOIN mpi_get ".$v_nl.
     "     NATURAL JOIN mpi_install_configure_args ".$v_nl.
     "     NATURAL JOIN test_suites ".$v_nl.
     "     NATURAL JOIN test_run_command ".$v_nl.
     "WHERE ".$replace_where_field." AND ".$v_nl.
     "      test_result >= 0 ".$v_nl.
     "GROUP BY test_result ".$v_nl.
     "ORDER BY test_result");

  #
  # Aggregate Test Run perf
  #
  $select_agg_cmd_tr_perf =
    ("SELECT count(performance_id) ".$v_nl.
     "FROM test_run NATURAL JOIN submit ".$v_nl.
     "     JOIN compiler ON test_run.mpi_install_compiler_id = compiler.compiler_id ".$v_nl.
     "     NATURAL JOIN compute_cluster ".$v_nl.
     "     NATURAL JOIN mpi_get ".$v_nl.
     "     NATURAL JOIN mpi_install_configure_args ".$v_nl.
     "     NATURAL JOIN test_suites ".$v_nl.
     "     NATURAL JOIN test_run_command ".$v_nl.
     "WHERE ".$replace_where_field." AND ".$v_nl.
     "      performance_id > 0 ");

  #
  # Select Existing Stat Tuple
  #
  $select_stat_cmd =
    ("SELECT mtt_stats_contrib_id ".$v_nl.
     "FROM mtt_stats_contrib ".$v_nl.
     "WHERE is_day = '$is_day' AND is_month = '$is_month' AND is_year = '$is_year' AND ".$v_nl.
     $replace_where_field."");

  #
  # Insert a new Stat Tuple
  #
  $insert_stat_cmd =
    ("INSERT INTO mtt_stats_contrib ".$v_nl.
     "(mtt_stats_contrib_id, is_day, is_month, is_year, ".$replace_insert_keys_field.") ".$v_nl.
     " VALUES ".$v_nl.
     "(DEFAULT, '$is_day', '$is_month', '$is_year', ".$replace_insert_vals_field.") ");

  #
  # Update existing stat tuple
  #
  $update_stat_cmd =
    ("UPDATE mtt_stats_contrib ".$v_nl.
     " SET ".$v_nl.
     " is_day = '$is_day', is_month = '$is_month', is_year = '$is_year', ".$v_nl.
     " ".$replace_update_field." ".$v_nl.
     " WHERE mtt_stats_contrib_id = ".$replace_update_id_field);

  return 0;
}

sub sql_destroy_queries() {
  ;
}

sub sql_scalar_cmd() {
  my $select = shift(@_);
  my $where  = shift(@_);
  my $rtn = 0;
  my $stmt;

  if( $select =~ /$replace_where_field/ ) {
    $select =~ s/$replace_where_field/$where/;
  }

  $stmt = $dbh_mtt->prepare($select);
  $rtn = sql_scalar_stmt($stmt);

  return $rtn;
}

sub sql_scalar_stmt() {
  my $stmt = shift(@_);
  my $rtn = 0;
  my @row;

  $stmt->execute();
  while(@row = $stmt->fetchrow_array ) {
    $rtn = $row[0];
  }

  $stmt->finish;

  return $rtn;
}

sub sql_1d_array_cmd($$) {
  my $select = shift(@_);
  my $where  = shift(@_);
  my $stmt;

  if( $select =~ /$replace_where_field/ ) {
    $select =~ s/$replace_where_field/$where/;
  }

  $stmt = $dbh_mtt->prepare($select);

  return sql_1d_array_stmt($stmt);
}

sub sql_1d_array_stmt($$) {
  my $stmt = shift(@_);
  my @rtn = ();
  my @row;

  $stmt->execute();
  while(@row = $stmt->fetchrow_array ) {
    push(@rtn, $row[0]);
  }

  $stmt->finish;

  return @rtn;
}

sub sql_2d_array_cmd($$) {
  my $select = shift(@_);
  my $where  = shift(@_);
  my $stmt;

  if( $select =~ /$replace_where_field/ ) {
    $select =~ s/$replace_where_field/$where/;
  }

  $stmt = $dbh_mtt->prepare($select);

  return sql_2d_array_stmt($stmt);
}

sub sql_2d_array_stmt($$) {
  my $stmt = shift(@_);
  my @rtn = ();
  my @accum = ();
  my @row;
  my $r;

  $stmt->execute();
  while(@row = $stmt->fetchrow_array ) {
    foreach $r (@row) {
      push(@rtn, $r);
    }
    push(@accum, @rtn);
  }

  $stmt->finish;

  return @accum;
}

sub resolve_date() {
  my $loc_date = shift(@_);
  my $r_date;
  my $cmd;
  my $stmt;
  my $row_ref;

  $cmd = ("SELECT DATE (DATE $loc_date) as resolv" );

  $stmt = $dbh_mtt->prepare($cmd);
  $stmt->execute();

  while($row_ref = $stmt->fetchrow_arrayref ) {
    $r_date = $row_ref->[$stmt->{NAME_lc_hash}{resolv}];
  }

  $stmt->finish;

  return $r_date;
}

sub get_times_today() {
  my $today_val;
  my $yesterday_val;

  my $cmd;
  my $stmt;
  my $row_ref;

  $cmd = ("SELECT ".
          "DATE 'now'       as today, ".
          "DATE 'yesterday' as yesterday ");

  $stmt = $dbh_mtt->prepare($cmd);
  $stmt->execute();

  while($row_ref = $stmt->fetchrow_arrayref ) {
    $today_val     = $row_ref->[$stmt->{NAME_lc_hash}{today}];
    $yesterday_val = $row_ref->[$stmt->{NAME_lc_hash}{yesterday}];
  }

  $stmt->finish;

  return ($today_val, $yesterday_val);
}

sub get_times_epoch() {
  my $loc_epoch = shift(@_);
  my $loc_today = shift(@_);
  my $num_days;
  my $num_months = 10; # JJH Hardcoded
  my $cmd;
  my $stmt;
  my $row_ref;

  $cmd = ("SELECT ".
          "DATE '".$loc_today."' - DATE '".$loc_epoch."' as epoch_days ");

  $stmt = $dbh_mtt->prepare($cmd);
  $stmt->execute();

  while($row_ref = $stmt->fetchrow_arrayref ) {
    $num_days  = $row_ref->[$stmt->{NAME_lc_hash}{epoch_days}];
  }

  $stmt->finish;

  return ($num_days, $num_months);
}

sub get_segment() {
  my $nth = shift(@_);
  my $s_date;
  my $e_date;
  my $where_c;

  if( $is_day eq "t" ) {
    $s_date = "'".$yesterday."' - interval '$nth_time_seg day'";
    $e_date = "'".$today    ."' - interval '$nth_time_seg day'";

    $where_c = ("start_timestamp >= TIMESTAMP ".$s_date." AND ".
                "start_timestamp <  TIMESTAMP ".$e_date."");
  }
  elsif( $is_month eq "t" ) {
    ($month_start, $month_end) = get_month_boundaries($nth_time_seg);
    $s_date = "'".$month_start."'";
    $e_date = "'".$month_end."'";

    $where_c = ("start_timestamp >= TIMESTAMP ".$s_date." AND ".
                "start_timestamp <= TIMESTAMP ".$e_date."");
  }
  else {
    print "ERROR: Unknown time interval\n";
    exit -1;
  }

  return ($s_date, $e_date, $where_c);
}

sub get_segment_stat() {
  my $nth = shift(@_);
  my $s_date;
  my $e_date;
  my $where_c;

  if( $is_day eq "t" ) {
    $s_date = "'".$yesterday."' - interval '$nth_time_seg day'";
    $e_date = "'".$today    ."' - interval '$nth_time_seg day'";

    $where_c = ("start_timestamp >= TIMESTAMP ".$s_date." AND ".
                "start_timestamp <  TIMESTAMP ".$e_date."");
  }
  elsif( $is_month eq "t" ) {
    ($month_start, $month_end) = get_month_boundaries($nth_time_seg);
    $s_date = "'".$month_start."'";
    $e_date = "'".$month_end."'";

    $where_c = ("collection_date >= DATE $s_date AND ".
                "collection_date <= DATE $e_date");
  }
  else {
    print "ERROR: Unknown time interval\n";
    exit -1;
  }

  return ($s_date, $e_date, $where_c);
}


sub get_month_boundaries() {
  my $months_ago = shift(@_);
  my $cur_month_start_val = `date +\"\%G-\%m-01\"`;
  my $month_start;
  my $month_end;

  my $cmd;
  my $stmt;
  my $row_ref;

  chomp($cur_month_start_val);

  # Dummy Check
  if( $months_ago < 0 ) {
    return (-1, -1);
  }
  # We have a better way to get the current month boundaries
  elsif( $months_ago == 0 ) {
    return get_cur_month_boundaries();
  }

  $cmd = ("SELECT ".
          "DATE (DATE '$cur_month_start_val' - interval '".($months_ago)    ." month') as month_start, ".
          "DATE (DATE '$cur_month_start_val' - interval '".($months_ago - 1)." month' - interval '1 day') as month_end"
         );

  $stmt = $dbh_mtt->prepare($cmd);
  $stmt->execute();

  while($row_ref = $stmt->fetchrow_arrayref ) {
    $month_start  = $row_ref->[$stmt->{NAME_lc_hash}{month_start}];
    $month_end    = $row_ref->[$stmt->{NAME_lc_hash}{month_end}];
  }

  $stmt->finish;

  return ($month_start, $month_end);
}

sub get_cur_month_boundaries() {
  my $month_start = `date +\"\%G-\%m-01\"`;
  my $month_end;
  my $cmd;
  my $stmt;
  my $row_ref;

  chomp($month_start);

  $cmd = ("SELECT ".
          "DATE (DATE '$month_start' + interval '1 month' - interval '1 day') as month_end ");

  $stmt = $dbh_mtt->prepare($cmd);
  $stmt->execute();

  while($row_ref = $stmt->fetchrow_arrayref ) {
    $month_end    = $row_ref->[$stmt->{NAME_lc_hash}{month_end}];
  }

  $stmt->finish;

  return ($month_start, $month_end);
}

sub gather_all_orgs() {
  my $start_seg = shift(@_);
  my $end_seg   = shift(@_);
  my $where_sub = shift(@_);
  my @loc_orgs = ();
  my @sql_rtn;
  my $n;
  my $datum;

  @sql_rtn = sql_1d_array_cmd($select_all_cmd_org, $where_sub->select_stmt);

  foreach $n (@sql_rtn) {
    $datum = Stat_Datum->new();

    $datum->name($n);
    $datum->select_stmt("submit.http_username = '$n'");
    $datum->select_stmt_stat("org_name = '$n'");
    $datum->update_stmt("org_name = '$n'");
    $datum->insert_keys("org_name");
    $datum->insert_vals("'$n'");

    push(@loc_orgs, $datum);
  }

  return @loc_orgs;
}

sub gather_all_platforms() {
  my $start_seg = shift(@_);
  my $end_seg   = shift(@_);
  my $where_sub = shift(@_);
  my @loc_platforms = ();

  my @sql_rtn;
  my $n;
  my $datum;

  @sql_rtn = sql_1d_array_cmd($select_all_cmd_platform, $where_sub->select_stmt);

  foreach $n (@sql_rtn) {
    $datum = Stat_Datum->new();

    $datum->name($n);
    $datum->select_stmt("compute_cluster.platform_name = '$n'");
    $datum->select_stmt_stat("platform_name = '$n'");
    $datum->update_stmt("platform_name = '$n'");
    $datum->insert_keys("platform_name");
    $datum->insert_vals("'$n'");

    push(@loc_platforms, $datum);
  }

  return @loc_platforms;
}

sub gather_all_os() {
  my $start_seg = shift(@_);
  my $end_seg   = shift(@_);
  my $where_sub = shift(@_);
  my @loc_os = ();

  my @sql_rtn;
  my $n;
  my $datum;

  @sql_rtn = sql_1d_array_cmd($select_all_cmd_os, $where_sub->select_stmt);

  foreach $n (@sql_rtn) {
    $datum = Stat_Datum->new();

    $datum->name($n);
    $datum->select_stmt("compute_cluster.os_name = '$n'");
    $datum->select_stmt_stat("os_name = '$n'");
    $datum->update_stmt("os_name = '$n'");
    $datum->insert_keys("os_name");
    $datum->insert_vals("'$n'");

    push(@loc_os, $datum);
  }

  return @loc_os;
}

sub gather_all_mi_compilers() {
  my $start_seg = shift(@_);
  my $end_seg   = shift(@_);
  my $where_sub = shift(@_);
  my @loc_mi_compilers = ();

  my @sql_rtn;
  my $r;
  my $datum;
  my $i = 0;
  my $name;
  my $version;

  @sql_rtn = sql_2d_array_cmd($select_all_cmd_mi_compiler, $where_sub->select_stmt);

  foreach $r (@sql_rtn) {
    ++$i;
    if( $i % 2 == 1 ) {
      $name = $r;
      next;
    }
    else {
      $version = $r;
    }

    $datum = Stat_Datum->new();

    $datum->name("$name ($version)");
    $datum->select_stmt("compiler_name = '$name' AND $v_nlt compiler_version = '$version'");
    $datum->select_stmt_stat("mpi_install_compiler_name = '$name' AND $v_nlt mpi_install_compiler_version = '$version'");
    $datum->update_stmt("mpi_install_compiler_name = '$name', $v_nlt mpi_install_compiler_version = '$version'");
    $datum->insert_keys("mpi_install_compiler_name, $v_nlt mpi_install_compiler_version");
    $datum->insert_vals("'$name', $v_nlt '$version'");

    push(@loc_mi_compilers, $datum);
  }

  return @loc_mi_compilers;
}

sub gather_all_tb_compilers() {
  my $start_seg = shift(@_);
  my $end_seg   = shift(@_);
  my $where_sub = shift(@_);
  my @loc_tb_compilers = ();

  my @sql_rtn;
  my $r;
  my $datum;
  my $i = 0;
  my $name;
  my $version;

  @sql_rtn = sql_2d_array_cmd($select_all_cmd_tb_compiler, $where_sub->select_stmt);

  foreach $r (@sql_rtn) {
    ++$i;
    if( $i % 2 == 1 ) {
      $name = $r;
      next;
    }
    else {
      $version = $r;
    }

    $datum = Stat_Datum->new();

    $datum->name("$name ($version)");
    $datum->select_stmt("compiler_name = '$name' AND $v_nlt compiler_version = '$version'");
    $datum->select_stmt_stat("test_build_compiler_name = '$name' AND $v_nlt test_build_compiler_version = '$version'");
    $datum->update_stmt("test_build_compiler_name = '$name', $v_nlt test_build_compiler_version = '$version'");
    $datum->insert_keys("test_build_compiler_name, $v_nlt test_build_compiler_version");
    $datum->insert_vals("'$name', '$version'");

    push(@loc_tb_compilers, $datum);
  }

  return @loc_tb_compilers;
}

sub gather_all_mpi_gets() {
  my $start_seg = shift(@_);
  my $end_seg   = shift(@_);
  my $where_sub = shift(@_);
  my @loc_mpi_gets = ();

  my @sql_rtn;
  my $r;
  my $datum;
  my $i = 0;
  my $name;
  my $version;

  @sql_rtn = sql_2d_array_cmd($select_all_cmd_mpi_get, $where_sub->select_stmt);

  foreach $r (@sql_rtn) {
    ++$i;
    if( $i % 2 == 1 ) {
      $name = $r;
      next;
    }
    else {
      $version = $r;
    }

    $datum = Stat_Datum->new();

    $datum->name("$name ($version)");
    $datum->select_stmt("mpi_name = '$name' AND $v_nlt mpi_version = '$version'");
    $datum->select_stmt_stat("mpi_get_name = '$name' AND $v_nlt mpi_get_version = '$version'");
    $datum->update_stmt("mpi_get_name = '$name', $v_nlt mpi_get_version = '$version'");
    $datum->insert_keys("mpi_get_name, $v_nlt mpi_get_version");
    $datum->insert_vals("'$name', '$version'");

    push(@loc_mpi_gets, $datum);
  }

  return @loc_mpi_gets;
}

sub gather_all_mi_configs() {
  my $start_seg = shift(@_);
  my $end_seg   = shift(@_);
  my $where_sub = shift(@_);
  my @loc_mi_configs = ();

  my @sql_rtn;
  my $n;
  my $datum;

  @sql_rtn = sql_1d_array_cmd($select_all_cmd_mi_config, $where_sub->select_stmt);

  foreach $n (@sql_rtn) {
    $datum = Stat_Datum->new();

    $datum->name($n);
    $datum->select_stmt("mpi_install_configure_id = '$n'");
    $datum->select_stmt_stat("mpi_install_config = '$n'");
    $datum->update_stmt("mpi_install_config = '$n'");
    $datum->insert_keys("mpi_install_config");
    $datum->insert_vals("'$n'");

    push(@loc_mi_configs, $datum);
  }

  return @loc_mi_configs;
}

sub gather_all_test_suites() {
  my $start_seg = shift(@_);
  my $end_seg   = shift(@_);
  my $where_sub = shift(@_);
  my @loc_test_suites = ();

  my @sql_rtn;
  my $n;
  my $datum;

  @sql_rtn = sql_1d_array_cmd($select_all_cmd_test_suite, $where_sub->select_stmt);

  foreach $n (@sql_rtn) {
    $datum = Stat_Datum->new();

    $datum->name($n);
    $datum->select_stmt("suite_name = '$n'");
    $datum->select_stmt_stat("test_suite = '$n'");
    $datum->update_stmt("test_suite = '$n'");
    $datum->insert_keys("test_suite");
    $datum->insert_vals("'$n'");

    push(@loc_test_suites, $datum);
  }

  return @loc_test_suites;
}

sub gather_all_launchers() {
  my $start_seg = shift(@_);
  my $end_seg   = shift(@_);
  my $where_sub = shift(@_);
  my @loc_launchers = ();

  my @sql_rtn;
  my $n;
  my $datum;

  @sql_rtn = sql_1d_array_cmd($select_all_cmd_launcher, $where_sub->select_stmt);

  foreach $n (@sql_rtn) {
    $datum = Stat_Datum->new();

    $datum->name($n);
    $datum->select_stmt("launcher = '$n'");
    $datum->select_stmt_stat("launcher = '$n'");
    $datum->update_stmt("launcher = '$n'");
    $datum->insert_keys("launcher");
    $datum->insert_vals("'$n'");

    push(@loc_launchers, $datum);
  }

  return @loc_launchers;
}

sub gather_all_resource_mgrs() {
  my $start_seg = shift(@_);
  my $end_seg   = shift(@_);
  my $where_sub = shift(@_);
  my @loc_resource_mgrs = ();

  my @sql_rtn;
  my $n;
  my $datum;

  @sql_rtn = sql_1d_array_cmd($select_all_cmd_resource_mgr, $where_sub->select_stmt);

  foreach $n (@sql_rtn) {
    $datum = Stat_Datum->new();

    $datum->name($n);
    $datum->select_stmt("resource_mgr = '$n'");
    $datum->select_stmt_stat("resource_mgr = '$n'");
    $datum->update_stmt("resource_mgr = '$n'");
    $datum->insert_keys("resource_mgr");
    $datum->insert_vals("'$n'");

    push(@loc_resource_mgrs, $datum);
  }

  return @loc_resource_mgrs;
}

sub gather_all_networks() {
  my $start_seg = shift(@_);
  my $end_seg   = shift(@_);
  my $where_sub = shift(@_);
  my @loc_networks = ();

  my @sql_rtn;
  my $n;
  my $datum;

  @sql_rtn = sql_1d_array_cmd($select_all_cmd_network, $where_sub->select_stmt);

  foreach $n (@sql_rtn) {
    $datum = Stat_Datum->new();

    $datum->name($n);
    $datum->select_stmt("network = '$n'");
    $datum->select_stmt_stat("network = '$n'");
    $datum->update_stmt("network = '$n'");
    $datum->insert_keys("network");
    $datum->insert_vals("'$n'");

    push(@loc_networks, $datum);
  }

  return @loc_networks;
}

sub gather_agg_tests() {
  my $where_sub = shift(@_);
  my $loc_accum = 0;

  my @sql_rtn;
  my $n;

  @sql_rtn = sql_1d_array_cmd($select_agg_cmd_tests, $where_sub->select_stmt);

  foreach $n (@sql_rtn) {
    $loc_accum = $n;
  }

  return $loc_accum;
}

sub gather_agg_params() {
  my $where_sub = shift(@_);
  my $loc_accum = 0;

  my @sql_rtn;
  my $n;

  @sql_rtn = sql_1d_array_cmd($select_agg_cmd_params, $where_sub->select_stmt);

  foreach $n (@sql_rtn) {
    $loc_accum = $n;
  }

  return $loc_accum;
}

sub gather_agg_mi_pf() {
  my $where_sub = shift(@_);
  my $loc_accum_pass = 0;
  my $loc_accum_fail = 0;

  my @sql_rtn;
  my $r;
  my $i = 0;
  my $idx;
  my $idx_val;

  @sql_rtn = sql_2d_array_cmd($select_agg_cmd_mi_pf, $where_sub->select_stmt);

  foreach $r (@sql_rtn) {
    ++$i;
    if( $i % 2 == 1 ) {
      $idx = $r;
      next;
    }
    else {
      $idx_val = $r;
    }

    # 0 = fail
    # 1 = pass
    if( $idx == 0 ) {
      $loc_accum_fail = $idx_val;
    }
    elsif( $idx == 1 ) {
      $loc_accum_pass = $idx_val;
    }
    else {
      print "ERROR: MI Unknown value [$idx] = $idx_val\n";
    }
  }

  return ($loc_accum_pass, $loc_accum_fail);
}

sub gather_agg_tb_pf() {
  my $where_sub = shift(@_);
  my $loc_accum_pass = 0;
  my $loc_accum_fail = 0;

  my @sql_rtn;
  my $r;
  my $i = 0;
  my $idx;
  my $idx_val;

  @sql_rtn = sql_2d_array_cmd($select_agg_cmd_tb_pf, $where_sub->select_stmt);

  foreach $r (@sql_rtn) {
    ++$i;
    if( $i % 2 == 1 ) {
      $idx = $r;
      next;
    }
    else {
      $idx_val = $r;
    }

    # 0 = fail
    # 1 = pass
    if( $idx == 0 ) {
      $loc_accum_fail = $idx_val;
    }
    elsif( $idx == 1 ) {
      $loc_accum_pass = $idx_val;
    }
    else {
      print "ERROR: TB Unknown value [$idx] = $idx_val\n";
    }
  }

  return ($loc_accum_pass, $loc_accum_fail);
}

sub gather_agg_tr_pfst() {
  my $where_sub = shift(@_);
  my $loc_accum_pass = 0;
  my $loc_accum_fail = 0;
  my $loc_accum_skip = 0;
  my $loc_accum_time = 0;

  my @sql_rtn;
  my $r;
  my $i = 0;
  my $idx;
  my $idx_val;

  @sql_rtn = sql_2d_array_cmd($select_agg_cmd_tr_pfst, $where_sub->select_stmt);

  foreach $r (@sql_rtn) {
    ++$i;
    if( $i % 2 == 1 ) {
      $idx = $r;
      next;
    }
    else {
      $idx_val = $r;
    }

    # 0 = fail
    # 1 = pass
    # 2 = skipped
    # 3 = timed_out
    if( $idx == 0 ) {
      $loc_accum_fail = $idx_val;
    }
    elsif( $idx == 1 ) {
      $loc_accum_pass = $idx_val;
    }
    elsif( $idx == 2 ) {
      $loc_accum_skip = $idx_val;
    }
    elsif( $idx == 3 ) {
      $loc_accum_time = $idx_val;
    }
    else {
      print "ERROR: TR Unknown value [$idx] = $idx_val\n";
    }
  }

  return ($loc_accum_pass, $loc_accum_fail,
          $loc_accum_skip, $loc_accum_time);
}

sub gather_agg_tr_perf() {
  my $where_sub = shift(@_);
  my $loc_accum = 0;

  my @sql_rtn;
  my $n;

  @sql_rtn = sql_1d_array_cmd($select_agg_cmd_tr_perf, $where_sub->select_stmt);

  foreach $n (@sql_rtn) {
    $loc_accum = $n;
  }

  return $loc_accum;
}

sub find_stat_tuple($$) {
  my $select_cmd = shift(@_);
  my $where_sub = shift(@_);
  my $loc_id = -1;

  my @sql_rtn;
  my $n;

  @sql_rtn = sql_1d_array_cmd($select_cmd, $where_sub);

  foreach $n (@sql_rtn) {
    $loc_id = $n;
  }

  if( $loc_id < 0 ) {
    print_verbose(5, "STAT TUPLE FIND: <$where_sub>\n");
  }

  return $loc_id;
}

sub update_stat_tuple($$$) {
  my $sql_update = shift(@_);
  my $update_sub = shift(@_);
  my $loc_id     = shift(@_);
  my $stmt;

  if( $sql_update =~ /$replace_update_field/ ) {
    $sql_update =~ s/$replace_update_field/$update_sub/;
  }
  if( $sql_update =~ /$replace_update_id_field/ ) {
    $sql_update =~ s/$replace_update_id_field/$loc_id/;
  }

  $stmt = $dbh_mtt->prepare($sql_update);
  $stmt->execute();

  $stmt->finish;

  print_verbose(5, "STAT TUPLE UPDATE:\n<$sql_update>\n");

  return $loc_id;
}

sub insert_stat_tuple($$$) {
  my $sql_insert      = shift(@_);
  my $insert_keys_sub = shift(@_);
  my $insert_vals_sub = shift(@_);
  my $loc_id = -1;
  my $stmt;

  if( $sql_insert =~ /$replace_insert_keys_field/ ) {
    $sql_insert =~ s/$replace_insert_keys_field/$insert_keys_sub/;
  }
  if( $sql_insert =~ /$replace_insert_vals_field/ ) {
    $sql_insert =~ s/$replace_insert_vals_field/$insert_vals_sub/;
  }

  $stmt = $dbh_mtt->prepare($sql_insert);
  $stmt->execute();

  $stmt->finish;

  print_verbose(5, "STAT TUPLE INSERT:\n<$sql_insert>\n");

  return $loc_id;
}

sub init_datum_stat() {
  my $start_seg = shift(@_);
  my $end_seg = shift(@_);
  my $accum_datum = shift(@_);

  $accum_datum->select_stmt_stat("collection_date = DATE $start_seg ");
  $accum_datum->update_stmt("collection_date = DATE $start_seg ");
  $accum_datum->insert_keys("collection_date ");
  $accum_datum->insert_vals("DATE $start_seg ");

  return $accum_datum;
}

sub append_datum_where() {
  my $cur_datum = shift(@_);
  my $accum_flag = shift(@_);
  my $select_datum = shift(@_);

  $cur_datum->select_stmt(   $cur_datum->select_stmt    . " AND ".$v_nlt. $select_datum->select_stmt);

  $cur_datum->select_stmt_stat($cur_datum->select_stmt_stat . " AND ".$v_nlt. $select_datum->select_stmt_stat);
  $cur_datum->update_stmt(   $cur_datum->update_stmt    . ",".$v_nlt. $select_datum->update_stmt);
  $cur_datum->insert_keys(   $cur_datum->insert_keys    . ",".$v_nlt. $select_datum->insert_keys);
  $cur_datum->insert_vals(   $cur_datum->insert_vals    . ",".$v_nlt. $select_datum->insert_vals);

  if( $accum_flag eq $ACCUM_ALL ) {
    $cur_datum->select_stmt_mi($cur_datum->select_stmt_mi . " AND ".$v_nlt. $select_datum->select_stmt);
    $cur_datum->select_stmt_tb($cur_datum->select_stmt_tb . " AND ".$v_nlt. $select_datum->select_stmt);
    $cur_datum->select_stmt_tr($cur_datum->select_stmt_tr . " AND ".$v_nlt. $select_datum->select_stmt);
  }
  elsif( $accum_flag eq $ACCUM_MI ) {
    $cur_datum->select_stmt_mi($cur_datum->select_stmt_mi . " AND ".$v_nlt. $select_datum->select_stmt);
    $cur_datum->select_stmt_tb($cur_datum->select_stmt_tb . " AND ".$v_nlt. $select_datum->select_stmt);
    $cur_datum->select_stmt_tr($cur_datum->select_stmt_tr . " AND ".$v_nlt. $select_datum->select_stmt);
  }
  elsif( $accum_flag eq $ACCUM_TB ) {
    #$cur_datum->select_stmt_mi($cur_datum->select_stmt_mi . " AND ".$v_nlt. $select_datum->select_stmt);
    $cur_datum->select_stmt_tb($cur_datum->select_stmt_tb . " AND ".$v_nlt. $select_datum->select_stmt);
    $cur_datum->select_stmt_tr($cur_datum->select_stmt_tr . " AND ".$v_nlt. $select_datum->select_stmt);
  }
  elsif( $accum_flag eq $ACCUM_TR ) {
    #$cur_datum->select_stmt_mi($cur_datum->select_stmt_mi . " AND ".$v_nlt. $select_datum->select_stmt);
    #$cur_datum->select_stmt_tb($cur_datum->select_stmt_tb . " AND ".$v_nlt. $select_datum->select_stmt);
    $cur_datum->select_stmt_tr($cur_datum->select_stmt_tr . " AND ".$v_nlt. $select_datum->select_stmt);
  }
  else {
    print "ERROR: Unknown accum flag <$accum_flag>\n";
    exit -1;
  }

  return $cur_datum;
}

sub append_datum_where_keys() {
  my $cur_datum = shift(@_);
  my $accum_flag = shift(@_);
  my $key = shift(@_);
  my $val = shift(@_);
  my $key_val_str;

  $val = "'".$val."'";
  $key_val_str = $key." = ".$val;

  #$cur_datum->select_stmt_stat($cur_datum->select_stmt_stat . " AND ". $key_val_str);

  $cur_datum->update_stmt(   $cur_datum->update_stmt    . ",".$v_nlt. $key_val_str);
  $cur_datum->insert_keys(   $cur_datum->insert_keys    . ",".$v_nlt. $key);
  $cur_datum->insert_vals(   $cur_datum->insert_vals    . ",".$v_nlt. $val);

  return $cur_datum;
}

sub dup_datum() {
  my $old_datum = shift(@_);
  my $new_datum;

  $new_datum = Stat_Datum->new();
  $new_datum->name($old_datum->name);
  $new_datum->select_stmt($old_datum->select_stmt);
  $new_datum->select_stmt_mi($old_datum->select_stmt_mi);
  $new_datum->select_stmt_tb($old_datum->select_stmt_tb);
  $new_datum->select_stmt_tr($old_datum->select_stmt_tr);
  $new_datum->select_stmt_stat($old_datum->select_stmt_stat);
  $new_datum->update_stmt($old_datum->update_stmt);
  $new_datum->insert_keys($old_datum->insert_keys);
  $new_datum->insert_vals($old_datum->insert_vals);

  return $new_datum;
}

sub submit_stat() {
  my $accum_flag = shift(@_);
  my $gathered_data = shift(@_);
  my $loc_select_args = "";
  my $loc_update_args = "";
  my $loc_insert_keys_args = "";
  my $loc_insert_vals_args = "";

  if( $accum_flag eq $ACCUM_ALL ) {
    # Same as Test Run
    $loc_select_args      = $gathered_data->select_stmt_stat;
    $loc_update_args      = $gathered_data->update_stmt;
    $loc_insert_keys_args = $gathered_data->insert_keys;
    $loc_insert_vals_args = $gathered_data->insert_vals;
  }
  elsif( $accum_flag eq $ACCUM_MI ) {
    $loc_select_args      = $gathered_data->select_stmt_stat;
    $loc_update_args      = $gathered_data->update_stmt;
    $loc_insert_keys_args = $gathered_data->insert_keys . ",".$v_nlt . $insert_stat_cmd_add_keys_mi;
    $loc_insert_vals_args = $gathered_data->insert_vals . ",".$v_nlt . $insert_stat_cmd_add_vals_mi;
  }
  elsif( $accum_flag eq $ACCUM_TB ) {
    $loc_select_args      = $gathered_data->select_stmt_stat;
    $loc_update_args      = $gathered_data->update_stmt;
    $loc_insert_keys_args = $gathered_data->insert_keys . ",".$v_nlt . $insert_stat_cmd_add_keys_tb;
    $loc_insert_vals_args = $gathered_data->insert_vals . ",".$v_nlt . $insert_stat_cmd_add_vals_tb;
  }
  elsif( $accum_flag eq $ACCUM_TR ) {
    $loc_select_args = $gathered_data->select_stmt_stat;
    $loc_update_args = $gathered_data->update_stmt;
    $loc_insert_keys_args = $gathered_data->insert_keys;
    $loc_insert_vals_args = $gathered_data->insert_vals;
  }
  else {
    print "ERROR: Unknown accum flag <$accum_flag> [submit_stat]\n";
    exit -1;
  }

  #
  # Save this last state
  #
  #
  # Select to see if we have already created a stat
  # If we have already established a stat_id then we can skip this step
  # and go straight to updating
  if( 0 > $cur_stat_id) {
    $cur_stat_id = find_stat_tuple($select_stat_cmd, $loc_select_args);
  }
  #
  # if a stat already exists then update it
  #
  if( 0 <= $cur_stat_id ) {
    update_stat_tuple($update_stat_cmd,
                      $loc_update_args,
                      $cur_stat_id);
    print_verbose(5, "****UPDATED**** Current ID <$cur_stat_id>\n");
    print_verbose(5, "*"x60 . "\n");
    ++$total_updates;
  }
  #
  # OW insert a new stat
  #
  else {
    $cur_stat_id = insert_stat_tuple($insert_stat_cmd,
                                     $loc_insert_keys_args,
                                     $loc_insert_vals_args);
    #
    # If insert didn't give us a valid ID, take a guess at it.
    #
    if( 0 > $cur_stat_id) {
      $cur_stat_id = find_stat_tuple($select_stat_cmd, $loc_select_args);
    }
    print_verbose(5, "****INSERTED**** Current ID <$cur_stat_id>\n");
    print_verbose(5, "*"x60 . "\n");
    ++$total_inserts;
  }

  return $cur_stat_id;
}

