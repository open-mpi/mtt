<!--

 Copyright (c) 2006 Sun Microsystems, Inc.
                         All rights reserved.
 $COPYRIGHT$

 Additional copyrights may follow

 $HEADER$

-->

<?php

#
#
# Variables/Functions that map-to/operate-on database constructs
#
#

include_once("$topdir/config.inc");
include_once("$topdir/reporter.inc");

# Setup db connection
$dbname = isset($_GET['db'])   ? $_GET['db']   : "mtt";
$user   = isset($_GET['user']) ? $_GET['user'] : "mtt";
$pass   = "3o4m5p6i";

# Corresponding db tables for "MPI Install", "Test Build", and "Test Run" phases
# X: better as 'table' => 'phase label' ?
$phases['per_script'] = array(
    "installs",
    "builds",
    "runs",
);



$br = " ";
$phase_labels = array(
    "installs" => "MPI" . $br . "Install",
    "builds"   => "Test" . $br . "Build",
    "runs"     => "Test" . $br . "Run",
);
# Corresponding db tables for "MPI Install", "Test Build", and "Test Run" phases
$atoms = array(
    "case",
    "run",
);

# Corresponding db tables for "MPI Install", "Test Build", and "Test Run" phases
$results_types = array(
    "pass",
    "fail",
);

# Note: test_pass/success fields are appended to all SELECTs,
#       and are thus not listed in the following arrays.
#       For now, comment out fields we're not including in the summary report.

# phase => array(fields belonging to phase)

$cluster_field =
    "('<font size=-2>' || platform_id || '<br>' || hostname || '</font>') as cluster";

$field_clauses = array('cluster' => $cluster_field);

# run-key definition
$fields_run_key = array(
    "hostname",
    "start_run_timestamp",
);

# Construct boolean-to-string casts for pass/fail (t/f) columns
# We differentiate between _case fails and _run fails
# A case is the single atomic test case (e.g., gmake foo, cc foo, or
# mpirun foo).
# A run is a collection of cases.
foreach ($phases['per_script'] as $ph) {
    $results['from_perm_tbl'][$ph] =
        array("(CASE WHEN success='t' THEN 'pass_case_$ph' END) as pass",
              "(CASE WHEN success='f' THEN 'fail_case_$ph' END) as fail");
}

# Construct the result aggregates

# A single pass/fail is based on the passing of test case
foreach ($phases['per_script'] as $ph) {
    $results['from_tmp_tbl'][$ph]['by_case'] = array();
    foreach (array("pass","fail") as $res) {

        $agg = "COUNT(CASE WHEN " . $res . " = '" .
                                    $res . "_case" . "_$ph' " .
                      "THEN '"    . $res . "_case" . "_$ph' END) " .
                      "as "       . $res . "_case" . "_$ph";

        array_push($results['from_tmp_tbl'][$ph]['by_case'], $agg);
    }
}

# A run pass is a collection of test cases without a single failure
# and at least one pass
foreach ($phases['per_script'] as $ph) {

    $results['from_tmp_tbl'][$ph]['by_run'] = array();

    $agg_pass = "COUNT(CASE WHEN pass_case_$ph > 0 " .
                    "AND fail_case_$ph < 1 " .
                    "THEN   'pass_run_$ph' " .
                    "END) as pass_run_$ph";

    $agg_fail = "COUNT(CASE WHEN fail_case_$ph > 0 " .
                    "THEN   'fail_run_$ph' " .
                    "END) as fail_run_$ph";

    array_push($results['from_tmp_tbl'][$ph]['by_run'], $agg_pass);
    array_push($results['from_tmp_tbl'][$ph]['by_run'], $agg_fail);
}

# There might be a lengthy list of possiblities for result labels
# so let's generate them via loop
foreach ($phases['per_script'] as $phase) {
    foreach (array("case", "run") as $type) {
        $field_labels["pass_" . $type . "_$phase"] = 'Pass';
        $field_labels["fail_" . $type . "_$phase"] = 'Fail';
        $field_labels[substr($phase, 0, 1) . "pass"] = 'Pass';
        $field_labels[substr($phase, 0, 1) . "fail"] = 'Fail';
    }
}

# Translate db result strings
$translate_data_cell = array(
    't' => 'pass',
    'f' => 'fail',
    'ompi-nightly-v1.0' => 'Open MPI v1.0',
    'ompi-nightly-v1.1' => 'Open MPI v1.1',
    'ompi-nightly-v1.2' => 'Open MPI v1.2',
    'ompi-nightly-v1.3' => 'Open MPI v1.3',
    'ompi-nightly-trunk' => 'Open MPI trunk',
);

$once_db_table = "once";

# This var is a little silly since there is currently only one 'level' of
# detail per invocation of this script, but maybe it will get used again
# when/if we add a feature that breaks-up reports into seperate tables
$level = -1;

$linked_stuff_top = array(
    "stdout",
    "stderr",
    "environment",
);

$linked_stuff_bottom = array(
    "test_duration_interval",
);

# pg_query_ that returns a 1D list
function pg_query_simple($cmd, $conn) {

    $rows = array();
    if ($res = pg_query($conn, $cmd)) {
        while ($row = pg_fetch_row($res)) {
            array_push($rows, $row);
        }
    }
    else {
        debug("\n<br>postgres: " . pg_last_error() . "\n" . pg_result_error());
    }
    return array_map('join',$rows);
}

# pg_query that returns a 2D list
function pg_query_($cmd, $conn) {

    $rows = array();
    if ($res = pg_query($conn, $cmd)) {
        while ($row = pg_fetch_row($res)) {
            array_push($rows, $row);
        }

        # Think about the advantages in returning a hash of results
        # versus an array (esp. wrt readability)
        # $rows = pg_fetch_all($res);
    }
    else {
        debug("\n<br>postgres: " . pg_last_error() . "\n" . pg_result_error());
    }
    return $rows;
}

# Take a list of phases and the type of atom, and return a list of result
# aggregates for those phases
function get_phase_result_selects($phases, $atom) {

    global $results;

    $tmp = array();

    foreach ($phases as $p) {
        $tmp = array_merge($tmp, $results['from_tmp_tbl'][$p][$atom]);
    }
    return $tmp;
}

# Return list of fields that are not run_key fields. Useful for filtering out
# run_key fields when doing a by_run query
function get_non_run_key_params($arr) {

    global $fields_run_key;

    $run_keys = array();
    $tmp = array();
    $run_keys = array_flip($fields_run_key);

    foreach ($arr as $a)
        if (! isset($run_keys[$a]))
            array_push($tmp, $a);

    return $tmp;
}

# Take in a filter (e.g., 'yesterday', 'today', etc.), and return the SQL date
# filter
# X: Create a get_en_date_string function
function get_date_filter($filter) {

    global $words_to_numerals;

    $filters = array();

    $sep = '[\s\+]';

    # (Currently, we're only doing all-levels filtering on timestamp)
    if (@preg_match("/yesterday/i", $filter, $m)) {
        array_push($filters, "start_test_timestamp > 'yesterday'");

    }
    elseif (@preg_match("/today/i", $filter, $m)) {
        array_push($filters, "start_test_timestamp > date_trunc('day', now())");
    }
    elseif (@preg_match("/past$sep*(\w+)$sep*(\w+)/i", $filter, $m)) {
        array_push($filters, "start_test_timestamp > now() - interval '" .
                    $words_to_numerals[$m[1]] . " " . $m[2] . "'");

    }
    return $filters;
}

# Take "field as f", return f
function get_as_alias($str) {

    if (@preg_match("/\s+as\s+(\w+)/i", $str, $m)) {
        return $m[1];
    }
    else {
        return $str;
    }
}

# Take an sql filter and explain it in plain-english
# Clean this up - too many regexps that could be consolidated
# Would it make more sense to go cgi_to_en?
# X: have this return a 2-element array, vs. a string
#    field => filter
# X: regexps
function sql_to_en($str) {

    global $translate_data_cell;
    global $field_labels;
    global $gray, $lgray, $llgray;

    $date_format = "m-d-Y";
    $time_format = "H:i:s";

    # html quotes
    $oq = ''; # '&#145;';
    $cq = ''; # '&#146;';

    # regexp quotes
    $qs = '\x22\x27';
    $q = '[\x22|\x27]?';
    $dash = "<b> - </b>";
    $ca = '\^'; # carrot
    $ds = '\$'; # dollar sign

    $english = "";

    if (@preg_match("/(\w+_timestamp)/i", $str, $m)) {

        # E.g., start_test_timestamp > now() - interval '3 Days'
        #       start_test_timestamp > date_trunc('day', now())
        # X: Cover other comparisons for timestamps
        if (preg_match("/([><=])\s*$q\s*now\(\)\s*-\s*interval\s*'(\d+)\s*(\w+)'$q/i", $str, $m)) {

            $op = $m[1];
            $num = $m[2];
            $units = $m[3];

            if (preg_match("/day/i", $units))
                $days = 1 * $num;
            elseif (preg_match("/week/i", $units))
                $days = 7 * $num;
            elseif (preg_match("/month/i", $units))
                $days = 30 * $num;          # Doh, not all months are 30!
            elseif (preg_match("/year/i", $units))
                $days = 365 * $num;

            $english .=
                  date($date_format, time() - ($days * 24 * 60 * 60)) . " 00:00:00 " . $dash .
                  date($date_format . " " . $time_format);
        }
        # Yesterday in postgres means yesterday at 12:00 am
        elseif (preg_match("/yesterday/i", $str, $m)) {

            $english .=
                  date($date_format, time() - (1 * 24 * 60 * 60)) . " 00:00:00 " .  $dash .
                  date($date_format . " " . $time_format);
        }
        # Today
        # E.g., start_test_timestamp > date_trunc('day', now())
        # Watch out for them darn parenthesees, they need to be escaped
        elseif (preg_match("/date_trunc\(\s*$q"."day"."$q/i", $str)) {

            $english .=
                  date($date_format, time()) . " 00:00:00 " . $dash .
                  date($date_format . " " . $time_format);
        }
        $english .= date(" O");
        $english = "<td bgcolor=$lgray>Date Range<td bgcolor=$llgray>" . $english;
    }
    # success = 't|f'
    elseif (preg_match("/(test_pass|success)\s*=\s*$q(\w+)$q/i", $str, $m)) {

        $what   = $m[1];
        $filter = $m[2];
        $filter = $translate_data_cell[$filter] ? $translate_data_cell[$filter] : $filter;

        $english .= "<td bgcolor=$lgray>$what <td bgcolor=$llgray>$oq$filter$cq";
    }
    # field = 'value'
    elseif (preg_match("/(\w+)\s*([=<>])\s*$q([^$qs]+)$q/i", $str, $m)) {

        $field  = $m[1];
        $op     = $m[2];
        $filter = $m[3];
        $field  = $field_labels[$field] ? $field_labels[$field] : $field;

        $english .= "<td bgcolor=$lgray>$field <td bgcolor=$llgray>$oq$filter$cq";

        if ($op == '=')
            $english .= " (equals)";
        elseif ($op == '<')
            $english .= " (less than)";
        elseif ($op == '>')
            $english .= " (greater than)";
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

        $english .= "<td bgcolor=$lgray>$field <td bgcolor=$llgray>$oq$filter$cq $type";
    }
    # unclassified filter
    else {
        $english = "<td bgcolor=$lgray>Filter<td bgcolor=$llgray>$str";
    }

    return $english;
}

?>
