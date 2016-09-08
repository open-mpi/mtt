<?php

#
# Copyright (c) 2006 Sun Microsystems, Inc.
#                         All rights reserved.
# Copyright (c) 2008      Mellanox Technologies.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

#
#
# Variables/Functions that map-to/operate-on database constructs
#
#

include_once("$topdir/config.inc");
include_once("$topdir/common.inc");
# For debug()
include_once("$topdir/reporter/util.inc");

# Select a database name
if (array_key_exists("db", $_GET) &&
    preg_match("/mtt/i", $_GET['db'])) {
    $mtt_database_name = $_GET['db'];
}

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

# Function used to determine which _POST fields
# to INSERT. Prevent non-existent fields from being
# INSERTed
function get_table_fields($table_name) {

    global $dbname;
    $id = "_id";

    # These indexes are special in that they link phases
    # together and hence, can and do show up in _POST
    if ($table_name == "test_build")
        $special_indexes = array("mpi_install$id");
    elseif ($table_name == "test_run")
        $special_indexes = array("test_build$id");

    # Crude way to tell whether a field is an index
    $is_not_index_clause =
           "\n\t (table_name = '$table_name' AND NOT " .
           "\n\t (data_type = 'integer' AND " .
           "\n\t column_name ~ '_id$' AND " .
           "\n\t table_catalog = '$dbname'))";

    $is_special_index_clause = 
           "\n\t (table_name = '$table_name' AND " .
           "\n\t (column_name = '$special_indexes[0]'))";

    $is_index_columns = array(
            "column_name",
            "data_type",
            "column_default");

    $sql_cmd = "\n   SELECT " . join(",",$is_index_columns) .
               "\n\t FROM information_schema.columns WHERE " .
               "\n\t " . 
                     $is_not_index_clause . " OR " .
                     $is_special_index_clause . ';';

    do_pg_connect();

    # This table will be easier to manage if it's
    # keyed by column, instead of index
    $tmp = array();
    $arr = array();
    $arr = select($sql_cmd);

    foreach ($is_index_columns as $col) {
        $tmp[$col] = array();
        for ($i = 0; $i < sizeof($arr); $i++) {
            $tmp[$col][] = $arr[$i][$col];
        }
    }

    return $tmp;
}

######################################################################
#
# Pulled from submit/index.php
#
######################################################################

# Connect to the Postgres database
function do_pg_connect() {
    global $mtt_database_server;
    global $mtt_database_port;
    global $mtt_database_name;
    global $mtt_database_username;
    global $mtt_database_password;
    global $pgsql_conn;
    static $connected = false;

    # MTT uses time zone independent timestamps
    putenv("PGTZ=GMT");

    if (!$connected) {
        $pgsql_conn = 
            pg_connect("host=$mtt_database_server port=$mtt_database_port dbname=$mtt_database_name user=$mtt_database_username password=$mtt_database_password");
        if (!$pgsql_conn) {
            mtt_abort(400, "\nCould not connect to the $mtt_database_name database; " .
                    "submit this run later." );
        } else {
            $connected = true;
            # Serialize all transactions by default - Safer that way.
            do_pg_query("SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE", false);
            # Set statement timeout to 60 seconds to prevent accidental/malicious long running 
            # queries from wasting system resources.
            do_pg_query("SET statement_timeout = 60000", false);
        }
    }
}

# Execute an SQL query
function do_pg_query($cmd, $silent) {
    do_pg_connect();

    $start = gettimeofday();
    $start = $start['sec'] + ($start['usec'] / 1000000.0);

    debug("\nSQL: $cmd\n");
    if (! ($db_res = pg_query($cmd))) {
        $out = "\nSQL QUERY: " . $cmd .
            "\nSQL ERROR: " . pg_last_error() .
            "\nSQL ERROR: " . pg_result_error();

        # Some errors are unsurprising, allow for silence in
        # such cases
        if (! $silent) {
            mtt_error($out);
        }
    }

    $finish = gettimeofday();
    $finish = $finish['sec'] + ($finish['usec'] / 1000000.0);
    $elapsed = $finish - $start;

    stats("\ndo_pg_query()".
          "\nExecution time: " . round($elapsed, 5) . " seconds" .
          "\nRows affected: "  . pg_affected_rows($db_res) .
          "\nRows retrieved: " . pg_num_rows($db_res));

    if (isset($_GET['stats']) == 'on') {
      if( $elapsed >= 0.1 ) {
        print "<pre>SQL:$cmd</pre>\n";
      }
    }

    global $global_sql_time_elapsed;
    $global_sql_time_elapsed += $elapsed;

    return $db_res;
}

# Fetch scalar value
function select_scalar($cmd) {
    $set = array();
    $set = simple_select($cmd);
    if( $set == NULL ) {
        return NULL;
    }
    return array_shift($set);
}

# Fetch 1D array
function simple_select($cmd) {
    do_pg_connect();

    $rows = null;

    $start = gettimeofday();
    $start = $start['sec'] + ($start['usec'] / 1000000.0);

    debug("\nSQL: $cmd\n");
    if (! ($result = pg_query($cmd))) {
        $out = "\nSQL QUERY: " . $cmd .
            "\nSQL ERROR: " . pg_last_error() .
            "\nSQL ERROR: " . pg_result_error();
        mtt_error($out);
        return NULL;
    }
    $max = pg_num_rows($result);
    for ($i = 0; $i < $max; ++$i) {
        $row = pg_fetch_array($result, $i, PGSQL_NUM);
        $rows[] = $row[0];
    }

    $finish = gettimeofday();
    $finish = $finish['sec'] + ($finish['usec'] / 1000000.0);
    $elapsed = $finish - $start;

    stats("\nsimple_select()".
          "\nExecution time: " . round($elapsed, 5) . " seconds" .
          "\nRows affected: "  . pg_affected_rows($result) .
          "\nRows retrieved: " . pg_num_rows($result));

    if (isset($_GET['stats']) == 'on') {
      if( $elapsed >= 0.1 ) {
        print "<pre>SQL:$cmd</pre>\n";
      }
    }

    global $global_sql_time_elapsed;
    $global_sql_time_elapsed += $elapsed;

    return $rows;
}

# Fetch 2D array
function select($cmd) {
    do_pg_connect();

    $start = gettimeofday();
    $start = $start['sec'] + ($start['usec'] / 1000000.0);

    debug("\nSQL: $cmd\n");
    if (! ($result = pg_query($cmd))) {
        $out = "\nSQL QUERY: " . $cmd .
            "\nSQL ERROR: " . pg_last_error() .
            "\nSQL ERROR: " . pg_result_error();
        mtt_error($out);
        return NULL;
    }

    $finish = gettimeofday();
    $finish = $finish['sec'] + ($finish['usec'] / 1000000.0);
    $elapsed = $finish - $start;

    stats("\nselect()".
          "\nExecution time: " . round($elapsed, 5) . " seconds" .
          "\nRows affected: "  . pg_affected_rows($result) .
          "\nRows retrieved: " . pg_num_rows($result));

    if (isset($_GET['stats']) == 'on') {
      if( $elapsed >= 0.1 ) {
        print "<pre>SQL:$cmd</pre>\n";
      }
    }

    global $global_sql_time_elapsed;
    $global_sql_time_elapsed += $elapsed;

    return pg_fetch_all($result);
}

?>
