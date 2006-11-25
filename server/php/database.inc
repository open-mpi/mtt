<?php

#
# Copyright (c) 2006 Sun Microsystems, Inc.
#                         All rights reserved.
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

$ompi_home = '/l/osl/www/doc/www.open-mpi.org';
include_once("$ompi_home/dbpassword.inc");
include_once("$topdir/reporter.inc");

$dbname = 'mtt3';

# Setup db connection
if (isset($_GET['db']))
    if (preg_match("/mtt/i", $_GET['db']))
        $dbname = $_GET['db'];

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

function do_pg_connect() {
    global $dbname;
    global $user;
    global $pass;
    global $pgsql_conn;
    static $connected = false;

    # MTT uses time zone independent timestamps
    putenv("PGTZ=GMT");

    if (!$connected) {
        $pgsql_conn = 
            pg_connect("host=localhost port=5432 dbname=$dbname user=$user password=$pass");
        $connected = true;
    }
}

function do_pg_query($cmd) {
    do_pg_connect();

    $start = time();

    debug("\nSQL: $cmd\n");
    if (! ($db_res = pg_query($cmd))) {
        print("\npostgres: " . pg_last_error() . "\n" .
                    pg_result_error());
    }

    $finish = time();
    $elapsed = $finish - $start;

    debug("\nExecution time: " . $elapsed . " seconds\n");
    debug("\nRows affected: " . pg_affected_rows($db_res) . "\n");

    return $db_res;
}

# Fetch scalar value
function select_scalar($cmd) {
    do_pg_connect();

    $rows = null;

    debug("\nSQL: $cmd\n");
    if (! ($result = pg_query($cmd))) {
        print("\npostgres: " . pg_last_error() . "\n" .
                  pg_result_error());
    }
    $max = pg_num_rows($result);
    for ($i = 0; $i < $max; ++$i) {
        $row = pg_fetch_array($result, $i, PGSQL_NUM);
        $rows[] = $row[0];
    }
    return array_shift($rows);
}

# Fetch 1D array
function simple_select($cmd) {
    do_pg_connect();

    $rows = null;

    debug("\nSQL: $cmd\n");
    if (! ($result = pg_query($cmd))) {
        print("\npostgres: " . pg_last_error() . "\n" .
                  pg_result_error());
    }
    $max = pg_num_rows($result);
    for ($i = 0; $i < $max; ++$i) {
        $row = pg_fetch_array($result, $i, PGSQL_NUM);
        $rows[] = $row[0];
    }
    return $rows;
}

# Fetch 2D array
function select($cmd) {
    do_pg_connect();

    debug("\nSQL: $cmd\n");
    if (! ($result = pg_query($cmd))) {
        print("\npostgres: " . pg_last_error() . "\n" .
                  pg_result_error());
    }
    return pg_fetch_all($result);
}

?>
