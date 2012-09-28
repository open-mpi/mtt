<?php
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2006-2007 Sun Microsystems, Inc.  All rights reserved.

#
#
# stats/index.php - 
#
# Display Stats regarding MTT usage
#
#

$head_html = null;
$body_html_prefix = null;
$body_html_suffix = null;


$topdir = '..';
if (file_exists("$topdir/config.inc")) {
    include_once("$topdir/config.inc");
}
include_once("$topdir/google-analytics.inc");
include_once("$topdir/reporter/reporter.inc");
# For debug()
include_once("$topdir/reporter/util.inc");

if (array_key_exists("db", $_GET) &&
    preg_match("/mtt/i", $_GET['db'])) {
    $mtt_database_name = $_GET['db'];
}
$pgsql_conn = null;

date_default_timezone_set('America/New_York');

$start_collection_date = "DATE '".date("Y-m-01")."'";
$end_collection_date   = "DATE '".date("Y-m-01")."' + interval '1 month'";
$given_dates = array_key_exists("dates", $_GET) ? $_GET['dates'] : date("Y-m-01 - Y-m-d");

$total_hash = null;
$focus_where = null;
$basic_select = ("sum(num_mpi_install_pass + num_mpi_install_fail) as mpi_install, ".
                 "sum(num_test_build_pass + num_test_build_fail) as test_build, ".
                 "sum(num_test_run_pass + num_test_run_fail + num_test_run_timed) as test_run, ".
                 "sum(num_test_run_perf) as perf ");
$basic_where = ("is_day = 't'");
$basic_from  = ("FROM mtt_stats_contrib ");

#######################################
# Determine the date range
#######################################

print("<html>" .
      "\n<head>" .
      "\n<title>Open MPI Test Statistics</title>" . $head_html .
      "\n</head>".
      "\n<body>". $body_html_prefix . print_ga() .
      "\n");

process_stat_dates();
process_stat_input();

#display_debug_input();
display_stats_header();

print(html_select_stats());

display_stats();

# All done
pg_close();
print("\n<hr>". $body_html_suffix .
      "\n</body>".
      "\n</html>");


######################################################################
function display_stats() {
    global $start_collection_date;
    global $end_collection_date;

    #
    # Get totals
    #
    get_total_results();

    #
    # Display database stats
    #
    display_stats_database();

    #
    # For each Org., how many results were accumulated?
    #
    display_stats_org();

    #
    # For each Platform, how many results were accumulated?
    #
    display_stats_platform();

    #
    # For each OS, how many results were accumulated?
    #
    display_stats_os();

    #
    # For each Compiler, how many results were accumulated?
    #
    display_stats_compiler();

    #
    # For each MPI Get, how many results were accumulated?
    #
    display_stats_mpi_get();

    #
    # For each Test Suite, how many results were accumulated?
    #
    display_stats_test_suite();
}

function display_stats_database() {
    global $start_collection_date;
    global $end_collection_date;
    $nl  = "\n";
    $nlt = "\n\t";
    $database_hash = array();

    $get_database_all =
        ("SELECT collection_date, ".$nlt.
         "(size_db/(1024*1024*1024)) as db_size_gb, ".$nlt.
         "(size_db/(1024*1024)) as db_size_mb, ".$nlt.
         "num_tuples, ".$nlt.
         "num_tuples_mpi_install, ".$nlt.
         "num_tuples_test_build, ".$nlt.
         "num_tuples_test_run ".$nl.
         "FROM mtt_stats_database ".$nl.
         "WHERE collection_date >= $start_collection_date AND ".$nl.
         "      collection_date <= $end_collection_date ".$nl.
         "ORDER BY collection_date DESC");

    $database_hash = select($get_database_all);
    print_query_stmt("Database Statistics");
    print_query_db_table($database_hash);

    return 0;
}

function display_stats_org() {
    global $start_collection_date;
    global $end_collection_date;
    global $total_hash;
    global $basic_select;
    global $basic_from ;
    global $basic_where;

    $get_contrib_all =
        ("SELECT org_name, ".
         $basic_select.
         $basic_from.
         "WHERE ".
         $basic_where.
         "GROUP BY org_name ".
         "ORDER BY test_run DESC");

    $org_hash   = select($get_contrib_all);
    print_query_stmt("For each Organization, how many results did each accumulate?");
    print_query_table("Org. Name", "org_name", $org_hash, $total_hash);

    return 0;
}

function display_stats_platform() {
    global $start_collection_date;
    global $end_collection_date;
    global $total_hash;
    global $basic_select;
    global $basic_from ;
    global $basic_where;

    $get_contrib_all =
        ("SELECT platform_name, ".
         $basic_select.
         $basic_from.
         "WHERE ".
         $basic_where.
         "GROUP BY platform_name ".
         "ORDER BY test_run DESC");

    $platform_hash   = select($get_contrib_all);
    print_query_stmt("For each Platform, how many results did each accumulate?");
    print_query_table("Platform Name", "platform_name", $platform_hash, $total_hash);

    return 0;
}

function display_stats_os() {
    global $start_collection_date;
    global $end_collection_date;
    global $total_hash;
    global $basic_select;
    global $basic_from ;
    global $basic_where;

    $get_contrib_all =
        ("SELECT os_name, ".
         $basic_select.
         $basic_from.
         "WHERE ".
         $basic_where.
         "GROUP BY os_name ".
         "ORDER BY test_run DESC");

    $os_hash    = select($get_contrib_all);
    print_query_stmt("For each OS, how many results did each accumulate?");
    print_query_table("OS Name", "os_name", $os_hash, $total_hash);

    return 0;
}

function display_stats_compiler() {
    global $start_collection_date;
    global $end_collection_date;
    global $total_hash;
    global $basic_select;
    global $basic_from ;
    global $basic_where;

    $get_contrib_all =
        ("SELECT mpi_install_compiler_name, ".
         $basic_select.
         $basic_from.
         "WHERE ".
         $basic_where.
         "GROUP BY mpi_install_compiler_name ".
         "ORDER BY test_run DESC");

    $compiler_hash   = select($get_contrib_all);
    print_query_stmt("For each Compiler, how many results did each accumulate?");
    print_query_table("Compiler Name", "mpi_install_compiler_name", $compiler_hash, $total_hash);

    return 0;
}

function display_stats_mpi_get() {
    global $start_collection_date;
    global $end_collection_date;
    global $total_hash;
    global $basic_select;
    global $basic_from ;
    global $basic_where;

    $get_contrib_all =
        ("SELECT mpi_get_name, ".
         $basic_select.
         $basic_from.
         "WHERE ".
         $basic_where.
         "GROUP BY mpi_get_name ".
         "ORDER BY test_run DESC");

    $mpi_get_hash = select($get_contrib_all);
    print_query_stmt("For each MPI_Get, how many results did each accumulate?");
    print_query_table("MPI Get Name", "mpi_get_name", $mpi_get_hash, $total_hash);

    return 0;
}

function display_stats_test_suite() {
    global $start_collection_date;
    global $end_collection_date;
    global $basic_select;
    global $basic_from ;
    global $basic_where;

    $get_contrib_all =
        ("SELECT test_suite, ".
         $basic_select.
         $basic_from.
         "WHERE ".
         $basic_where.
         "GROUP BY test_suite ".
         "ORDER BY test_run DESC");

    $test_suite_hash = select($get_contrib_all);
    print_query_stmt("For each Test Suite, how many results did each accumulate?");
    print_query_table("Test Suite", "test_suite", $test_suite_hash);

    return 0;
}

function get_total_results() {
    global $start_collection_date;
    global $end_collection_date;
    global $total_hash;
    global $basic_select;
    global $basic_from ;
    global $basic_where;

    $get_contrib_total =
        ("SELECT ".
         $basic_select .
         $basic_from .
         "WHERE ".
         $basic_where);

    $total_hash      = select($get_contrib_total);

    return 0;
}

function print_query_db_table($database_hash) {

    print("<table border=\"1\" width=100%\n");

    print("<tr>\n");
    print("<th align=center bgcolor='".THCOLOR."'>\n");
    print("Collection Date\n");
    print("</th>\n");

    print("<th align=center colspan=2 bgcolor='".LYELLOW."'>\n");
    print("Database Size\n");
    print("</th>\n");

    print("<th align=center colspan=1 bgcolor='".LGREEN."'>\n");
    print("Total\n");
    print("</th>\n");

    print("<th align=center colspan=1 bgcolor='".LBLUE."'>\n");
    print("MPI Install\n");
    print("</th>\n");

    print("<th align=center colspan=1 bgcolor='".LBLUE."'>\n");
    print("Test Build\n");
    print("</th>\n");

    print("<th align=center colspan=1 bgcolor='".LBLUE."'>\n");
    print("Test Run\n");
    print("</th>\n");
    print("</tr>\n");

    # Line 2
    print("<tr>\n");
    print("<th align=center bgcolor='".THCOLOR."'>\n");
    print("&nbsp;\n");
    print("</th>\n");

    print("<th align=right colspan=1 bgcolor='".LYELLOW."'>\n");
    print("(GB)\n");
    print("</th>\n");
    print("<th align=right colspan=1 bgcolor='".LYELLOW."'>\n");
    print("(MB)\n");
    print("</th>\n");

    for($i = 0; $i < 4; ++$i) {
        print("<th align=center colspan=1 bgcolor='".THCOLOR."'>\n");
        print("# Tuples\n");
        print("</th>\n");
    }
    print("</tr>\n");


    for($i = 0; $i < sizeof($database_hash); ++$i) {
        print("<tr>\n");
        print("<td align=right>\n");
        print($database_hash[$i]["collection_date"]."\n");
        print("</td>\n");

        print("<td align=right bgcolor='".LYELLOW."'>\n");
        print(pretty_print_big_num($database_hash[$i]["db_size_gb"]) . "\n");
        print("</td>\n");

        print("<td align=right bgcolor='".LYELLOW."'>\n");
        print(pretty_print_big_num($database_hash[$i]["db_size_mb"]) . "\n");
        print("</td>\n");

        print("<td align=right bgcolor='".LGREEN."'>\n");
        print(pretty_print_big_num($database_hash[$i]["num_tuples"]) . "\n");
        print("</td>\n");

        print("<td align=right bgcolor='".LBLUE."'>\n");
        print(pretty_print_big_num($database_hash[$i]["num_tuples_mpi_install"]) . "\n");
        print("</td>\n");

        print("<td align=right bgcolor='".LBLUE."'>\n");
        print(pretty_print_big_num($database_hash[$i]["num_tuples_test_build"]) . "\n");
        print("</td>\n");

        print("<td align=right bgcolor='".LBLUE."'>\n");
        print(pretty_print_big_num($database_hash[$i]["num_tuples_test_run"]) . "\n");
        print("</td>\n");

        print("</tr>\n");
    }

    print("</table>\n");
}

function print_query_table($field_title, $db_field, $contrib_hash) {
    global $total_hash;

    print("<table border=\"1\" width=100%\n");

    print("<tr>\n");
    print("<th align=center bgcolor='".THCOLOR."'>\n");
    print($field_title."\n");
    print("</th>\n");

    print("<th align=center colspan=2 bgcolor='".LYELLOW."'>\n");
    print("MPI Installs\n");
    print("</th>\n");

    print("<th align=center colspan=2 bgcolor='".LGREEN."'>\n");
    print("Test Builds\n");
    print("</th>\n");

    print("<th align=center colspan=2 bgcolor='".LRED."'>\n");
    print("Test Runs\n");
    print("</th>\n");

    print("<th align=center colspan=2 bgcolor='".LBLUE."'>\n");
    print("Performance Runs\n");
    print("</th>\n");

    print("<tr>\n");
    print("<th align=center bgcolor='".THCOLOR."'>\n");
    print("&nbsp;\n");
    print("</th>\n");

    for($i = 0; $i < 4; ++$i) {
        print("<th align=center bgcolor='".THCOLOR."'>\n");
        print("# Tests\n");
        print("</th>\n");
        print("<th align=center bgcolor='".THCOLOR."'>\n");
        print("% Contrib\n");
        print("</th>\n");
    }

    print("</tr>\n");

    for($i = 0; $i < sizeof($contrib_hash); ++$i) {
        print("<tr>\n");
        print("<td align=right>\n");
        if( 0 < strlen($contrib_hash[$i][$db_field]) ) {
            print($contrib_hash[$i][$db_field]."\n");
        }
        else {
            print("Unknown\n");
        }
        print("</td>\n");

        print("<td align=right bgcolor='".LYELLOW."'>\n");
        print(pretty_print_big_num($contrib_hash[$i]["mpi_install"]) . "\n");
        print("</td>\n");
        print("<td align=right bgcolor='".LYELLOW."'>\n");
        printf("%4.1f %s\n", get_percent($contrib_hash[$i]["mpi_install"], $total_hash[0]["mpi_install"]), "%");
        print("</td>\n");

        print("<td align=right bgcolor='".LGREEN."'>\n");
        print(pretty_print_big_num($contrib_hash[$i]["test_build"]) . "\n");
        print("</td>\n");
        print("<td align=right bgcolor='".LGREEN."'>\n");
        printf("%4.1f %s\n", get_percent($contrib_hash[$i]["test_build"], $total_hash[0]["test_build"]), "%");
        print("</td>\n");

        print("<td align=right bgcolor='".LRED."'>\n");
        print(pretty_print_big_num($contrib_hash[$i]["test_run"]) . "\n");
        print("</td>\n");
        print("<td align=right bgcolor='".LRED."'>\n");
        printf("%4.1f %s\n", get_percent($contrib_hash[$i]["test_run"], $total_hash[0]["test_run"]), "%");
        print("</td>\n");

        print("<td align=right bgcolor='".LBLUE."'>\n");
        print(pretty_print_big_num($contrib_hash[$i]["perf"]) . "\n");
        print("</td>\n");
        print("<td align=right bgcolor='".LBLUE."'>\n");
        printf("%4.1f %s\n", get_percent($contrib_hash[$i]["perf"], $total_hash[0]["perf"]), "%");
        print("</td>\n");

        print("</tr>\n");
    }

    print("<tr><b>\n");
    print("<th align=right>\n");
    print("Total\n");
    print("</th>\n");

    print("<th align=right>\n");
    print(pretty_print_big_num($total_hash[0]["mpi_install"]) . "\n");
    print("</th>\n");
    print("<th align=right>\n");
    print("100.0 %\n");
    print("</th>\n");

    print("<th align=right>\n");
    print(pretty_print_big_num($total_hash[0]["test_build"]) . "\n");
    print("</th>\n");
    print("<th align=right>\n");
    print("100.0 %\n");
    print("</th>\n");

    print("<th align=right>\n");
    print(pretty_print_big_num($total_hash[0]["test_run"]) . "\n");
    print("</th>\n");
    print("<th align=right>\n");
    print("100.0 %\n");
    print("</th>\n");

    print("<th align=right>\n");
    print(pretty_print_big_num($total_hash[0]["perf"]) . "\n");
    print("</th>\n");
    print("<th align=right>\n");
    print("100.0 %\n");
    print("</th>\n");

    print("</tr>\n");
    print("</table>\n");
}

function print_query_stmt($query) {
    print("<hr>\n");
    print("<h3>".
          $query.
          "</h3>");
}

function display_stats_header() {
    global $start_collection_date;
    global $end_collection_date;

    print("<center><h3>".
          "Current Date Range: ".
          sql_resolve_date($start_collection_date).
          " - ".
          sql_resolve_date($end_collection_date).
          "</h3></center>\n");
}

function display_debug_input() {
    global $basic_where;

    print("\n<pre>\n");

    print("INPUT Date         [".$_GET['dates']."]\n");
    print("INPUT Org          [".$_GET['org_name']."]\n");
    print("INPUT Platform     [".$_GET['platform_name']."]\n");
    print("INPUT OS           [".$_GET['os_name']."]\n");
    print("INPUT MI Compiler  [".$_GET['mpi_install_compiler_name']."]\n");
    print("INPUT TB Compiler  [".$_GET['test_build_compiler_name']."]\n");
    print("INPUT MPI Get      [".$_GET['mpi_get_name']."]\n");
    print("INPUT Test Suite   [".$_GET['test_suite']."]\n");
    print("\n");
    print("WHERE [$basic_where]");

    print("\n</pre>\n");
}

######################################################################
function html_select_stats() {
    global $start_collection_date;
    global $end_collection_date;

    print("<form action=\"index.php\" method=\"get\" id=\"stats\" name=\"stats\">\n");

    #
    # Date Range
    #
    print("<table border=\"1\" width=\"50%\" bgcolor='".THCOLOR."'>\n");
    print("<tr>\n");
    print("<td align=\"left\" width=\"25%\">\n");
    print("<b>Date Range</b>:\n");
    print("</td>\n");
    print("<td align=\"left\">\n");
    print("<input type=\"text\" name=\"dates\" value=\"".
          sql_resolve_date($start_collection_date)." - ".
          sql_resolve_date($end_collection_date).
          "\"><br>\n");
    print("</td>\n");
    print("</tr>\n");

    #
    # Org. Name
    #
    $all_vals = select_all_distinct("org_name");
    print(html_add_table_select("Org.", "org_name", $all_vals));

    #
    # Platform Name
    #
    $all_vals = select_all_distinct("platform_name");
    print(html_add_table_select("Platform Name", "platform_name", $all_vals));

    #
    # OS Name
    #
    $all_vals = select_all_distinct("os_name");
    print(html_add_table_select("OS Name", "os_name", $all_vals));

    #
    # MPI Install Compiler Name/Version
    #
    $all_vals = select_all_distinct("mpi_install_compiler_name");
    print(html_add_table_select("MPI Install Compiler", "mpi_install_compiler_name", $all_vals));
    #print(html_add_table_select("MPI Install Compiler Version", "mpi_install_compiler_version", ""));

    #
    # Test Build Compiler Name/Version
    #
    #JJH $all_vals = select_all_distinct("test_build_compiler_name");
    #$all_vals = array();
    #print(html_add_table_select("Test Build Compiler", "test_build_compiler_name", $all_vals));
    #print(html_add_table_select("Test Build Compiler Version", "test_build_compiler_version", ""));

    #
    # MPI Get Name/Version
    #
    $all_vals = select_all_distinct("mpi_get_name");
    print(html_add_table_select("MPI Get Name", "mpi_get_name", $all_vals));
    #print(html_add_table_select("MPI Get Version", "mpi_get_version", ""));

    #
    # MPI Install Config Name
    #
    #print(html_add_table_select("MPI Install Configuration", "mpi_install_config", ""));

    #
    # Test Suite Name
    #
    $all_vals = select_all_distinct("test_suite");
    print(html_add_table_select("Test Suite", "test_suite", $all_vals));

    #
    # Launcher Name
    #
    #print(html_add_table_select("Launcher", "launcher", ""));

    #
    # Resource Mgr Name
    #
    #print(html_add_table_select("Resource Mgr.", "resource_mgr", ""));

    #
    # Resource Mgr Name
    #
    #print(html_add_table_select("Network", "network", ""));

    #
    # Submit Button
    #
    print("<tr>\n");
    print("<td align=\"left\" colspan=2>\n");
    print("<center>\n");
    print("<input type=\"submit\">\n");
    print("<input type=\"reset\">\n");
    print("</center>\n");
    print("</td>\n");
    print("</tr>\n");

    print("</table>\n");
    print("<form>\n");
    print("<hr>\n");
}

function html_add_table_select($title, $form_name, $values) {
    $table_entry = "";

    $table_entry .= "<tr>\n";
    $table_entry .= "<td align=\"left\" width=\"25%\">\n";
    $table_entry .= "<b>".$title."</b>:\n";
    $table_entry .= "</td>\n";
    $table_entry .= "<td align=\"left\">\n";
    $table_entry .= "<select name=\"".$form_name."\" width=\"350\">\n";
    if( isset($_GET[$form_name]) &&
        0 != strncmp($_GET[$form_name], "all", strlen("all")) ) {
        $table_entry .= "<option value=\"all\">All</option>\n";
    }
    else {
        $table_entry .= "<option value=\"all\" selected>All</option>\n";
    }
    foreach($values as $v) {
        if( array_key_exists($form_name, $_GET) &&
            0 == strncmp($_GET[$form_name], $v, strlen($v)) ) {
            $table_entry .= "<option value=\"".$v."\" selected>".$v."</option>\n";
        }
        else {
            $table_entry .= "<option value=\"".$v."\">".$v."</option>\n";
        }
    }
    $table_entry .= "</select>\n";
    $table_entry .= "</td>\n";
    $table_entry .= "</tr>\n";

    return $table_entry;
}


######################################################################
# Process Date Field
function process_stat_dates() {
    global $start_collection_date;
    global $end_collection_date;
    global $given_dates;
    global $basic_where;

    $tmp_begin = 0;
    $tmp_end   = 0;

    $tokens = tokenize($given_dates);

    foreach ($tokens as $token) {
        # Find Range (e.g., 2007-07-01 - 2007-08-01)
        if( preg_match("/(\d*)(-|\/)(\d*)(-|\/)(\d*)/", $token, $m) ) {
            if($tmp_begin == 0) {
                $tmp_begin = $m[0];
            }
            else {
                $tmp_end = $m[0];
            }
        }
    }

    if( $tmp_begin != 0) {
        $start_collection_date = "DATE '$tmp_begin'";
        $end_collection_date   = "DATE '$tmp_end'";
    }
}

function process_stat_input() {
    global $start_collection_date;
    global $end_collection_date;
    global $basic_where;

    # Org Name
    if( array_key_exists("org_name", $_GET) &&
        0 <  strlen( $_GET['org_name']) &&
        0 != strncmp($_GET['org_name'], "all", strlen("all"))) {
        $basic_where = ($basic_where . " AND org_name = '".$_GET['org_name']."'");
    }

    # Platform Name
    if( array_key_exists("platform_name", $_GET) && 
        0 <  strlen( $_GET['platform_name']) &&
        0 != strncmp($_GET['platform_name'], "all", strlen("all"))) {
        $basic_where = ($basic_where . " AND platform_name = '".$_GET['platform_name']."'");
    }

    # OS Name
    if( array_key_exists("os_name", $_GET) &&
        0 <  strlen( $_GET['os_name']) &&
        0 != strncmp($_GET['os_name'], "all", strlen("all"))) {
        $basic_where = ($basic_where . " AND os_name = '".$_GET['os_name']."'");
    }

    # MI Compiler Name
    if( array_key_exists("mpi_install_compiler_name", $_GET) &&
        0 <  strlen( $_GET['mpi_install_compiler_name']) &&
        0 != strncmp($_GET['mpi_install_compiler_name'], "all", strlen("all"))) {
        $basic_where = ($basic_where . " AND mpi_install_compiler_name = '".$_GET['mpi_install_compiler_name']."'");
    }

    # TB Compiler Name
    if( array_key_exists("test_build_compiler_name", $_GET) &&
        0 <  strlen( $_GET['test_build_compiler_name']) &&
        0 != strncmp($_GET['test_build_compiler_name'], "all", strlen("all"))) {
        $basic_where = ($basic_where . " AND test_build_compiler_name = '".$_GET['test_build_compiler_name']."'");
    }

    # MPI Get Name
    if( array_key_exists("mpi_get_name", $_GET) &&
        0 <  strlen( $_GET['mpi_get_name']) &&
        0 != strncmp($_GET['mpi_get_name'], "all", strlen("all"))) {
        $basic_where = ($basic_where . " AND mpi_get_name = '".$_GET['mpi_get_name']."'");
    }

    # Test Suite Name
    if( array_key_exists("test_suite", $_GET) &&
        0 <  strlen( $_GET['test_suite']) &&
        0 != strncmp($_GET['test_suite'], "all", strlen("all"))) {
        $basic_where = ($basic_where . " AND test_suite = '".$_GET['test_suite']."'");
    }

    # Collection Date Specifier
    $basic_where = ("collection_date >= $start_collection_date AND collection_date <= $end_collection_date AND ".
                    $basic_where);
}

######################################################################
function pretty_print_big_num($val) {
    return number_format($val, 0, '.', ',');
}

function get_percent($amt, $total) {
    if( $total == 0 ) {
        return 0;
    }
    else {
        return (($amt/$total) * 100);
    }
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

function do_pg_connect() {

    global $mtt_database_name;
    global $mtt_database_username;
    global $mtt_database_password;
    global $pgsql_conn;
    static $connected = false;

    if (!$connected) {
        $pgsql_conn =
            pg_connect("host=localhost port=5432 dbname=$mtt_database_name user=$mtt_database_username password=$mtt_database_password");

        # Exit if we cannot connect
        if (!$pgsql_conn)
            mtt_abort("\nCould not connect to the $dbname database; " .
                      "submit this run later.");
        else
            $connected = true;
    }
}

function do_pg_query($cmd, $silent) {

    do_pg_connect();

    debug("\nSQL: $cmd\n");
    if (! ($db_res = pg_query($cmd))) {
        $out = "\nSQL QUERY: " . $cmd .
               "\nSQL ERROR: " . pg_last_error() .
               "\nSQL ERROR: " . pg_result_error();

        # Some errors are unsurprising, allow for silence in
        # such cases
        if (! $silent) {
            mtt_error($out);
            mtt_send_mail($out);
        }
    }
    debug("\nDatabase rows affected: " . pg_affected_rows($db_res) . "\n");
}

# Fetch All distinct values for this key
function select_all_distinct($field) {
    global $basic_from;
    global $basic_where;

    $vals = simple_select("select distinct(".$field.") ".
                          $basic_from.
                          "WHERE ".$field." != '' AND ".
                          $basic_where);
    if( null == $vals ) {
        return array();
    }

    $accum = array();
    foreach($vals as $v) {
        $accum[] = preg_replace("/\s*$/", "", $v);
    }
    return $accum;
}

# Resolve a SQL Date to a printable string
function sql_resolve_date($date) {
    return select_scalar("select DATE ( $date )");
}

# Fetch scalar value
function select_scalar($cmd) {
    $set = array();
    $set = simple_select($cmd);
    return array_shift($set);
}

# Fetch 1D array
function simple_select($cmd) {

    do_pg_connect();

    $rows = null;

    debug("\nSQL: $cmd\n");
    if (! ($result = pg_query($cmd))) {
        $out = "\nSQL QUERY: " . $cmd .
               "\nSQL ERROR: " . pg_last_error() .
               "\nSQL ERROR: " . pg_result_error();
        mtt_error($out);
        mtt_send_mail($out);
    }
    $max = pg_num_rows($result);
    for ($i = 0; $i < $max; ++$i) {
        $row = pg_fetch_array($result, $i, PGSQL_NUM);
        $rows[] = $row[0];
    }
    return $rows;
}

# Fetch an associative hash (column name => value)
function associative_select($cmd) {

    do_pg_connect();

    debug("\nSQL: $cmd\n");
    if (! ($result = pg_query($cmd))) {
        $out = "\nSQL QUERY: " . $cmd .
               "\nSQL ERROR: " . pg_last_error() .
               "\nSQL ERROR: " . pg_result_error();
        mtt_error($out);
        mtt_send_mail($out);
    }
    return pg_fetch_array($result);
}

# Fetch 2D array
function select($cmd) {
    $rtn = null;

    do_pg_connect();

    debug("\nSQL: $cmd\n");
    if (! ($result = pg_query($cmd))) {
        $out = "\nSQL QUERY: " . $cmd .
               "\nSQL ERROR: " . pg_last_error() .
               "\nSQL ERROR: " . pg_result_error();
        mtt_error($out);
        mtt_send_mail($out);
    }
    $rtn = pg_fetch_all($result);
    if( false == $rtn ) {
       return array();
    }
    else {
       return $rtn;
    }
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
}

# Function for reporting errors back to the client
function mtt_error($str) {
    print("MTTDatabase server error: $str\n");
}

# Function for reporting notices back to the client
function mtt_notice($str) {
    print("MTTDatabase server notice: $str\n");
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

?>
