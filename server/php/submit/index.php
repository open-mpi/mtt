<?php
# Copyright (c) 2006 Cisco Systems, Inc.  All rights reserved.

$dbname = isset($_GET['db']) ? $_GET['db'] : "mtt";
$user   = "mtt";
$pass   = "3o4m5p6i";

$GLOBALS['debug'] = isset($_POST['debug']) ? $_POST['debug'] : 0;
$GLOBALS['verbose'] = isset($_POST['verbose']) ? $_POST['verbose'] : 0;
$GLOBALS['nosql'] = isset($_POST['nosql']) ? $_POST['nosql'] : 0;

# if the PING field is set, then this was just a test.  Exit successfully.

if (isset($_POST['PING'])) {
    print "Ping successful.\n";
    exit(0);
}

# mtt_version_major - Major revision of MTT, must match server version
# mtt_version_minor - Minor revision of MTT

# If these are not set, then exit.

if (! isset($_POST['mtt_version_major']) ||
    ! isset($_POST['mtt_version_minor'])) {
    mtt_error(400, "\nClient version not specified.");
    exit(1);
}

# The following lists should be grabbed from the database

# Who is submitting?

# JMS: to be enabled later; but cannot write to $_POST, so will need to 
# do this differently.
#$_POST[submitting_http_username] = isset($_SERVER[PHP_AUTH_USER]) ?
#    $_SERVER[PHP_AUTH_USER] : "anonymous";

# What phase are we doing?

if (0 == strcasecmp($_POST['phase'], "test run")) {
    process_test_run();
} else if (0 == strcasecmp($_POST['phase'], "test build")) {
    process_test_build();
} else if (0 == strcasecmp($_POST['phase'], "mpi install")) {
    process_mpi_install();
} else {
    print "ERROR: Unknown phase! ($_POST[phase])<br>\n";
    mtt_error(400, "\nNo phase given, so I don't know which table to direct this data to.");
    exit(1);
}

# All done

pg_close();
exit(0);

######################################################################

function get_table_fields($table_name) {
    $sql_cmd = "SELECT column_name FROM information_schema.columns WHERE table_name = '$table_name'";

    do_pg_connect();
    debug("\nSQL: $sql_cmd\n");
    if (! ($result = pg_query($sql_cmd))) {
        mtt_error(100, "\npostgres: " . pg_last_error() . "\n" . 
                  pg_result_error());
    }
    $max = pg_num_rows($result);
    for ($i = 0; $i < $max; ++$i) {
        $row = pg_fetch_array($result, $i, PGSQL_NUM);
        $rows[] = $row[0];
    }
    return $rows;
}

######################################################################

function set_once_data() {
    global $_POST;

    $once_params = get_table_fields("once");

    # See if this data is already in the table
    $sql_cmd = "SELECT run_index FROM once WHERE ";
    $first = true;
    foreach ($once_params as $field) {
        if (isset($_POST[$field])) {
            $value = $_POST[$field];
            if (preg_match("/_timestamp/", $field)) {
                $value = unix2sql_time($value);
            }
            $suffix = $field . " = '" . pg_escape_string($value) . "'";
            if (! $first) {
                $sql_cmd .= " AND $suffix";
            } else {
                $sql_cmd .= $suffix;
                $first = false;
            }
        }
    }
    $idx = simple_select($sql_cmd);
    
    # If there is no matching config in the db - grab the latest run_index,
    # increment it, and assign it to this config
    # JMS: THIS IS A RACE CONDITION THAT WILL BE ADDRESSED BY TICKET #51
    $found_match = false;
    if ($idx == null) {
        $sql_cmd = "SELECT (run_index + 1) FROM once ORDER BY run_index DESC LIMIT 1;";
        $idx = simple_select($sql_cmd);
    } else {
        $found_match = true;
    }
    # this is the first config to be inserted
    if (! $idx) {
        $idx = 0;
    }

    # If it was not already in the table, insert it
    if (! $found_match) {
        $sql_cmd = "INSERT INTO once (";
        $values = ") VALUES (";
        $first = true;
        foreach ($once_params as $field) {
            if (isset($_POST[$field])) {
                $value = $_POST[$field];
                if (preg_match("/_timestamp/", $field)) {
                    $value = unix2sql_time($value);
                }
                if (! $first) {
                    $sql_cmd .= ",";
                    $values .= ",";
                }
                $sql_cmd .= $field;
                $values .= "'" . pg_escape_string($value) . "'";
                $first = false;
            }
        }

        $sql_cmd = "$sql_cmd, run_index$values, $idx)";
        do_pg_query($sql_cmd);
    }

    # Return the run index
    return $idx;
}

######################################################################

function set_multiple_data($run_idx, $table_name) {
    global $_POST;

    $db_fields = get_table_fields($table_name);
    $submitted_fields = explode(",", $_POST['fields']);
    foreach ($submitted_fields as $s_field) {
        foreach ($db_fields as $db_field) {
            if (0 == strcmp($s_field, $db_field)) {
                $good_fields[] = $s_field;
            }
        }
    }

    $n = $_POST['number_of_results'];
    for ($i = 1; $i <= $n; ++$i) {
        $sql_cmd = "INSERT INTO $table_name (run_index, ";
        $values = ") VALUES ('$run_idx',";
        $first = true;
        foreach ($good_fields as $field) {
            $name = $field . "_" . $i;
            if (isset($_POST[$name])) {
                $v = $_POST[$name];
            } else {
                $v = "";
            }
            if (preg_match("/_timestamp/", $field)) {
                $v = unix2sql_time($v);
            }
            if (! $first) {
                $sql_cmd .= ",";
                $values .= ",";
            }
            $sql_cmd .= $field;
            $values .= "'" . pg_escape_string($_POST[$name]) . "'";
            $first = false;
        }

        $sql_cmd .= $values . ")";
        do_pg_query($sql_cmd);
    }
}

######################################################################

function process_test_run() {
    $run_idx = set_once_data();
    set_multiple_data($run_idx, "runs");
}

function process_test_build() {
    $run_idx = set_once_data();
    set_multiple_data($run_idx, "builds");
}

function process_mpi_install() {
    $run_idx = set_once_data();
    set_multiple_data($run_idx, "installs");
}

######################################################################

function do_pg_connect() {
    global $dbname;
    global $user;
    global $pass;
    static $connected = false;

    if (!$connected) {
        $GLOBALS['conn'] = pg_connect("host=localhost port=5432 dbname=$dbname user=$user password=$pass");
        $connected = true;
    }
}

# select a field in the db and return it
function simple_select($cmd) {
    do_pg_connect();
    $fetched = null;

    debug("\nSQL: $cmd");
    if (! ($db_res = pg_query($cmd))) {
        debug("\npostgres: " . pg_last_error() . "\n" . pg_result_error());
    }
    $fetched = array_shift(pg_fetch_row($db_res));
    return $fetched;
}

function do_pg_query($cmd) {
    do_pg_connect();

    debug("\nSQL: $cmd\n");
    if (! ($db_res = pg_query($cmd))) {
        debug("\npostgres: " . pg_last_error() . "\n" . pg_result_error());
    }
}

# TODO: Make this more robust (or does postgres understand most Unix timestamps?)
function unix2sql_time($str) {
    return @preg_replace('/(Mon|Tue|Wed|Thu|Fri|Sat|Sun) /','',$str);
}

######################################################################

# Function to reporting errors back to the client
function mtt_error($status, $str) {
    if (!headers_sent()) {
        header("HTTP/1.0 $status");
    } else {
        print("ERROR: (Tried to send HTTP error) $status\n");
    }
    print("ERROR: $str\n");
    exit(0);
}

######################################################################

function debug($arg) {
    if ($GLOBALS['debug'] || $GLOBALS['verbose']) {
        if (is_string($arg)) {
            print("\n$arg");
        } else {
            print_r("\n$arg");
        }
    }
}
