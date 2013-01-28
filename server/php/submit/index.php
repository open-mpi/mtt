<?php
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2006-2007 Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2008      Mellanox Technologies.  All rights reserved.

#
#
# submit/index.php - 
#
# Parse results submitted by the MTT client.  MTT
# client submits results, one ini section at a time.
#
#

$topdir = "..";
if (file_exists("$topdir/config.inc")) {
    include_once("$topdir/config.inc");
}

# Note that Google Analytics is not performed here because the MTT
# client doesn't understand javascript to report back to GA.

# A large test run submission could overload the PHP 16MB limit
# (The following line increases the limit for this script only)
#ini_set("memory_limit", "32M");
# We were breaking even 32MB, so try 48 MB
#ini_set("memory_limit", "48M");
# We were breaking even 48MB, so try 64 MB
#ini_set("memory_limit", "64M");
# We were breaking even 64MB, so try 128 MB - Wow we are pretty good at this
#ini_set("memory_limit", "128M");
# We were breaking even 128MB, so try 256 MB - There has got to be a better way...
ini_set("memory_limit", "256M");

$topdir = '..';
include_once("$topdir/database.inc");
include_once("$topdir/reporter/reporter.inc");
include_once("$topdir/reporter/util.inc");
include_once("$topdir/common.inc");

date_default_timezone_set('America/New_York');

$GLOBALS['debug']   = isset($_POST['debug'])   ? $_POST['debug']   : 1;
$GLOBALS['verbose'] = isset($_POST['verbose']) ? $_POST['verbose'] : 1;
$dbname             = isset($_GET['db'])       ? $_GET['db']       : "mtt";
$pgsql_conn = null;

# Set php trace levels
if ($GLOBALS['verbose'])
    error_reporting(E_ALL);
else
    error_reporting(E_ERROR | E_WARNING | E_PARSE);
#    error_reporting((E_ERROR | E_WARNING | E_PARSE) & ~E_NOTICE);

#######################################
# Post: Ping
#######################################
# If the PING field is set, then this was just a
# test.  Exit successfully.
if (isset($_POST['PING'])) {
    print "Ping successful.\n";
    exit(0);
}

$marker = "===";

#######################################
# Post: Serial
#######################################
# If the SERIAL field is set, then the client just
# needs a serial.  Exit successfully.
if (isset($_POST['SERIAL'])) {
    print "\n$marker client_serial = " .  stringify(get_serial()) . " $marker\n";
    pg_close();
    exit(0);
}

#######################################
# Post: Data
#######################################
# The client will only submit one gzip file at a time for
# now. Initialize the _POST global with the uploaded gzip
# file contents. (There is backcompatibility here. E.g., if
# there is no uploaded file, then we assume its an
# oldfangled regular _POST submission)
define("undef", "");

if (sizeof($_FILES)) {
    $include_file = gunzip_file($_FILES['userfile']['tmp_name']);
    include_once($include_file);
    unlink($include_file);

    # If setup_post() is renamed, it must also be renamed in gunzip_file()
    setup_post();
}

# Uncomment to get a large dump of debug data
#debug_dump_data();

# Notify of fields that do not exist in the database
report_non_existent_fields();

# If these are not set, then exit.
if ((! isset($_POST['mtt_version_major']) or
     ! isset($_POST['mtt_version_minor'])) and
     ! isset($_POST['mtt_client_version'])) {
    mtt_abort(400, "\nMTT client version not specified.");
    exit(1);
}

# Who is submitting?  Note: PHP_AUTH_USER index is
# not set if .htaccess file is absent
$_POST['http_username'] =
        isset($_SERVER['PHP_AUTH_USER']) ?
        $_SERVER['PHP_AUTH_USER'] : "";
    
# Declare some global MTT database semantics
$id = "_id";

#
# Process Phase Data
#############################
# What phase are we doing?
$phase      = strtolower($_POST['phase']);
$phase_name = preg_replace('/^\s+|\s+$/', '', $phase);
$phase_name = preg_replace('/\s+/', '_', $phase);
$interconnect_id_hash = null;

print "\nMTT submission for $phase\n";

if (0 == strcasecmp($phase, "test run")) {

    $idx = process_phase($phase_name);

} else if (0 == strcasecmp($phase, "test build")) {

    $idx = process_phase($phase_name);

} else if (0 == strcasecmp($phase, "mpi install")) {

    $idx = process_phase($phase_name);

} else {
    print("ERROR: Unknown phase! ($phase)<br>\n");
    mtt_abort(400, "\nNo phase given, so I don't know which table to direct this data to.");
    exit(1);
}

#
# Return necessary indexes to the MTT client
#############################################
print("\n$marker $phase_name$id" . " = " . stringify($idx) . " $marker\n");

# All done
pg_close();
exit(0);

######################################################################

function process_phase($phase) {

    global $id;

    $results_idxs_hash = array();

    ########
    # Select/Insert: submit_id
    #
    # It is impossible to submit with two different submit identities
    # so grab the one and only submit_id
    # IF DISCONNECTED SCENARIOS COMES TO PASS, THIS WILL NEED 
    # TO BE CHANGED
    $stmt_fields = array("hostname",
                         "local_username",
                         "http_username",
                         "mtt_client_version");
    $stmt_values = array($_POST['hostname'],
                         $_POST['local_username'],
                         $_POST['http_username'],
                         $_POST['mtt_client_version'] );

    $results_idxs_hash['submit_id'] =
        select_insert("submit", "submit_id",
                      $stmt_fields, $stmt_values,
                      false);

    if (0 == strcasecmp($phase, "test_run")) {
        $idx = process_phase_test_run($results_idxs_hash);
    } else if (0 == strcasecmp($phase, "test_build")) {
        $idx = process_phase_test_build($results_idxs_hash);
    } else if (0 == strcasecmp($phase, "mpi_install")) {
        $idx = process_phase_mpi_install($results_idxs_hash);
    }
    else {
        mtt_error("Unknown Phase [$phase]\n");
    }

    return $idx;
}

function process_phase_test_run($results_idxs_hash) {
    $n = $_POST['number_of_results'];

    $error_function = "process_phase_test_run()";

    # JJH: Once all clients are really submitting test_run_command normalized
    # JJH: data then set this back to false so we warn the users. For now it
    # JJH: is just an annoying warning the user can do nothing about.
    #$print_once = false;
    $print_once = true;

    #
    # Do this instead of getting all of the columns passed
    # so we do not overload the memory space.
    $columns = array("environment",
                     "command",
                     "test_name",
                     "test_build_id",
                     "result_message",
                     "description",
                     "latency_bandwidth",
                     "message_size",
                     "latency_min",
                     "latency_avg",
                     "latency_max",
                     "bandwidth_min",
                     "bandwidth_avg",
                     "bandwidth_max",
                     "np",
                     "launcher",
                     "resource_manager",
                     "parameters",
                     "network",
                     "start_timestamp",
                     "test_result",
                     "trial",
                     "duration",
                     "result_stdout",
                     "result_stderr",
                     "merge_stdout_stderr",
                     "exit_value",
                     "exit_signal",
                     "client_serial");
    $param_set = get_post_values($columns);

    #######
    # A 'client_serial' is required, so check before moving forward
    if(!isset($param_set['client_serial']) ||
       0 == strlen($param_set['client_serial']) ||
       !preg_match("/^\d+$/", $param_set['client_serial'], $m) ) {
        $error_output  = ("CRITICAL ERROR: Cannot continue\n".
                          "-------------------------------\n".
                          "Invalid client_serial (".$param_set['client_serial'].") given.\n".
                          "-------------------------------\n");
        mtt_send_mail($error_output, $error_function);
        mtt_abort(400, $error_output);
        exit(1);
    }

    #######
    # Get the Test Build IDs
    $test_build_ids = get_test_build_ids($param_set['test_build_id']);

    foreach (array_keys($test_build_ids) as $k ) {
        if(!preg_match("/\d+$/", $k, $m) ) {
            $results_idxs_hash[$k] = $test_build_ids[$k];
        }
    }

    for($i = 0; $i < $n; $i++) {

        # The POST fields are enumerated starting at 1
        $j = $i + 1;

        ########
        # Select/Insert: performance
        # Currently only support latency/bandwidth
        # Assume that performance data is unique, so we do not have to search
        # for an existing tuple
        $results_idxs_hash['performance_id'] = 0;
        $index = "test_type_" . ($i + 1);
        if ((array_key_exists($index, $_POST) and
             $_POST[$index] == 'latency_bandwidth')) {
            #####
            # Insert Into Latency/Bandwidth
            $stmt_fields = array("message_size",
                                 "latency_min",
                                 "latency_avg",
                                 "latency_max",
                                 "bandwidth_min",
                                 "bandwidth_avg",
                                 "bandwidth_max");
            
            $stmt_values = array();
            for($f = 0; $f < count($stmt_fields); $f++) {
                $stmt_values[] = get_scalar($param_set[$stmt_fields[$f]], $i);
            }

            $results_idxs_hash['latency_bandwidth_id'] =
                select_insert("latency_bandwidth", "latency_bandwidth_id",
                              $stmt_fields, $stmt_values,
                              true);

            ####
            # Insert Into Performance
            $stmt_fields = array("latency_bandwidth_id");

            $stmt_values = array($results_idxs_hash['latency_bandwidth_id']);

            $results_idxs_hash['performance_id'] =
                select_insert("performance", "performance_id",
                              $stmt_fields, $stmt_values,
                              true);
        }

        ########
        # Select/Insert: test_command
        #
        # Examples:
        # launcher         = 'mpirun'
        # resource_manager = 'slurm'
        # parameters       = '-mca foo bar -mca zip zaz'
        # network          = 'loopback,shmem,tcp'
        # Only process these parameters if they are all provided by the client.
        $results_idxs_hash['test_run_command_id'] = 0;
        if(!is_sql_key_word(get_scalar($param_set['launcher'], $i)) &&
           !is_sql_key_word(get_scalar($param_set['resource_manager'], $i)) &&
           !is_sql_key_word(get_scalar($param_set['parameters'], $i)) &&
           !is_sql_key_word(get_scalar($param_set['network'], $i)) ) {
            #
            # Process the networks parameter
            #
            $results_idxs_hash['test_run_network_id'] =
                process_networks(get_scalar($param_set['network'], $i));

            # 
            # Now select/insert a test_run_command
            #
            $stmt_fields = array("launcher",
                                 "resource_mgr",
                                 "parameters",
                                 "network",
                                 "test_run_network_id");

            $stmt_values = array(get_scalar($param_set['launcher'], $i),
                                 get_scalar($param_set['resource_manager'], $i),
                                 get_scalar($param_set['parameters'], $i),
                                 get_scalar($param_set['network'], $i),
                                 $results_idxs_hash['test_run_network_id']);

            $results_idxs_hash['test_run_command_id'] = 
                select_insert("test_run_command", "test_run_command_id",
                              $stmt_fields, $stmt_values,
                              false);
        }
        else if(!$print_once) {
            mtt_notice("The submitting client did not submit valid IDs for one or more of the following\n".
                       "'launcher', 'resource_manager', 'paramters' or 'network'");
            $print_once = true;
        }

        ########
        # Select/Insert: test_names
        $stmt_fields = array("test_suite_id",
                             "test_name",
                             "test_name_description");
        $stmt_values = array($results_idxs_hash['test_suite_id'],
                             get_scalar($param_set['test_name'], $i),
                             "DEFAULT");

        $results_idxs_hash['test_name_id'] = 
            select_insert("test_names", "test_name_id",
                          $stmt_fields, $stmt_values,
                          false);

        #########
        # Select/Insert: Description (Test Run)
        $results_idxs_hash['description_id'] = 0;
        if( !is_sql_key_word(get_scalar($param_set['description'], $i)) ) {
            $stmt_fields = array("description");
            $stmt_values = array(get_scalar($param_set['description'], $i));

            $results_idxs_hash['description_id'] = 
                select_insert("description", "description_id",
                              $stmt_fields, $stmt_values,
                              false);
        }

        #########
        # Select/Insert: Result Message
        $stmt_fields = array("result_message");

        $stmt_values = array(get_scalar($param_set['result_message'], $i) );

        $results_idxs_hash['result_message_id'] =
            select_insert("result_message", "result_message_id",
                          $stmt_fields, $stmt_values,
                          false);

        #########
        # Select/Insert: Environment
        $results_idxs_hash['environment_id'] = 0;
        if( isset($_POST["environment_$j"]) ) {
            $stmt_fields = array("environment");

            $stmt_values = array(get_scalar($param_set['environment'], $i) );

            $results_idxs_hash['environment_id'] =
                select_insert("environment", "environment_id",
                              $stmt_fields, $stmt_values,
                              false);
        }

        #########
        # Insert: Result for Test Run
        $stmt_fields = array("submit_id",
                             "compute_cluster_id",
                             "mpi_install_compiler_id",
                             "mpi_get_id",
                             "mpi_install_configure_id",
                             "mpi_install_id",
                             "test_suite_id",
                             "test_build_compiler_id",
                             "test_build_id",
                             "test_name_id",
                             "performance_id",
                             "test_run_command_id",
                             "np",
                             "full_command",
                             "description_id",
                             "start_timestamp",
                             "test_result",
                             "trial",
                             "submit_timestamp",
                             "duration",
                             "environment_id",
                             "result_stdout",
                             "result_stderr",
                             "result_message_id",
                             "merge_stdout_stderr",
                             "exit_value",
                             "exit_signal",
                             "client_serial");
        
        $stmt_values = array($results_idxs_hash['submit_id'],
                             $results_idxs_hash['compute_cluster_id'],
                             $results_idxs_hash['mpi_install_compiler_id'],
                             $results_idxs_hash['mpi_get_id'],
                             $results_idxs_hash['mpi_install_configure_id'],
                             $results_idxs_hash['mpi_install_id'],
                             $results_idxs_hash['test_suite_id'],
                             $results_idxs_hash['test_build_compiler_id'],
                             $results_idxs_hash['test_build_id'],
                             $results_idxs_hash['test_name_id'],
                             $results_idxs_hash['performance_id'],
                             $results_idxs_hash['test_run_command_id'],
                             get_scalar($param_set['np'], $i),
                             get_scalar($param_set['command'], $i),
                             $results_idxs_hash['description_id'],
                             get_scalar($param_set['start_timestamp'], $i),
                             get_scalar($param_set['test_result'], $i),
                             get_scalar($param_set['trial'], $i),
                             "DEFAULT",
                             get_scalar($param_set['duration'], $i),
                             $results_idxs_hash['environment_id'],
                             get_scalar($param_set['result_stdout'], $i),
                             get_scalar($param_set['result_stderr'], $i),
                             $results_idxs_hash['result_message_id'],
                             convert_bool(get_scalar($param_set['merge_stdout_stderr'], $i)),
                             get_scalar($param_set['exit_value'], $i),
                             get_scalar($param_set['exit_signal'], $i),
                             get_scalar($param_set['client_serial'], $i)
                             );
        
        $test_run_id =
            select_insert("test_run", "test_run_id",
                          $stmt_fields, $stmt_values,
                          true);
        
        debug("*** Test Run Id [$test_run_id]\n");
    }


    return $test_run_id;
}

function process_networks($network_full_param) {
    global $interconnect_id_hash;

    $error_function = "process_networks(".$network_full_param.")";

    $nl  = "\n";
    $nlt = "\n\t";

    $test_run_network_id = 0;
    $loc_id_hash = null;
    $rtn_insert = null;

    #
    # Split the network CSV, and generate interconnect_ids for each value
    #
    $networks = preg_split('/,/', $network_full_param);
    if( 0 >= count($networks) ) {
        return $$test_run_network_id;
    }

    foreach( array_keys($networks) as $n) {
        $stmt_fields = array();
        $stmt_values = array();

        $key = $networks[$n];

        #
        # Select/Insert network if we haven't already cached the ID
        #
        if(!isset($interconnect_id_hash[$key]) ) {
            $stmt_fields = array("interconnect_name");
            $stmt_values = array($key);
            $interconnect_id_hash[$key] =
                select_insert("interconnects", "interconnect_id",
                              $stmt_fields, $stmt_values,
                              false);
        }

        $loc_id_hash[$key] = $interconnect_id_hash[$key];
    }

    #
    # Determine if we have established this network combination yet
    #
    $select_stmt = ("SELECT test_run_network_id $nl".
                "FROM test_run_networks $nl".
                "GROUP BY test_run_network_id $nl".
                "HAVING count(interconnect_id) = ".count($loc_id_hash)." ");
    foreach( array_keys($loc_id_hash) as $n ) {
        $select_stmt .= ($nlt."INTERSECT $nlt".
                     "(SELECT test_run_network_id $nlt".
                     " FROM test_run_networks $nlt".
                     " WHERE interconnect_id = ".$loc_id_hash[$n].")");
    }
    $select_stmt .= $nl . "LIMIT 1";

    #
    # if not then obtain a new test_run_network_id and insert it
    #
    $test_run_network_id = select_scalar($select_stmt);
    if(!isset($test_run_network_id) ) {
        $test_run_network_id = fetch_single_nextval("test_run_network_id");

        foreach( array_keys($loc_id_hash) as $n ) {
            $insert_stmt = ("INSERT INTO test_run_networks VALUES $nl".
                            "(DEFAULT, ".$test_run_network_id.", ".$loc_id_hash[$n].")");
            $rtn_insert = do_pg_query($insert_stmt, false);
            # JJH: Do we really need to do error checking here? I don't think this will ever fail.
            if( !$rtn_insert ) {
                $error_output = ("WARNING: Failed to insert the network parameters.\n".
                                 "---------------------------------\n".
                                 "Failed to insert the following:\n".
                                 $insert_stmt."\n".
                                 "---------------------------------\n".
                                 "Insert resulted from failed SELECT below:\n".
                                 $select_stmt."\n".
                                 "---------------------------------\n");
                mtt_send_mail($error_output, $error_function);
            }
        }
    }

    #
    # Return the test_run_network_id generated
    #
    return $test_run_network_id;
}

function process_phase_test_build($results_idxs_hash) {
    $n = $_POST['number_of_results'];

    $error_function = "process_phase_test_build()";

    #
    # Do this instead of getting all of the columns passed
    # so we don't overload the memory space.
    $columns = array("mpi_install_id",
                     "compiler_name",
                     "compiler_version",
                     "suite_name",
                     "result_message",
                     "description",
                     "environment",
                     "start_timestamp",
                     "test_result",
                     "trial",
                     "duration",
                     "result_stdout",
                     "result_stderr",
                     "merge_stdout_stderr",
                     "exit_value",
                     "exit_signal",
                     "client_serial");
    $param_set = get_post_values($columns);

    #######
    # A 'client_serial' is required, so check before moving forward
    if(!isset($param_set['client_serial']) ||
       0 == strlen($param_set['client_serial']) ||
       !preg_match("/^\d+$/", $param_set['client_serial'], $m) ) {
        $error_output  = ("CRITICAL ERROR: Cannot continue\n".
                          "-------------------------------\n".
                          "Invalid client_serial (".$param_set['client_serial'].") given.\n".
                          "-------------------------------\n");
        mtt_send_mail($error_output, $error_function);
        mtt_abort(400, $error_output);
        exit(1);
    }

    #######
    # Get the MPI Install IDs
    $mpi_install_ids = get_mpi_install_ids($param_set['mpi_install_id']);
    foreach (array_keys($mpi_install_ids) as $k ) {
        if(!preg_match("/\d+$/", $k, $m) ) {
            $results_idxs_hash[$k] = $mpi_install_ids[$k];
        }
    }

    for($i = 0; $i < $n; $i++) {
        
        # The POST fields are enumerated starting at 1
        $j = $i + 1;

        ########
        # Select/Insert: test_build_compiler -> compiler
        # Error out if the client did not supply a compiler,
        # as DEFAULT is meaningless here
        $stmt_fields = array("compiler_name",
                             "compiler_version");
        $stmt_values = array();
        for($f = 0; $f < count($stmt_fields); $f++) {
            if(0 == strcasecmp(get_scalar($param_set[$stmt_fields[$f]], $i), "DEFAULT") ) {
               mtt_error("ERROR: No compiler reported which is required for test_build submits ".
                         "[field '".$stmt_fields[$f]."' empty]\n");
               mtt_abort(400, "\nNo compiler supplied for test_build submit. ".
                              "[field '".$stmt_fields[$f]."' empty]");
               exit(1);
            }
            $stmt_values[] = get_scalar($param_set[$stmt_fields[$f]], $i);
        }

        $results_idxs_hash['test_build_compiler_id'] = 
            select_insert("compiler", "compiler_id",
                          $stmt_fields, $stmt_values,
                          false);
        ########
        # Select/Insert: test_suites
        $stmt_fields = array("suite_name",
                             "test_suite_description");
        $stmt_values = array(get_scalar($param_set['suite_name'], $i),
                             "DEFAULT");

        $results_idxs_hash['test_suite_id'] = 
            select_insert("test_suites", "test_suite_id",
                          $stmt_fields, $stmt_values,
                          false);

        #########
        # Select/Insert: Description (Test Build)
        $results_idxs_hash['description_id'] = 0;
        if( !is_sql_key_word(get_scalar($param_set['description'], $i)) ) {
            $stmt_fields = array("description");
            $stmt_values = array(get_scalar($param_set['description'], $i));

            $results_idxs_hash['description_id'] = 
                select_insert("description", "description_id",
                              $stmt_fields, $stmt_values,
                              false);
        }

        #########
        # Select/Insert: Result Message
        $stmt_fields = array("result_message");

        $stmt_values = array(get_scalar($param_set['result_message'], $i) );

        $results_idxs_hash['result_message_id'] =
            select_insert("result_message", "result_message_id",
                          $stmt_fields, $stmt_values,
                          false);

        #########
        # Select/Insert: Environment
        $results_idxs_hash['environment_id'] = 0;

        if( isset($_POST["environment_$j"]) ) {
            $stmt_fields = array("environment");

            $stmt_values = array(get_scalar($param_set['environment'], $i) );

            $results_idxs_hash['environment_id'] =
                select_insert("environment", "environment_id",
                              $stmt_fields, $stmt_values,
                              false);
        }


        #########
        # Insert: Result for MPI Install
        $stmt_fields = array("submit_id",
                             "compute_cluster_id",
                             "mpi_install_compiler_id",
                             "mpi_get_id",
                             "mpi_install_configure_id",
                             "mpi_install_id",
                             "test_suite_id",
                             "test_build_compiler_id",
                             "description_id",
                             "start_timestamp",
                             "test_result",
                             "trial",
                             "submit_timestamp",
                             "duration",
                             "environment_id",
                             "result_stdout",
                             "result_stderr",
                             "result_message_id",
                             "merge_stdout_stderr",
                             "exit_value",
                             "exit_signal",
                             "client_serial");

        $stmt_values = array($results_idxs_hash['submit_id'],
                             $results_idxs_hash['compute_cluster_id'],
                             $results_idxs_hash['mpi_install_compiler_id'],
                             $results_idxs_hash['mpi_get_id'],
                             $results_idxs_hash['mpi_install_configure_id'],
                             $results_idxs_hash['mpi_install_id'],
                             $results_idxs_hash['test_suite_id'],
                             $results_idxs_hash['test_build_compiler_id'],
                             $results_idxs_hash['description_id'],
                             get_scalar($param_set['start_timestamp'], $i),
                             get_scalar($param_set['test_result'], $i),
                             get_scalar($param_set['trial'], $i),
                             "DEFAULT",
                             get_scalar($param_set['duration'], $i),
                             $results_idxs_hash['environment_id'],
                             get_scalar($param_set['result_stdout'], $i),
                             get_scalar($param_set['result_stderr'], $i),
                             $results_idxs_hash['result_message_id'],
                             convert_bool(get_scalar($param_set['merge_stdout_stderr'], $i)),
                             get_scalar($param_set['exit_value'], $i),
                             get_scalar($param_set['exit_signal'], $i),
                             get_scalar($param_set['client_serial'], $i)
                             );
        
        $test_build_id =
            select_insert("test_build", "test_build_id",
                          $stmt_fields, $stmt_values,
                          true);

        debug("*** Test Build Id [$test_build_id]\n");
    }

    return $test_build_id;
}

function get_test_build_ids($test_build_id) {
    $error_function = "get_test_build_ids(".$test_build_id.")";

    $nl  = "\n";
    $nlt = "\n\t";
    $error_output = "";
    $test_build_ids = null;

    $orig_test_build_id = $test_build_id;

    ###############
    # First check if this is a valid test_build_id
    # If not then we give it '0', and insert it so no data is lost
    if(!isset($test_build_id) ||
       0 == strlen($test_build_id) ||
       !preg_match("/^\d+$/", $test_build_id, $m) ) {
        # We could guess using: $test_build_id = find_test_build_id();
        # But we should probably just pint it to an invalid row for safety.
        $test_build_id = 0;

        $error_output .= ("-------------------------------\n".
                          "Invalid test_build_id ($orig_test_build_id) given. (Not provided)\n".
                          "Guessing that it should be $test_build_id \n".
                          "-------------------------------\n");
        mtt_notice("WARNING:\n".$error_output);
    }
    else {
        $select_stmt = ("SELECT test_build_id $nl" .
                        "FROM test_build $nl".
                        "WHERE $nlt" .
                        "test_build_id = '".$test_build_id."'");

        $valid_id = select_scalar($select_stmt);

        if( !isset($valid_id) ) {
            # We could guess using: $test_build_id = find_test_build_id();
            # But we should probably just pint it to an invalid row for safety.
            $test_build_id = 0;

            $error_output .= ("-------------------------------\n".
                              "Invalid test_build_id ($orig_test_build_id) given. (Does not exist)\n" .
                              "Guessing that it should be $test_build_id \n".
                              "-------------------------------\n");
            mtt_notice("WARNING:\n".$error_output);
        }
    }

    if( $test_build_id < 0 ) {
        $error_output .= ("-------------------------------\n".
                          "ERROR: Unable to find a test_build to associate with this test_run.".
                          "-------------------------------\n");
        mtt_send_mail($error_output, $error_function);
        mtt_error("ERROR: Unable to find a test_build to associate with this test_run.\n");
        mtt_abort(400, "\nNo test_build associated with this test_run\n");
        exit(1);
    }

    $select_stmt = ("SELECT test_build_id, $nl" .
                    "       compute_cluster_id, $nl" .
                    "       mpi_install_compiler_id, $nl" .
                    "       mpi_get_id, $nl" .
                    "       mpi_install_configure_id, $nl" .
                    "       mpi_install_id, $nl" .
                    "       test_suite_id, $nl" .
                    "       test_build_compiler_id $nl" .
                    "FROM test_build $nl" .
                    "WHERE $nlt" .
                    "test_build_id = '".$test_build_id."'");

    debug("Test Build IDs Select: \n");
    debug("$select_stmt\n");

    $test_build_ids = associative_select($select_stmt);

    if( 0 < strlen($error_output) ) {
        $error_output = ("WARNING: The following Test Build was not able to be added to the database properly.\n".
                         "         See the below and attached information for more information.\n".
                         "-------------------------------\n".
                         $select_stmt."\n".
                         "-------------------------------\n".
                         "Resolved to:\n".
                         var_export($test_build_ids, true)."\n".
                         "-------------------------------\n".
                         $error_output);
        mtt_send_mail($error_output, $error_function);
    }

    return $test_build_ids;
}

#
# This is really taking a best guess at what the test_build_id might
# be given the limited amount of data the client provides us.
#
function find_test_build_id() {
    $error_function = "find_test_build_id()";

    $nl  = "\n";
    $nlt = "\n\t";

    $multi_value = false;

    $n = $_POST['number_of_results'];
    $i = 0;
    $test_build_id = 0;

    #
    # Do this instead of getting all of the columns passed
    # so we don't overload the memory space.
    $columns = array("mpi_version",
                     "mpi_name",
                     "hostname",
                     "mtt_client_version",
                     "local_username",
                     "platform_name");
    $param_set = get_post_values($columns);

    $select_stmt = ("SELECT test_build_id $nl" .
                    "FROM test_build  NATURAL JOIN $nl" .
                    "     mpi_get     NATURAL JOIN $nl" .
                    "     compute_cluster NATURAL JOIN $nl" .
                    "     submit $nl" .
                    "WHERE $nlt");

    if(!is_sql_key_word(get_scalar($param_set['mpi_version'], $i))) {
        if( $multi_value ) { $select_stmt .= (" AND $nlt"); }
        $select_stmt .= ("mpi_version = ".quote_(pg_escape_string(get_scalar($param_set['mpi_version'], $i))) );
        $select_stmt .= " ";
        $multi_value = true;
    }
    if(!is_sql_key_word(get_scalar($param_set['mpi_name'], $i)) ) {
        if( $multi_value ) { $select_stmt .= (" AND $nlt"); }
        $select_stmt .= ("mpi_name    = ".quote_(pg_escape_string(get_scalar($param_set['mpi_name'], $i)) ) );
        $select_stmt .= " ";
        $multi_value = true;
    }
    if(!is_sql_key_word(get_scalar($param_set['hostname'], $i)) ) {
        if( $multi_value ) { $select_stmt .= (" AND $nlt"); }
        $select_stmt .= ("hostname    = ".quote_(pg_escape_string(get_scalar($param_set['hostname'], $i)) ) );
        $select_stmt .= " ";
        $multi_value = true;
    }
    if(!is_sql_key_word(get_scalar($param_set['mtt_client_version'], $i)) ) {
        if( $multi_value ) { $select_stmt .= (" AND $nlt"); }
        $select_stmt .= ("mtt_client_version    = ".quote_(pg_escape_string(get_scalar($param_set['mtt_client_version'], $i)) ) );
        $select_stmt .= " ";
        $multi_value = true;
    }
    if(!is_sql_key_word(get_scalar($param_set['local_username'], $i)) ) {
        if( $multi_value ) { $select_stmt .= (" AND $nlt"); }
        $select_stmt .= ("local_username    = ".quote_(pg_escape_string(get_scalar($param_set['local_username'], $i)) ) );
        $select_stmt .= " ";
        $multi_value = true;
    }
    if(!is_sql_key_word(get_scalar($param_set['platform_name'], $i)) ) {
        if( $multi_value ) { $select_stmt .= (" AND $nlt"); }
        $select_stmt .= ("platform_name    = ".quote_(pg_escape_string(get_scalar($param_set['platform_name'], $i)) ) );
        $select_stmt .= " ";
        $multi_value = true;
    }
    $select_stmt .= " $nlt";
    $select_stmt .= ("ORDER BY test_build_id DESC limit 1");

    $test_build_id = select_scalar($select_stmt);

    if(isset($test_build_id) && 0 < strlen($test_build_id) ) {
        return $test_build_id;
    }
    else {
        $error_output = ("find_test_build_id():\n".
                         "-------------------------------\n".
                         "The following SELECT returned -1:\n".
                         "-------------------------------\n".
                         $select_stmt."\n".
                         "-------------------------------\n");
        mtt_send_mail($error_output, $error_function);
        return -1;
    }
}

function get_mpi_install_ids($mpi_install_id) {
    $error_function = "get_mpi_install_ids(".$mpi_install_id.")";

    $nl  = "\n";
    $nlt = "\n\t";
    $error_output = "";
    $mpi_install_ids = null;

    $orig_mpi_install_id = $mpi_install_id;

    ###############
    # First check if this is a valid mpi_install_id
    # If not then we give it '0', and insert it so no data is lost
    if(!isset($mpi_install_id) ||
       0 == strlen($mpi_install_id) ||
       !preg_match("/^\d+$/", $orig_mpi_install_id, $m) ) {
        # We could guess using: $mpi_install_id = find_mpi_install_id();
        # But we should probably just pint it to an invalid row for safety.
        $mpi_install_id = 0;

        $error_output .= ("-------------------------------\n".
                          "Invalid mpi_install_id ($orig_mpi_install_id) given. (Not provided)\n".
                          "Guessing that it should be $mpi_install_id .\n".
                          "-------------------------------\n");
        mtt_notice("WARNING:\n".$error_output);
    }
    else {
        $select_stmt = ("SELECT mpi_install_id $nl" .
                        "FROM mpi_install $nl".
                        "WHERE $nlt" .
                        "mpi_install_id = '".$mpi_install_id."'");

        $valid_id = select_scalar($select_stmt);

        if( !isset($valid_id) ) {
            # We could guess using: $mpi_install_id = find_mpi_install_id();
            # But we should probably just pint it to an invalid row for safety.
            $mpi_install_id = 0;

            $error_output .= ("-------------------------------\n".
                              "Invalid mpi_install_id ($orig_mpi_install_id) given. (Does not exist)\n".
                              "Guessing that it should be $mpi_install_id \n".
                              "-------------------------------\n");
            mtt_notice("WARNING:\n".$error_output);
        }
    }
    
    if( $mpi_install_id < 0 ) {
        $error_output .= ("-------------------------------\n".
                          "ERROR: Unable to find a mpi_install to associate with this test_build.".
                          "-------------------------------\n");
        mtt_send_mail($error_output, $error_function);
        mtt_error("ERROR: Unable to find a mpi_install to associate with this test_build.\n");
        mtt_abort(400, "\nNo mpi_install associated with this test_build\n");
        exit(1);
    }

    $select_stmt = ("SELECT mpi_install_id, $nl" .
                    "       compute_cluster_id, $nl" .
                    "       mpi_install_compiler_id, $nl" .
                    "       mpi_get_id, $nl" .
                    "       mpi_install_configure_id $nl" .
                    "FROM mpi_install $nl" .
                    "WHERE $nlt" .
                    "mpi_install_id = '".$mpi_install_id."'");

    debug("MPI Install IDs Select: \n");
    debug("$select_stmt\n");

    $mpi_install_ids = associative_select($select_stmt);

    if( 0 < strlen($error_output) ) {
        $error_output = ("WARNING: The following MPI Install was not able to be added to the database properly.\n".
                         "         See the below and attached information for more information.\n".
                         "-------------------------------\n".
                         $select_stmt."\n".
                         "-------------------------------\n".
                         "Resolved to:\n".
                         var_export($mpi_install_ids, true)."\n".
                         "-------------------------------\n".
                         $error_output);
        mtt_send_mail($error_output, $error_function);
    }

    return $mpi_install_ids;
}

#
# This is really taking a best guess at what the mpi_install_id might
# be given the limited amount of data the client provides us.
#
function find_mpi_install_id() {
    $error_function = "find_mpi_install_id()";

    $nl  = "\n";
    $nlt = "\n\t";
    $error_output = "";
    $multi_value = false;

    $n = $_POST['number_of_results'];
    $i = 0;
    $mpi_install_id = 0;

    #
    # Do this instead of getting all of the columns passed
    # so we don't overload the memory space.
    $columns = array("mpi_version", 
                     "mpi_name",
                     "compiler_version",
                     "compiler_name",
                     "hostname",
                     "mtt_client_version",
                     "local_username",
                     "platform_name");
    $param_set = get_post_values($columns);

    $select_stmt = ("SELECT mpi_install_id $nl" .
                    "FROM mpi_install NATURAL JOIN $nl" .
                    "     mpi_get     NATURAL JOIN $nl" .
                    "     compiler    NATURAL JOIN $nl" .
                    "     compute_cluster NATURAL JOIN $nl" .
                    "     submit $nl" .
                    "WHERE $nlt");

    if(!is_sql_key_word(get_scalar($param_set['mpi_version'], $i)) ) {
        if( $multi_value ) { $select_stmt .= (" AND $nlt"); }
        $select_stmt .= ("mpi_version = ".quote_(pg_escape_string(get_scalar($param_set['mpi_version'], $i))) );
        $select_stmt .= " ";
        $multi_value = true;
    }
    if(!is_sql_key_word(get_scalar($param_set['mpi_name'], $i)) ) {
        if( $multi_value ) { $select_stmt .= (" AND $nlt"); }
        $select_stmt .= ("mpi_name    = ".quote_(pg_escape_string(get_scalar($param_set['mpi_name'], $i)) ) );
        $select_stmt .= " ";
        $multi_value = true;
    }
    if(!is_sql_key_word(get_scalar($param_set['compiler_version'], $i)) ) {
        if( $multi_value ) { $select_stmt .= (" AND $nlt"); }
        $select_stmt .= ("compiler_version    = ".quote_(pg_escape_string(get_scalar($param_set['compiler_version'], $i)) ) );
        $select_stmt .= " ";
        $multi_value = true;
    }
    if(!is_sql_key_word(get_scalar($param_set['compiler_name'], $i)) ) {
        if( $multi_value ) { $select_stmt .= (" AND $nlt"); }
        $select_stmt .= ("compiler_name    = ".quote_(pg_escape_string(get_scalar($param_set['compiler_name'], $i)) ) );
        $select_stmt .= " ";
        $multi_value = true;
    }
    if(!is_sql_key_word(get_scalar($param_set['hostname'], $i)) ) {
        if( $multi_value ) { $select_stmt .= (" AND $nlt"); }
        $select_stmt .= ("hostname    = ".quote_(pg_escape_string(get_scalar($param_set['hostname'], $i)) ) );
        $select_stmt .= " ";
        $multi_value = true;
    }
    if(!is_sql_key_word(get_scalar($param_set['mtt_client_version'], $i)) ) {
        if( $multi_value ) { $select_stmt .= (" AND $nlt"); }
        $select_stmt .= ("mtt_client_version    = ".quote_(pg_escape_string(get_scalar($param_set['mtt_client_version'], $i)) ) );
        $select_stmt .= " ";
        $multi_value = true;
    }
    if(!is_sql_key_word(get_scalar($param_set['local_username'], $i)) ) {
        if( $multi_value ) { $select_stmt .= (" AND $nlt"); }
        $select_stmt .= ("local_username    = ".quote_(pg_escape_string(get_scalar($param_set['local_username'], $i)) ) );
        $select_stmt .= " ";
        $multi_value = true;
    }
    if(!is_sql_key_word(get_scalar($param_set['platform_name'], $i)) ) {
        if( $multi_value ) { $select_stmt .= (" AND $nlt"); }
        $select_stmt .= ("platform_name    = ".quote_(pg_escape_string(get_scalar($param_set['platform_name'], $i)) ) );
        $select_stmt .= " ";
        $multi_value = true;
    }
    $select_stmt .= " $nlt";
    $select_stmt .= ("ORDER BY mpi_install_id DESC limit 1");

    $mpi_install_id = select_scalar($select_stmt);

    if(isset($mpi_install_id) && 0 < strlen($mpi_install_id) ) {
        return $mpi_install_id;
    }
    else {
        $error_output = ("ERROR:\n".
                         "---------------------------------\n".
                         "The following SELECT returned -1:\n".
                         "-------------------------------\n".
                         $select_stmt."\n".
                         "-------------------------------\n");
        mtt_send_mail($error_output, $error_function);
        return -1;
    }
}

function process_phase_mpi_install($results_idxs_hash) {
    $error_function = "process_phase_mpi_install()";

    $n = $_POST['number_of_results'];

    #
    # Do this instead of getting all of the columns passed
    # so we don't overload the memory space.
    $columns = array("compiler_name",
                     "compiler_version",
                     "platform_name",
                     "platform_hardware",
                     "platform_type",
                     "os_name",
                     "os_version",
                     "mpi_name",
                     "mpi_version",
                     "vpath_mode",
                     "bitness",
                     "endian",
                     "configure_arguments",
                     "result_message",
                     "description",
                     "environment",
                     "start_timestamp",
                     "test_result",
                     "trial",
                     "duration",
                     "result_stdout",
                     "result_stderr",
                     "merge_stdout_stderr",
                     "exit_value",
                     "exit_signal",
                     "client_serial");
    $param_set = get_post_values($columns);

    #######
    # A 'client_serial' is required, so check before moving forward
    if(!isset($param_set['client_serial']) ||
       0 == strlen($param_set['client_serial']) ||
       !preg_match("/^\d+$/", $param_set['client_serial'], $m) ) {
        $error_output .= ("CRITICAL ERROR: Cannot continue\n".
                          "-------------------------------\n".
                          "Invalid client_serial (".$param_set['client_serial'].") given.\n".
                          "-------------------------------\n");
        mtt_send_mail($error_output, $error_function);
        mtt_abort(400, $error_output);
        exit(1);
    }

    for($i = 0; $i < $n; $i++) {

        # The POST fields are enumerated starting at 1
        $j = $i + 1;

        ########
        # Select/Insert: compute_cluster
        $stmt_fields = array("platform_name",
                             "platform_hardware",
                             "platform_type",
                             "os_name",
                             "os_version");

        $stmt_values = array();
        for($f = 0; $f < count($stmt_fields); $f++) {
            $stmt_values[] = get_scalar($param_set[$stmt_fields[$f]], $i);
        }

        $results_idxs_hash['compute_cluster_id'] =
            select_insert("compute_cluster", "compute_cluster_id",
                          $stmt_fields, $stmt_values,
                          false);

        ########
        # Select/Insert: mpi_install_compiler -> compiler
        # Error out if the client did not supply a compiler,
        # as DEFAULT is meaningless here
        $stmt_fields = array("compiler_name",
                             "compiler_version");
        $stmt_values = array();
        for($f = 0; $f < count($stmt_fields); $f++) {
            if(0 == strcasecmp(get_scalar($param_set[$stmt_fields[$f]], $i), "DEFAULT") ) {
               mtt_error("ERROR: No compiler reported which is required for mpi_install submits ".
                         "[field '".$stmt_fields[$f]."' empty]\n");
               mtt_abort(400, "\nNo compiler supplied for mpi_install submit. ".
                              "[field '".$stmt_fields[$f]."' empty]");
               exit(1);
            }

            $stmt_values[] = get_scalar($param_set[$stmt_fields[$f]], $i);
        }

        $results_idxs_hash['mpi_install_compiler_id'] = 
            select_insert("compiler", "compiler_id",
                          $stmt_fields, $stmt_values,
                          false);

        ########
        # Select/Insert: mpi_get
        $stmt_fields = array("mpi_name",
                             "mpi_version");

        $stmt_values = array();
        for($f = 0; $f < count($stmt_fields); $f++) {
            $stmt_values[] = get_scalar($param_set[$stmt_fields[$f]], $i);
        }

        $results_idxs_hash['mpi_get_id'] =
            select_insert("mpi_get", "mpi_get_id",
                          $stmt_fields, $stmt_values,
                          false);

        ########
        # Select/Insert: mpi_install_configure -> mpi_install_configure table
        $stmt_fields = array("vpath_mode",
                             "bitness",
                             "endian",
                             "configure_arguments");

        $stmt_values = array(convert_vpath_mode(get_scalar($param_set['vpath_mode'], $i) ),
                             convert_bitness(   get_scalar($param_set['bitness'],    $i) ),
                             convert_endian(    get_scalar($param_set['endian'],     $i) ),
                             get_scalar($param_set['configure_arguments'],           $i) );

        $results_idxs_hash['mpi_configure_id'] =
            select_insert("mpi_install_configure_args", "mpi_install_configure_id",
                          $stmt_fields, $stmt_values,
                          false);

        #########
        # Select/Insert: Description
        $results_idxs_hash['description_id'] = 0;
        if( !is_sql_key_word(get_scalar($param_set['description'], $i)) ) {
            $stmt_fields = array("description");
            $stmt_values = array(get_scalar($param_set['description'], $i));

            $results_idxs_hash['description_id'] = 
                select_insert("description", "description_id",
                              $stmt_fields, $stmt_values,
                              false);
        }

        #########
        # Select/Insert: Result Message
        $stmt_fields = array("result_message");

        $stmt_values = array(get_scalar($param_set['result_message'], $i) );

        $results_idxs_hash['result_message_id'] =
            select_insert("result_message", "result_message_id",
                          $stmt_fields, $stmt_values,
                          false);

        #########
        # Select/Insert: Environment
        $results_idxs_hash['environment_id'] = 0;
        if( isset($_POST["environment_$j"]) ) {
            $stmt_fields = array("environment");

            $stmt_values = array(get_scalar($param_set['environment'], $i) );

            $results_idxs_hash['environment_id'] =
                select_insert("environment", "environment_id",
                              $stmt_fields, $stmt_values,
                              false);
        }

        #########
        # Insert: Result for MPI Install
        $stmt_fields = array("submit_id",
                             "compute_cluster_id",
                             "mpi_install_compiler_id",
                             "mpi_get_id",
                             "mpi_install_configure_id",
                             "description_id",
                             "start_timestamp",
                             "test_result",
                             "trial",
                             "submit_timestamp",
                             "duration",
                             "environment_id",
                             "result_stdout",
                             "result_stderr",
                             "result_message_id",
                             "merge_stdout_stderr",
                             "exit_value",
                             "exit_signal",
                             "client_serial");

        $stmt_values = array($results_idxs_hash['submit_id'],
                             $results_idxs_hash['compute_cluster_id'],
                             $results_idxs_hash['mpi_install_compiler_id'],
                             $results_idxs_hash['mpi_get_id'],
                             $results_idxs_hash['mpi_configure_id'],
                             $results_idxs_hash['description_id'],
                             get_scalar($param_set['start_timestamp'], $i),
                             get_scalar($param_set['test_result'], $i),
                             get_scalar($param_set['trial'], $i),
                             "DEFAULT",
                             get_scalar($param_set['duration'], $i),
                             $results_idxs_hash['environment_id'],
                             get_scalar($param_set['result_stdout'], $i),
                             get_scalar($param_set['result_stderr'], $i),
                             $results_idxs_hash['result_message_id'],
                             get_scalar($param_set['merge_stdout_stderr'], $i),
                             get_scalar($param_set['exit_value'], $i),
                             get_scalar($param_set['exit_signal'], $i),
                             get_scalar($param_set['client_serial'], $i)
                             );
        
        $mpi_install_id =
            select_insert("mpi_install", "mpi_install_id",
                          $stmt_fields, $stmt_values,
                          true);

        debug("*** MPI Install Id [$mpi_install_id]\n");
    }

    return $mpi_install_id;
}

function select_insert($table, $table_id, $stmt_fields, $stmt_values, $always_new) {
    $num_good_fields = 0;
    $nl  = "\n";
    $nlt = "\n\t";
    $rtn_insert = null;

    $select_stmt = ("SELECT $table_id $nl" .
                    "FROM $table $nl");
    $insert_stmt = ("INSERT INTO $table $nlt" .
                    "($table_id");

    for($i = 0; $i < count($stmt_fields); ++$i) {
        $insert_stmt .= ", " . $stmt_fields[$i];

        # Select Skips 'DEFAULT' values
        if( 0 == strncmp($stmt_values[$i], "DEFAULT", strlen("DEFAULT")) ) {
            continue;
        }

        if( $i != 0 ) {  $select_stmt .= " AND $nlt";  }
        else {           $select_stmt .= "WHERE $nlt"; }

        $select_stmt .= $stmt_fields[$i] . " = ";
        $select_stmt .= quote_(pg_escape_string($stmt_values[$i])) ;
        $num_good_fields++;
    }
    $select_stmt .= $nl . "ORDER BY $table_id ASC LIMIT 1 ";
    $insert_stmt .= ") VALUES " . $nlt . "(";

    ###############
    # Try out the select to see if we have to insert
    if(! $always_new && 0 < $num_good_fields) {
        debug("\n--- SELECT STMT ---\n");
        debug("$select_stmt\n");

        $idx_value = select_scalar($select_stmt);
        if( ! is_null_($idx_value) ) {
            return $idx_value;
        }
    }

    ###############
    # Since it does not exist, insert a new tuple
    $seq_name = $table . "_" . $table_id . "_seq";
    $idx_value = fetch_single_nextval($seq_name);

    $insert_stmt .=  quote_(pg_escape_string($idx_value));
    for($i = 0; $i < count($stmt_fields); ++$i) {
        $insert_stmt .= ", ";
        if( 0 == strncmp($stmt_values[$i], "DEFAULT", strlen("DEFAULT")) ) {
            $insert_stmt .= "DEFAULT";
        }
        else {
            $insert_stmt .= quote_(pg_escape_string($stmt_values[$i])) ;
        }
    }
    $insert_stmt .= ")";

    debug("\n--- INSERT STMT ---\n");
    debug("$insert_stmt\n");

    $rtn_insert = do_pg_query($insert_stmt, false);

    #############
    # If the insert operation failed, then this usually means that another
    # thread beat us to the insert, so just select the last id.
    # if this select fails, then badness happened somewhere :(
    if( !$rtn_insert ) {
        $idx_value = select_scalar($select_stmt);
    }

    return $idx_value;
}

# array_unique that does not error out when given a scalar
function _array_unique($var) {

    if (is_array($var))
        return array_unique($var);
    elseif (is_scalar($var))
        return array($var);
}

# array_unique that does not error out when given a scalar
function _array_values($var) {

    if (is_array($var))
        return array_values($var);
    elseif (is_scalar($var))
        return array($var);
}

function fetch_nextvals($idx, $seq_name, $numbered) {

    $n = $_POST['number_of_results'];

    for ($i = 0; $i < $n; $i++) {
        if (is_null($idx[$i])) {
            $ret['idx'][$i] = fetch_single_nextval($seq_name);
            $ret['new_indexes'][$i] = true;
        } else {
            $ret['new_indexes'][$i] = false;
        }
            
        if (! $numbered)
            break;
    }

    return $ret;
}

function fetch_single_nextval($seq_name) {
    return select_scalar("SELECT nextval('$seq_name') LIMIT 1;");
}

# Return true if the table contains an integer
# index into another table
function contains_table_key($table_name) {

    $t = array();
    $t = get_table_indexes($table_name, false);
    return (count($t) > 0);
}

function contains_no_table_key($table_name) {
    return ! contains_table_key($table_name);
}

# Recursively gather all indexes linked to $parent. The prune_list is
# used to avoid descending into a part of the schema
function gather_indexes($parent, $child, $idxs, $prune_list) {

    global $id;

    $new_idxs = get_table_indexes($parent, true);

    if (! is_null($child))
        $self = array(
                    $parent . $id => array(
                        'integer' => $child,
                        'serial' => $parent,
                    )
                );
    else
        $self = NULL;

    $prune = false;
    foreach ($prune_list as $pattern)
        if (strstr($parent, $pattern))
            $prune = true;


    if ((count($new_idxs) > 0) and ! $prune) {

        foreach ($new_idxs as $idx) {
            $t = array();
            $t = gather_indexes(get_idx_root($idx), $parent, $idxs, $prune_list);

            $idxs = array_merge(
                                (array)$self,
                                (array)$t,
                                (array)$idxs
                    );
        }
    }
    else {
        return $self;
    }

    return $idxs;
}

function sql_join($table_name) {
    global $id;
    return "JOIN $table_name USING (" . $table_name . $id . ")";
}

# X: maybe a misnomer, since this function doesn't involve database
# indexes, but rather the pointers to other tables set up for this schema
function get_table_indexes($table_name, $qualified) {

    global $id;
    global $dbname;

    # Crude way to tell whether a field is an index
    $is_index_clause = "\n\t (data_type = 'integer' AND " .
                       "\n\t column_name ~ '$id$' AND " .
                       "\n\t column_default !~ 'nextval' AND " .
                       "\n\t table_catalog = '$dbname')";

    $select = "column_name";

    $sql_cmd = "\n   SELECT $select as index " .
               "\n\t FROM information_schema.columns WHERE " .
               "\n\t table_name = '$table_name' AND " . $is_index_clause . ';';

    do_pg_connect();
    return simple_select($sql_cmd);
}

#
# Useful display of all the parameters posted.
# Warning: this function could explode the memory footprint causing the 
# script to fail for large submits.
function debug_dump_data() {
  $n = $_POST['number_of_results'];

  # Iterate through POST, and report names that are not 
  # columns in the database
  print("=======================================\n");

  $uber_param = get_all_post_values();
  for($i = 0; $i < $n; $i++) {
    foreach(array_keys($uber_param) as $f) {
      print("Posted Parameters $i: [".$f."] = [".get_scalar($uber_param[$f], $i)."]\n");
    }
  }
  print("=======================================\n\n");
}

# Check fields in the POST that are not in the DB
function report_non_existent_fields() {

    global $dbname;

    $sql_cmd = "\n   SELECT column_name " .
               "\n\t FROM information_schema.columns " . 
               "\n\t WHERE table_schema = 'public'";

    do_pg_connect();

    $arr = array();
    $arr = simple_select($sql_cmd);
    $arr = array_flip($arr);

    # Iterate through POST, and report names that are not 
    # columns in the database
    foreach (array_keys($_POST) as $k) {

        # We only need to check the first numbered field
        if (preg_match("/_(\d+)$/", $k, $m)) {
            $n = $m[1];
            if ($n > 1)
                continue;
        }
        $name = preg_replace('/_\d+$/', '', $k);
        # Only print this if we are debugging the submit script.
        # The user cannot do anything about this, so why tell then about it.
        if (!array_key_exists($name, $arr) && isset($_POST['debug']) ) {
            mtt_notice("$name is not in $dbname database.");
        }
    }
}

# Take an array or scalar
function get_scalar($var , $i) {

    if (is_array($var))
        return $var[$i];
    else
        return $var;
}

######################################################################

# Return either var, or [elem1, elem2, ... elemn]
function stringify($var) {
    if (is_array($var))
        if (is_numeric_($var))
            return join(",",$var);
        else
            return $var;
    else
        return $var;
}

# Check for numeric array
function is_numeric_($ar) {
    $keys = array_keys($ar);
    natsort($keys); # String keys will be last
    return is_int(array_pop($keys));
}

# Return true if it's a NULL or an array containing a single NULL
function is_null_($var) {
    $ret = false;

    if (is_null($var))
        $ret = true;
    elseif (is_array($var))
        foreach ($var as $v)
            if (is_null($v)) {
                $ret = true;
                break;
            }
    else
        $ret = false;

    return $ret;
}

######################################################################

# Fetch an associative hash (column name => value)
function associative_select($cmd) {
    $error_function = "associative_select()";

    do_pg_connect();

    debug("\nSQL: $cmd\n");
    if (! ($result = pg_query($cmd))) {
        $out = "\nSQL QUERY: " . $cmd .
               "\nSQL ERROR: " . pg_last_error() .
               "\nSQL ERROR: " . pg_result_error();
        mtt_send_mail($out, $error_function);
        mtt_error($out);
    }
    return pg_fetch_array($result);
}

######################################################################

# Function for reporting errors back to the client
function mtt_abort($status, $str) {
    if (!headers_sent()) {
        header("HTTP/1.0 $status");
    } else {
        print("MTTDatabase abort: (Tried to send HTTP error) $status\n");
    }
    print("MTTDatabase abort: $str\n");
    pg_close();
    exit(0);
}

function mtt_send_mail($message, $func) {

    # Send only one email per phase to avoid a hurricane of
    # SQL error emails (generally in this case, when it
    # rains it pours here)
    static $sent_mail = false;

    if ($sent_mail)
        return;

    # Export the PHP POST data to a temp file
    if (! ($filename = tempnam("/tmp", "submit-")))
        mtt_notice("Could not create a temporary file.\n");

    $filename .= ".inc";

    $fp = fopen($filename, "wb");
    fwrite($fp, var_export($_POST, 1));
    fclose($fp);

    $php_auth_user = $_SERVER['PHP_AUTH_USER'];
    $user          = "";
    if( isset($_POST['email']) ) {
        $user      = $_POST['email'];
    }
    $admin         = 'mtt-devel-core@open-mpi.org';
    $date          = date('r');
    $phpversion    = phpversion();
    $boundary      = md5(time());

    # Read the atachment file contents into a string, encode it with MIME
    # base64, and split it into smaller chunks
    $attachment = chunk_split(base64_encode(file_get_contents($filename)));

    $headers = <<<END
From: $admin
Reply-To: $admin
Date: $date
X-Mailer: PHP v$phpversion
MIME-Version: 1.0
Content-Type: multipart/related; boundary="$boundary"
END;

    $message = <<<END
--$boundary
Content-Type: text/plain; charset="iso-9959-1"
Content-Transfer-Encoding: 7bit

----------------------------
Date     : $date
User     : $php_auth_user
Email    : $user
Function : $func
----------------------------

$message

--$boundary
Content-Type: text/plain; name="$filename"
Content-Disposition: attachment; filename="$filename"
Content-Transfer-Encoding: base64

$attachment

--$boundary--

END;

    # Email the user of the offending MTT client
    if (preg_match("/\w+@\w+/", $user, $m)) {
        mail($user, "MTT server error", $message, $headers);
    }

    # Email the MTT database administrator(s)
    mail("$admin", "MTT server error (user: $php_auth_user)", $message, $headers);

    # Whack the temp file
    unlink($filename);

    $sent_mail = true;
}

######################################################################

# Quote non-sql-key-words
function quote_($str) {
    if (! is_sql_key_word($str))
        return "'" . $str . "'";
    else
        return "$str";
}

# Return true if this is an sql keyword (that should not be quoted)
function is_sql_key_word($str) {

    $key_words = array(
        "DEFAULT",
        "NULL",
    );

    if (preg_match("/^\s*(" . join("|", $key_words) . ")\s*$/i", $str))
        return true;
    else
        return false;
}

# Take param value
# Return param = 'value'
function sql_compare($param, $value, $type, $default) {

    $default = preg_replace('/::.*$/', '', $default);

    if (preg_match("/'([^']*)'/", $default, $m))
        $default = $m[1];

    # X: Replace this block to use some sort of
    # is_default(x) postgres stored procedure
    if (strstr($type, "timestamp"))
        $clause = 'true';           # This allows us to recycle a row
    elseif (strstr($type, "serial"))
        $clause = 'true';           # This allows us to recycle a row

    # When doing comparisons in a SELECT statement we cannot
    # use the DEFAULT key word, we have to provide the
    # actual value of the DEFAULT
    elseif (strstr($value, "DEFAULT"))
        $clause = "$param = '$default'";
    else
        $clause = "$param = " . quote_($value);

    return $clause;
}

# Take foo_id, return foo
function get_idx_root($str) {
    return preg_replace('/_id$/', '', $str);
}

# Args: parameters to fetch from _POST
# Return: associateive array of field=value pairs

# Three types of POST params:
# 
# 1 Once set (not numbered)
# 2 Always set (each and every param, 1-num_of_results are set)
# 3 Sometimes set (some names are set)

# A "some_set" field is a field that may be present in
# only several tests in a given submission (e.g., latency_min)
# Only a numbered field can be a some_set
#
# 1. Determine the some_sets
# 2. Fill in the name/value pairs, and use DEFAULT if 
#    it is a some_set

function get_post_values($params) {

    $n = $_POST['number_of_results'];

    $hash = array();
    $some_set = array();

    # Determine some_sets
    foreach ($params as $field) {
        for ($i = 1; $i <= $n; $i++) {
            $name = "${field}_$i";
            if (isset($_POST[$name])) {
                $some_set[$field] = true;
            }
        }
    }

    foreach ($params as $field) {

        $found_value = false;
        $numbered = false;

        for ($i = 0; $i <= $n; $i++) {

            $name = $field . (($i == 0) ? "" : "_" . $i);
            $numbered = (($i == 0) ? false : true);

            if (isset($_POST[$name])) {

                $value       = $_POST[$name];
                $found_value = true;

                if ($numbered) {
                    $hash[$field][] = $value;
                }
                else {
                    $hash[$field] = $value;
                    break;
                } 
            }
            elseif (isset($some_set[$field]) and $numbered) {
                $hash[$field][] = "DEFAULT";
            }
        }
        # We could leave this out and the field would insert to DEFAULT,
        # let's explicitly INSERT DEFAULT for now
        if (! $found_value) {
            $hash[$field] = "DEFAULT";
        }
    }
    return $hash;
}

function get_all_post_values() {

    $n = $_POST['number_of_results'];

    $params = array();
    foreach(array_keys($_POST) as $k) {
       $params[] = preg_replace('/_\d+$/', '', $k);
    }
    $hash = array();
    $some_set = array();

    # Determine some_sets
    foreach ($params as $field) {
        for ($i = 1; $i <= $n; $i++) {
            $name = $field . (($i == 0) ? "" : "_" . $i);
            if (isset($_POST[$name])) {
                $some_set[$field] = true;
            }
        }
    }

    foreach ($params as $field) {

        $found_value = false;
        $numbered = false;

        for ($i = 0; $i <= $n; $i++) {

            $name = $field . (($i == 0) ? "" : "_" . $i);
            $numbered = (($i == 0) ? false : true);

            if (isset($_POST[$name])) {

                $value       = $_POST[$name];
                $found_value = true;

                if ($numbered) {
                    $hash[$field][] = $value;
                }
                else {
                    $hash[$field] = $value;
                    break;
                } 
            }
            elseif (isset($some_set[$field]) and $numbered) {
                $hash[$field][] = "DEFAULT";
            }
        }
        # We could leave this out and the field would insert to DEFAULT,
        # let's explicitly INSERT DEFAULT for now
        if (! $found_value) {
            $hash[$field] = "DEFAULT";
        }
    }
    return $hash;
}

# Args: params (which presumably map to a single db table)
# Return: true if it contains a numbered field in HTTP input
function are_numbered($params) {

    $n = $_POST['number_of_results'];

    foreach ($params as $field) {
        for ($i = 1; $i <= $n; $i++) {
            $name = $field . "_" . $i;
            if (isset($_POST[$name])) {
                $ret = true;
                break 2;
            }
        }
    }
    return $ret;
}

# For returning to the client (so we can keep
# track of MTT client invocations)
function get_serial() {
    $error_function = "get_serial()";

    # Works in psql cli, *BROKEN* in php
    # $cmd =  "\n   SELECT relname FROM pg_class WHERE " .
    #         "\n\t relkind = 'S' AND " .
    #         "\n\t relnamespace IN ( " .
    #         "\n\t SELECT oid FROM pg_namespace WHERE " .
    #         "\n\t nspname NOT LIKE 'pg_%' AND " .
    #         "\n\t nspname != 'information_schema') " .
    #         "\n\t AND relname NOT LIKE '%id_seq';";
    #
    # $serial_name = select_scalar($cmd);

    $serial_name = 'client_serial';
    $serial      = fetch_single_nextval($serial_name);

    if( NULL == $serial ) {
        $error_output  = ("CRITICAL ERROR: Cannot continue\n".
                          "-------------------------------\n".
                          "Failed to find a ($serial_name) value!\n".
                          "-------------------------------\n");
        mtt_send_mail($error_output, $error_function);
        mtt_abort(400, $error_output);
        exit(1);
    }

    return $serial;
}

# Special debug routine to audit INSERT statements
function var_dump_debug_inserts($function, $line, $var_name, $arr) {

    if ($GLOBALS['verbose'] or $GLOBALS['debug']) {
        $output = "\ndebug: $function:$line, $var_name = ";
        foreach (array_keys($arr) as $k) {
            $output .= "\n\t '$k' => '" . 
                    (is_array($arr[$k]) ?
                        join(",", $arr[$k]) :
                        $arr[$k])
                    . "'";
        }
        print($output);
    }
}

# Return the name a temporary file to include
function gunzip_file($filename) {

    $temp_filename = tempnam("/tmp", "mtt-submit-php-");

    $fp = fopen($temp_filename, "wb");
    chmod($temp_filename, 0664);

    fwrite($fp, "<?php
function setup_post() {
        \$_POST = ");

    $handle = gzopen($filename, 'r');
    while (! gzeof($handle)) {
        fwrite($fp, gzgets($handle, 4096));
    }

    fwrite($fp, ";
}
?>
");
    gzclose($handle);
    fclose($fp);

    return $temp_filename;
}

function convert_bool($val) {
  if(!isset($val)) { return '1'; }
  else { return $val; }
}
function convert_vpath_mode($vm) {
  if($vm == 1) {      return "01"; }
  else if($vm == 2) { return "10"; }
  else {              return "00"; }
}

function convert_bitness($bit) {
  if(     $bit == 1 ) { return "000001"; }
  else if($bit == 2 ) { return "000010"; }
  else if($bit == 4 ) { return "000100"; }
  else if($bit == 6 ) { return "000110"; }
  else if($bit == 8 ) { return "001000"; }
  else if($bit == 16) { return "010000"; }
  else {                return "000000"; }
}

function convert_endian($bit) {
  if($bit == 1) {      return "01"; }
  else if($bit == 2) { return "10"; }
  else {               return "00"; }
}

function convert_launcher($cmd) {
    # Strip Off leading whitespace
    $loc_cmd = preg_replace('/^\s*/', '', $cmd);

    # Break up the arguments by spacing
    $args = preg_split('/\s+/', $loc_cmd);

    # The launcher is always the first item
    return $args[0];
}

function convert_parameters($cmd) {
    $params = "";
    $param_list = array();

    # Known parameters = # of arguments
    $known_params = array();
    $known_params['mca']  = 2;
    $known_params['gmca'] = 2;
    $known_params['am']   = 1;
    $known_params['ssi']  = 2;
    
    # Strip Off leading whitespace
    $loc_cmd = preg_replace('/^\s*/', '', $cmd);

    # Strip Off --prefix
    $loc_cmd = preg_replace('/(--prefix)\s+\S+\s+/', '', $loc_cmd);

    # Strip Off --host list argument
    $loc_cmd = preg_replace('/(--host)\s+\S+\s+/', '', $loc_cmd);

    # Break up the arguments by spacing
    $args = preg_split('/\s+/', $loc_cmd);

    #print_r($args);

    # For each argument
    for($i = 0; $i < count($args); $i++) {
        #
        # Check to see if it matches a known parameter
        foreach( array_keys($known_params) as $k ) {
            $params = "";
            if(preg_match("/$k$/", $args[$i], $matches) ) {
                #
                # if it does then pull off the arguments and add them to a list
                for($j = 0; $j <= $known_params[$k]; $j++, $i++) {
                    if($j != 0) {
                        $params .= " ";
                    }
                    if($i < count($args) && isset($args[$i])) {
                        $params .= $args[$i];
                    }
                }
                --$i;
                $param_list[] = $params;
                break;
            }
        }
    }

    $params = join(" ", $param_list);
    #print "Param List <$params>\n";
    return $params;
}
