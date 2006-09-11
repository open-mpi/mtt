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

include_once("$topdir/config.inc");
include_once("$topdir/reporter.inc");
include_once("$topdir/html.inc");

# MTT uses time zone independent timestamps
putenv("PGTZ=GMT");

# Corresponding db tables for "MPI Install", "Test Build", and "Test Run" phases
# X: better as 'table' => 'phase label' ?
$phases['per_script'] = array(
    "installs",
    "builds",
    "runs",
);

$tables = array(
    "once",
    "general_a",
    "general_b",
);

$once_db_table = "once";

$Filters = "Filters";
$textfield_tables = array(
    "general_a" => array( "label" => null,
                          "phases" => array( "runs","builds","installs" ),
                   ),
    "runs"      => array( "label" => "Test Run $Filters",
                          "phases" => array( "runs" ),
                   ),
    "general_b" => array( "label" => "MPI Install/Test Build $Filters",
                          "phases" => array( "builds","installs" ),
                   ),
);

$string_filter_types = array("contains","does not contain", "begins with", "ends with");
$numeric_filter_types = array("equals","less than","greater than");

$columns = array();

# We'll define these fields instead of fetch from information_schema
# so that we can order/process/categorize them how we want
$columns["general_a"] = array(
    "stderr"                   => $string_filter_types,
    "stdout"                   => $string_filter_types,
    "environment"              => $string_filter_types,
    "configure_arguments"      => $string_filter_types,
    "result_message"           => $string_filter_types,
    "mpi_get_section_name"     => $string_filter_types,
    "mpi_install_section_name" => $string_filter_types,
    #"vpath_mode"              => $string_filter_types,
    #"start_test_timestamp"    => $string_filter_types,
    #"submit_test_timestamp"   => $string_filter_types,
    #"test_duration_interval"  => $string_filter_types,
    #"merge_stdout_stderr"     => $string_filter_types,
    #"mpi_details"             => $string_filter_types,
);
$columns["general_b"] = array(
    "compiler_name"    => $string_filter_types,
    "compiler_version" => $string_filter_types,
);

$columns["advanced"] = array(
    "mpi_details"               => $string_filter_types,
    "merge_stdout_stderr"       => $string_filter_types,
    "vpath_mode"                => $string_filter_types,
    "start_test_timestamp"      => $string_filter_types,
    "submit_test_timestamp"     => $string_filter_types,
    "test_duration_interval"    => $string_filter_types,
    #"result_message"           => $string_filter_types,
    #"environment"              => $string_filter_types,
    #"configure_arguments"      => $string_filter_types,
    #"mpi_get_section_name"     => $string_filter_types,
    #"mpi_install_section_name" => $string_filter_types,
);

$cluster_field =
    "platform_id as cluster";

$columns['once'] = array(
    "platform_hardware" => $string_filter_types,
    "os_name"           => $string_filter_types,
    "os_version"        => $string_filter_types,
    "mpi_name"          => $string_filter_types,
    "mpi_version"       => $string_filter_types,

    "$cluster_field"    => $string_filter_types,

    #"hostname"         => $string_filter_types,
    #"platform_type"    => $string_filter_types,
    #"platform_id"      => $string_filter_types,
);

$columns["runs"] = array(
    "test_name"               => $string_filter_types,
    "test_command"            => $string_filter_types,
    "test_np"                 => $numeric_filter_types,
    "test_build_section_name" => $string_filter_types,
    "test_run_section_name"   => $string_filter_types,
);

$columns["installs"] = 
    $columns["general_b"];
$columns["builds"] = array_merge(
    array("test_build_section_name" => $string_filter_types),
    array($columns["general_b"])
);
$br = " ";
$phase_labels = array(
    "installs" => "MPI" . $br . "Install",
    "builds"   => "Test" . $br . "Build",
    "runs"     => "Test" . $br . "Run",
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

$field_clauses = array('cluster' => $cluster_field);

# run-key definition
$fields_run_key = array(
    "hostname",
    "start_run_timestamp",
);

# Gather selectable menu items

# Global timestamp
# X: To avoid conflicting with a 'by_run' query, we use _test_timestamp
#    and not run_timestamp. We may want to allow for either.
$timestamp = 'start_test_timestamp';
$main_menu[$timestamp]["options"] = array(
    "*Today",
    "Since Yesterday",
);

$i = 0;
foreach (array_keys($words_to_numerals) as $n) {
    if ($i++ > 5)
        break;
    array_push($main_menu[$timestamp]["options"], "Past $n Days");
}
$i = 0;
foreach (array_keys($words_to_numerals) as $n) {
    if ($i++ > 5)
        break;
    array_push($main_menu[$timestamp]["options"], "Past $n Weeks");
}
$i = 0;
foreach (array_keys($words_to_numerals) as $n) {
    if ($i++ > 4)
        break;
    array_push($main_menu[$timestamp]["options"], "Past $n Months");
}
array_push($main_menu[$timestamp]["options"], $All);

# Timestamp is an oddball field, in that it has more than one
# way to aggregate
# X: Add week-by-week
$agg_timestamp_selects = array(
    "*-"               => null,
    "Month-by-Month"   => "substring($timestamp from 0 for 8) as $timestamp",
    "Day-by-Day"       => "substring($timestamp from 0 for 11) as $timestamp",
    "Hour-by-Hour"     => "substring($timestamp from 0 for 14) || ':00' as $timestamp",
    "Minute-by-Minute" => "substring($timestamp from 0 for 17) as $timestamp",
    "Second-by-Second" => $timestamp,
);

$main_menu["agg_timestamp"]["options"] = array_keys($agg_timestamp_selects);

# Note: 'phase' is a special key in that it is not a field in the db
$main_menu["phase"]["options"] = array(
    $All,
    "installs",
    "builds",
    "runs",
);

# X: This javascript is *broken* due to undefined tf_0 and ft_0 fields
# X: Loop through elems in HTML 'name' attribute, instead of this absurd
#    get_phase_specific_fields function
#
# Add some javascript actions for this menu (gray out appropriate
# phase-specific fields)
$main_menu["phase"]["javascript"] = array(
    # $All
    "enable(" . join(",", get_phase_specific_fields(array("installs","builds","runs"))) . ");",
    # installs
    "disable(" . join(",", get_phase_specific_fields(array("runs"))) . ");" .
    "enable(" . join(",", get_phase_specific_fields(array("installs"))) . ");",
    # builds
    "disable(" . join(",", get_phase_specific_fields(array("runs"))) . ");" .
    "enable(" . join(",", get_phase_specific_fields(array("builds"))) . ");",
    # runs
    "disable(" . join(",", get_phase_specific_fields(array("installs","builds"))) . ");" .
    "enable(" . join(",", get_phase_specific_fields(array("runs"))) . ");",
);

$main_menu["success"]["options"] = array(
    $All,
    "Pass",
    "Fail",
);

# Setup db connection
$dbname = isset($_GET['db'])   ? $_GET['db']   : "mtt";
$user   = isset($_GET['user']) ? $_GET['user'] : "mtt";
$pass   = "3o4m5p6i";

if (! ($conn = pg_connect("host=localhost port=5432 dbname=$dbname user=$user password=$pass")))
    exit_("<br><b><i>Could not connect to database server.</i></b>");

$menu = array();
$menu = populate_menu(array_keys($columns["once"]), "once");

pg_close();

$by_atoms = array(
    "*by_test_case" => "By test case",
    "by_test_run" => "By test run",
);

$domain  = "http://www.open-mpi.org";

$client = "MTT";

$results['from_perm_tbl'] = array();
$results['from_tmp_tbl'] = array();

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

# Return list of phase specific fields for each phase
# passed in
function get_phase_specific_fields($phases) {

    global $columns;
    global $cgi_abbrevs;

    $fields = array();

    $field_types = array($cgi_abbrevs["textfield"], $cgi_abbrevs["filter_types"]);

    foreach ($phases as $phase) {
        foreach (array_keys($columns[$phase]) as $f) {
            foreach ($field_types as $ft) {
                array_push($fields, $ft . $f);
            }
        }
    }
    return $fields;
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
    $field = "";
    $filter = "";

    if (preg_match("/(\w+_timestamp)/i", $str, $m)) {

        $field = "Date Range";

        # E.g., start_test_timestamp > now() - interval '3 Days'
        #       start_test_timestamp > date_trunc('day', now())
        # X: Cover other comparisons for timestamps
        if (preg_match("/([><=])\s*$q\s*now\(\)\s*-\s*interval\s*'(\d+)\s*(\w+)'$q/i", $str, $m)) {

            $op = $m[1];
            $num = $m[2];
            $units = $m[3];

            $days = 1;
            $hours = 1;
            $mins = 1;
            $secs = 1;

            if (preg_match("/year/i", $units)) {
                $days  = 365 * $num;
                $hours = 24;
                $mins  = 60;
                $secs  = 60;
            }
            elseif (preg_match("/month/i", $units)) {
                $days  = 30 * $num;          # Doh, not all months are 30!
                $hours = 24;
                $mins  = 60;
                $secs  = 60;
            }
            elseif (preg_match("/week/i", $units)) {
                $days  = 7 * $num;
                $hours = 24;
                $mins  = 60;
                $secs  = 60;
            }
            elseif (preg_match("/day/i", $units)) {
                $days  = 1 * $num;
                $hours = 24;
                $mins  = 60;
                $secs  = 60;
            }
            elseif (preg_match("/hour/i", $units)) {
                $hours = $num;
                $mins  = 60;
                $secs  = 60;
            }
            elseif (preg_match("/minute/i", $units)) {
                $mins = $num;
                $secs = 60;
            }
            elseif (preg_match("/second/i", $units)) {
                $secs = $num;
            }

            $format = $date_format . " " . $time_format;

            $filter .=
                  date($format,
                        time() - ($days * $hours * $mins * $secs)) . " " . $dash .
                  date($format);
        }
        # Yesterday in postgres means yesterday at 12:00 am
        elseif (preg_match("/yesterday/i", $str, $m)) {

            $filter .=
                  date($date_format, time() - (1 * 24 * 60 * 60)) . " 00:00:00 " .  $dash .
                  date($date_format . " " . $time_format);
        }
        # Today
        # E.g., start_test_timestamp > date_trunc('day', now())
        # Watch out for them darn parenthesees, they need to be escaped
        elseif (preg_match("/date_trunc\(\s*$q"."day"."$q/i", $str)) {

            $filter .=
                  date($date_format, time()) . " 00:00:00 " . $dash .
                  date($date_format . " " . $time_format);
        }
        $filter .= date(" O");
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

?>
