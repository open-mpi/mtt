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
include_once("$topdir/config.inc");
include_once("$topdir/reporter.inc");
include_once("$topdir/html.inc");

# Return a table->field->values hash
# to be used to generate menus


$dbname = 'mtt2';

# Setup db connection
if (isset($_GET['db']))
    if (preg_match("/mtt/i", $_GET['db']))
        $dbname = $_GET['db'];

# Take in a filter (e.g., 'yesterday', 'today', etc.), and return the SQL date
# filter
# X: Create a get_en_date_string function
function get_date_filter($filter) {

    global $words_to_numerals;
    global $dash;
    global $cgi_abbrevs;

    $filters = array();

    $sep = '[\s\+]';

    # (Currently, we're only doing all-levels filtering on timestamp)
    if (preg_match("/yesterday/i", $filter, $m)) {
        array_push($filters, "start_test_timestamp > 'yesterday'");
    }
    elseif (preg_match("/today/i", $filter, $m)) {
        array_push($filters, "start_test_timestamp > date_trunc('day', now())");
    }
    elseif (preg_match("/past$sep*(\w+)$sep*(\w+)/i", $filter, $m)) {
        array_push($filters, "start_test_timestamp > now() - interval '" .
                    (preg_match("/\d/", $m[1]) ? $m[1] : $words_to_numerals[$m[1]]) . " " .
                    $m[2] . "'");

    }
    elseif (preg_match("/(.*)$dash(.*)/i", $filter, $m)) {

        array_push($filters,
                    "start_test_timestamp > " .
                    "'" .  $m[1] . "'" .
                    ""
        );
        array_push($filters,
                    "start_test_timestamp < " .
                    "'" .  $m[2] . "'" .
                    ""
        );
    }
    return $filters;
}

# Take "field as f", return f
function get_as_alias($str) {

    if (preg_match("/\s+as\s+(\w+)/i", $str, $m)) {
        return $m[1];
    }
    else {
        return $str;
    }
}

$dash = " through ";

# Take an sql filter and explain it in plain-english
# X: Clean this up - too many regexps that could be consolidated
# Would it make more sense to go cgi_to_en?
function sql_to_en($str) {

    global $translate_data_cell;
    global $field_labels;
    global $gray, $lgray, $llgray;
    global $dash;
    global $cgi_abbrevs, $timestamp;
    global $abs_date_range, $rel_date_range;
    global $dbname, $user, $pass;

    $date_format = "m-d-Y";
    $time_format = "H:i:s";

    # html quotes
    $oq = ''; # '&#145;';
    $cq = ''; # '&#146;';

    # regexp quotes
    $qs = '\x22\x27';
    $q = '[\x22|\x27]?';
    $ca = '\^'; # carrot
    $ds = '\$'; # dollar sign

    $english = "";
    $field = "";
    $filter = "";

    if (preg_match("/(\w+_timestamp)/i", $str, $m)) {

        if (! ($conn = pg_connect("host=localhost port=5432 dbname=$dbname user=$user password=$pass")))
            exit_("<br><b><i>Could not connect to database server.</i></b>");

        $field = "Date Range (GMT)";

        # Unfortunate to have to resort to looking at input params in this function
        $abs_date_range = $_GET[$cgi_abbrevs['mainfield'] . $timestamp];

        if (preg_match("/$dash/i", $abs_date_range)) {
            if (preg_match("/>/", $str))  # better way to not duplicate date range desc?
                $filter = $abs_date_range;
            else {
                $filter = null;
                $field = null;
            }
        }

        # E.g., start_test_timestamp > now() - interval '3 Days'
        #       start_test_timestamp > date_trunc('day', now())
        elseif (preg_match("/([><=])\s*$q\s*((now\(\))\s*-\s*interval\s*'(\d+)\s*(\w+)')$q/i", $str, $m)) {

            $op = $m[1];
            $start = $m[2];
            $end = $m[3];
            $num = $m[4];
            $units = $m[5];

            $start = array_shift(pg_query_simple(
                        "SELECT substring(date_trunc('second', $start) from 0 for 20)", $conn));
            $end = array_shift(pg_query_simple(
                        "SELECT substring(date_trunc('second', $end) from 0 for 20)", $conn));
            $filter = $start . $dash . $end;
        }
        elseif (preg_match("/yesterday/i", $str, $m)) {

            $start = array_shift(pg_query_simple(
                        "SELECT substring(date_trunc('second', TIMESTAMP 'yesterday') from 0 for 20)", $conn));
            $end = array_shift(pg_query_simple(
                        "SELECT substring(date_trunc('second', now()) from 0 for 20)", $conn));
            $filter = $start . $dash . $end;
        }
        elseif (preg_match("/date_trunc\(\s*$q"."day"."$q/i", $str)) {

            $start = array_shift(pg_query_simple(
                        "SELECT substring(date_trunc('day', now()) from 0 for 20)", $conn));
            $end = array_shift(pg_query_simple(
                        "SELECT substring(date_trunc('second', now()) from 0 for 20)", $conn));
            $filter = $start . $dash . $end;
        }
    }
    # success = 't|f'
    elseif (preg_match("/(test_pass|success)\s*=\s*$q(\w+)$q/i", $str, $m)) {

        $field  = $m[1];
        $filter = $m[2];
        $filter = $translate_data_cell[$filter] ? $translate_data_cell[$filter] : $filter;
    }
    # field = 'value'
    elseif (preg_match("/(\w+)\s*([=<>])\s*$q([^$qs]+)$q/i", $str, $m)) {

        $field  = $m[1];
        $op     = $m[2];
        $filter = $m[3];
        $field  = $field_labels[$field] ? $field_labels[$field] : $field;

        if ($op == '=')
            $filter .= " (equals)";
        elseif ($op == '<')
            $filter .= " (less than)";
        elseif ($op == '>')
            $filter .= " (greater than)";
    }
    # field ~ value
    elseif (preg_match("/(\w+)\s*\\!?~\s*$q$ca?([^$qs$ds]+)$ds?$q/i", $str, $m)) {

        $field  = $m[1];
        $filter = $m[2];
        $field  = $field_labels[$field] ? $field_labels[$field] : $field;

        if (preg_match('/\^/', $str))
            $type  = " (begins with)";
        elseif (preg_match('/\$/', $str))
            $type  = " (ends with)";
        elseif (preg_match('/\!/', $str))
            $type  = " (does not contain)";
        else
            $type  = " (contains)";

        $filter .= $type;
    }
    # unclassified filter
    else {
        $field = "Filter".
        $filter = $str;
    }

    $tuple[0] = array();
    $tuple[0] = $field;
    $tuple[1] = $filter;

    return $tuple;
}

# Fetch all values in database for each item in list
function populate_menu($list, $table) {

    global $conn;

    foreach ($list as $field) {

        if (preg_match("/timestamp/i", $field)) {
            $clause = "substring($field from 0 for 11) as $field";
        } else {
            $clause = $field;
        }

        $alias = get_as_alias($field);

        $cmd = "SELECT $clause FROM $table " .
            "GROUP BY $alias " .
            "ORDER BY $alias ;";

        debug_sql($cmd);

        $rows = array_map('html_to_txt2', pg_query_simple($cmd, $conn));

        $menu[$alias] = array();
        $menu[$alias] = $rows;
    }
    return $menu;
}

# Function used to determine which _POST fields
# to INSERT. Prevent non-existent fields from being
# INSERTed
function get_table_fields($table_name) {

    global $dbname;
    global $id;

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

    if (!$connected) {
        $pgsql_conn = pg_connect("host=localhost port=5432 dbname=$dbname user=$user password=$pass");
        $connected = true;
        pg_trace('/nfs/rontok/xraid/users/emallove/pgsql.trace');
        debug("\npg_options: " . var_export(pg_options($pgsql_conn)));
    }
}

function do_pg_query($cmd) {
    do_pg_connect();

    debug("\nSQL: $cmd\n");
    if (! ($db_res = pg_query($cmd))) {
        debug("\npostgres: " . pg_last_error() . "\n" . pg_result_error());
    }
    debug("\nrows affected: " . pg_affected_rows($db_res) . "\n");
}

# Fetch 1D array
function simple_select($cmd) {
    do_pg_connect();

    $rows = null;

    debug("\nSQL: $cmd\n");
    if (! ($result = pg_query($cmd))) {
        debug("\npostgres: " . pg_last_error() . "\n" .
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
        debug("\npostgres: " . pg_last_error() . "\n" .
                  pg_result_error());
    }
    return pg_fetch_all($result);
}

######################################################################

?>
