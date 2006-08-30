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
# Web-based Open MPI Tests Querying Tool -
#   This tool is for drill-downs.
#   For the one-size-fits-all report, see summary.php.
#
#

#
# todo:
#
# [ ] Create "alerts", a la Google News Alerts
#     e.g., "email me when this type of error occurs"
# [ ] Offload more string processing to postgres
# [ ] Change anything hardcoded (e.g., col names) to dynamically eval'd
#     (create a variant of array_map)
# [-] Use pg_select, not pg_query (nevermind, php.net says pg_select is
#     experimental)
# [x] Do not print tables with 0 rows of data
# [ ] Format cgi option (txt, html, pdf)
# [ ] Graphing
# [ ] Alias function names to cut-down on verbosity?
# [x] Display pass and fail in a single row
# [ ] Look into query optimization (e.g., stored procedures,
#     saved queries, EXPLAIN/ANALYZE ...)
# [ ] Somehow unify Run.pm with correctness.sql - using an xml file?
# [ ] Use references where appropriate (e.g., returning large arrays?)
# [ ] Use open-mpi.org CSS stylesheets (will improve performance!)
# [ ] Add <tfoot> row showing totals (maybe play with <tbody> to delineate tables
# [ ] Add row numbering
# [ ] Throttling - e.g., "this query will generate a ton of data, let's look at it
#     in chunks"
# [x] Fix the newline issues in the Detailed Info popups (set font to courier)
# [x] Include more shades in the colorized pass/fail columns
# [ ] Experiment with levels_strike_column array (esp.for three-phase merging todo)
# [x] Come up with better naming scheme for query clause lists (e.g.,
#     selects['slave']['all']['main'][$phase], etc.)
# [ ] Try to better split out printing/querying
# [ ] Get rid of php warnings that show up from command-line
# [x] Timestamp aggregation
# [ ] Full path of given test in the testsuite
# [ ] Fix "Check all" link for "Roll" column
# [ ] "all on 1 page" option (or create FRAMES version?)
# [ ] "Break up into separate tables" checkbox
# [x] Gray-out phase-specific fields on a Phase onclick event
# [ ] Create a Save button, for cookie-izing default queries
# [ ] Functionalize more things, e.g., dumping an html table, gathering
#     SELECTS, etc.
# [ ] Make entire row clickable, not just far-right row cell
# [ ] Allow for multiple selections for certain fields
# [ ] Sort buttons in the results table
# [x] Cut back on magic cgi strings, e.g., menufield_, textfield_, etc.
#     * Variablizing these prefixes happens to shorten the query string
# [ ] Provide more flexible AND|OR searching (get_textfield_filters)
# [ ] - Slim down query-string (trim null params?)
#     - Alias CGI params for an even more compact query string
# [ ] Clean-up/improve tracing mechanism
# [ ] Add javascript checking for a nonsensical query
#

#
# history:
#
# Mon Aug 14
#  - Began integrating query screen (query.php) into reporting functions
#    (summary.php)
#
# Thurs Aug 17
#  - Added aggregate checkbox toggle (thanks Anya!)
#  - Added timestamp aggregation
#
# Fri Aug 18
#  - Fixed RH info links regression
#  - Fixed "too-many-columns-selected" 'by_run' regression
#  - Added numeric filters types (for Np)
#  - Trimmed save-link query string down with cgi param name prefix encoding
#  - Fixed check for phase-specific filter
#  - Fixed sql_to_en 'does not contain'
#  - Created 'Help' file
#

# In case we're using this script from the command-line
if ($argv) {
    for ($i=1; $i<count($argv); $i++) {
       $it = split("=",$argv[$i]);
       $_GET[$it[0]] = $it[1];
    }
}

$GLOBALS['verbose'] = $_GET['verbose'] ? $_GET['verbose'] : 0;
$GLOBALS['debug']   = $_GET['debug']   ? $_GET['debug']   : 0;
$GLOBALS['res']     = 0;

$form_id = "report";

$javascript = <<<EOT

    function popup(width,height,title,content,style) {

        newwindow2=window.open('','name','height=' + height + ',width=' + width + ' scrollbars=yes');
        var tmp = newwindow2.document;
        tmp.write('<html><head><title>' + title + '</title>');
        tmp.write('<body ' + style + '>' + content + '</body></html>');
        tmp.close();
    }

    // X: combine the following two functions

    // Disable all objects passed to the function
    function disable() {

        for (i = 0; i < arguments.length; i++) {

            // alert("list[i] = " + arguments[i]);

            // Aack! How do I check to see if the val is defined!
            // The function dies if we try to disable a single undefined object

            if (undefined != arguments[i]) {
                arguments[i].disabled=1;
            }
        }
    }

    // Enable all objects passed to the function
    function enable() {
        for (i = 0; i < arguments.length; i++) {
            if (undefined != arguments[i]) {
                arguments[i].disabled=0;
            }
        }
    }

    // Toggle all the arguments (check/uncheck)
    function toggle_checkboxes() {

        one_is_checked = false;

        for (i = 0; i < arguments.length; i++) {
            var box = document.getElementByName(arguments[i]);
            if (box.checked == true) {
                one_is_checked = true;
                break;
            }
        }

        toggle = ! one_is_checked;

        for (i = 0; i < arguments.length; i++) {
            var box = document.getElementByName(arguments[i]);
            box.checked = toggle;
        }
    }

EOT;

$style = <<<EOT

    a.lgray_ln:link    { color: #F8F8F8 } /* for unvisited links */
    a.lgray_ln:visited { color: #555555 } /* for visited links */
    a.lgray_ln:active  { color: #FFFFFF } /* when link is clicked */
    a.lgray_ln:hover   { color: #FFFF40 } /* when mouse is over link */

EOT;

# $_GET['debug'] = $GLOBALS['debug'] ? 'y' : $_GET['debug'];

# HTML variables

$domain  = "http://www.open-mpi.org";

$client = "MTT";

# Make these a $colors array for easier globalizing in functions
$gray    = "#A0A0A0";
$dgray   = "#808080";
$lgray   = "#C0C0C0";
$llgray  = "#DEDEDE";
$lllgray = "#E8E8E8";
$lred    = "#FFC0C0";
$lgreen  = "#C0FFC0";
$lyellow = "#FFFFC0";
$white   = "#FFFFFF";

$align   = "center";

$thcolor  = $llgray;

$menu_width = '220px';
$ft_menu_width = '125px';

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

# db field name => html column header This could be done using the SQL 'as'
# construct (?), but that's a lot of regexp-ing
#
# Or use pg_fetch_all which returns a hash, not a numerically indexed array
# (we're okay as long as php can preserve the array creation order)
$sp = "&nbsp;";
$field_labels = array(

    # not an actual db field
    "phase"                    => "Phase",

    # phase-independent fields
    "platform_hardware"        => "Hardware",
    "platform_type"            => "Os",
    "platform_id"              => "Cluster",
    "cluster"                  => "Cluster",
    "os_name"                  => "Os",
    "os_version"               => "Os".$sp."ver",
    "mpi_name"                 => "Mpi",
    "mpi_version"              => "Mpi".$sp."rev",
    "hostname"                 => "Host",

    # timestamp related
    "start_test_timestamp"     => "Timestamp" .$sp."(GMT)",
    "start_run_timestamp"      => "Timestamp" .$sp."(GMT)",
    "submit_test_timestamp"    => "Submit".$sp."time",
    "test_duration_interval"   => "Test".$sp."duration",
    "agg_timestamp"            => "Timestamp".$sp."aggregation",

    "mpi_get_section_name"     => "Section".$sp."(MPI Get)",
    "mpi_install_section_name" => "Section".$sp."(MPI Install)",
    "mpi_details"              => "MPI Details",
    "test_build_section_name"  => "Suite".$sp."(Build)",
    "test_run_section_name"    => "Suite".$sp."(Run)",
    "section"                  => "Section",
    "merge_stdout_stderr"      => "Merge".$sp."outputs",
    "stderr"                   => "Stderr",
    "stdout"                   => "Stdout",
    "environment"              => "Env",
    "mtt_version_major"        => "Mtt".$sp."ver".$sp."maj",
    "mtt_version_minor"        => "Mtt".$sp."ver".$sp."min",
    "compiler_name"            => "Compiler",
    "compiler"                 => "Compiler",
    "compiler_version"         => "Compiler".$sp."ver",
    "configure_arguments"      => "Config".$sp."args",
    "vpath_mode"               => "Vpath",
    "result_message"           => "Result".$sp."msg",
    "test_name"                => "Test".$sp."name",
    "name"                     => "Test name",
    "section_name"             => "Test name",
    "test_command"             => "Mpirun".$sp."cmd",
    "test_np"                  => "Np",
    "result_message"           => "Test".$sp."msg",
    "test_message"             => "Test".$sp."msg",
    "test_pass"                => "Result",
    "success"                  => "Result",
    "count"                    => "Count",
    "date"                     => "Date",
    "time"                     => "Time",
);
$menu_labels = array(
    "all" => "All",
);
$All = "All";

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

# Setup db connection
$dbname = $_GET['db']   ? $_GET['db']   : "mtt";
$user   = $_GET['user'] ? $_GET['user'] : "mtt";
$pass   = "3o4m5p6i";

if (! ($GLOBALS["conn"] = pg_connect("host=localhost port=5432 dbname=$dbname user=$user password=$pass")))
    exit_("<br><b><i>Could not connect to database server.</i></b>");

debug("\n<br>postgres: " . pg_last_error() . "\n" . pg_result_error());

$once_db_table = "once";


/**************************************************************
*                                                             *
* Will we have a config of any kind for this tool?            *
*                                                             *
*                                                             *
***************************************************************

#
# The report configuration
#
# (The following hash would be nicer as an external config file)
#

$first_lev  = 1;
$second_lev = 2;
$third_lev  = 5;
$fourth_lev = 6;

if ($_GET['verbose'] == 'y') {
    $config['show'] = array_fill(0, $num_cols, true);
    #var_dump_html("\nconfig[show] = ", $config['show']);
} else {
    $config = array(
        'show' => array(
            $first_lev => true,
            $second_lev => true,
            $third_lev => true,
            $fourth_lev => true,
        ),
    );
    # filter db results for a given level
    $config['filter'] = array(
        $fourth_lev => array ( 'runs' => array( "success = 'f'" ) )
    );
}

#################################
#                               #
#     Configuration defaults    #
#                               #
#################################

$config['by_run'] = array(
    $first_lev  => true,
    $second_lev => true,
);
$config['label'] = array(
    $first_lev  => "$client Executive Summary",
    $second_lev => "$client Cluster Summary",
    $third_lev  => "$client Test Suites Summary",
    $fourth_lev => "$client Test Case Details",
);
# Add some parameters for a given level and phase
# Note: This is jamming a square-peg into a round hole.
# E.g., what does a section in a 'Test Build' correlate to
# a section in an 'MPI Install' (it doesn't)
# These all need to have the same 'as' alias so that they
# can get selected from the tmp & run_atomic table correctly
$config['add_params'] = array(
    $third_lev => array (
        'installs' => array("compiler_name as section"),
        'builds'   => array("test_build_section_name as section"),
        'runs'     => array("test_run_section_name as section"),
    ),
    $fourth_lev => array (
        'runs'     => array("test_run_section_name as section",
                            "test_name"),
    ),
);
# Additional links
$config['info'] = array(
    $fourth_lev => array (
        'runs' => array( 'name' =>
            "$domain" . $_SERVER['PHP_SELF'] .
            "?level=" . ($fourth_lev + 1) . "&go=up" )
    ),
);
# Hide some phases for a given level?
$config['suppress'] = array(
    #6 => array (
    #        'installs' => true,
    #    ),
    6 => array (
            'builds' => true,
            'installs' => true,
        ),
);
# Fields for details links

**************************************************************/

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

# Additional phase-specific parameters that go in the linked table
$config['details'] = array(
    $level => array(
        'runs' => array_merge(
                        array( "test_command", "result_message",),
                        $linked_stuff_top,
                        $linked_stuff_bottom
                    ),
        'builds' => array_merge(
                        array( "configure_arguments" ),
                        $linked_stuff_top,
                        $linked_stuff_bottom
                    ),
        'installs' => array_merge(
                        array( "configure_arguments" ),
                        $linked_stuff_top,
                        $linked_stuff_bottom
                    ),
    ),
);

# Additional phase-specific parameters that go in the main table
# Note: installs/builds have identical 'add_params', so sometimes
# we will be able to merge the result sets of those two phases
$config['add_params'] = array(
    $level => array (
        'installs' => array("compiler_name","compiler_version"),
        'builds'   => array("compiler_name","compiler_version"),
        'runs'     => array("test_name", "test_np", "test_run_section_name"),
    ),
);

# Create SQL filters
# (Currently, we're only doing all-levels filtering on timestamp)
$sql_filters['per_script'] = array();

$selects['per_script']['params'] = array();
$done = false;
$max_desc_len = 80;

# --- Begin query screen vars

$tables = array(
    "once",
    "general_a",
    "general_b",
);

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

$once_tables = array(
    "once",
);

$columns = array();

# Fetch fields to be used as menus
# foreach ($tables as $table) {
#
#     $columns[$table] = array();
#
#     $cmd = "SELECT column_name FROM information_schema.columns WHERE table_name = '$table';";
#     $rows = pg_query_simple($cmd);
#     while ($row = array_shift($rows)) {
#         array_push($columns[$table], $row);
#     }
# }

$string_filter_types = array("contains","does not contain", "begins with", "ends with");
$numeric_filter_types = array("equals","less than","greater than");

# We'll define these fields instead of fetch from information_schema
# so that we can order them how we want
#
# Q: What's with general_a and general_b?
# A: The db tables are factored down such that if a column needs to be altered
#    it can be done to a single column, not a column in multiple tables
$columns["general_a"] = array(
    #"run_index"               => $string_filter_types,
    "stderr"                   => $string_filter_types,
    "stdout"                   => $string_filter_types,
    #"merge_stdout_stderr"     => $string_filter_types,
    "environment"              => $string_filter_types,
    "configure_arguments"      => $string_filter_types,
    #"vpath_mode"              => $string_filter_types,
    "result_message"           => $string_filter_types,
    #"start_test_timestamp"    => $string_filter_types,
    #"submit_test_timestamp"   => $string_filter_types,
    #"test_duration_interval"  => $string_filter_types,
    "mpi_get_section_name"     => $string_filter_types,
    "mpi_install_section_name" => $string_filter_types,
    #"mpi_details"             => $string_filter_types,
);
$columns["general_b"] = array(
    "compiler_name"    => $string_filter_types,
    "compiler_version" => $string_filter_types,
);

$columns["advanced"] = array(
    #"run_index"                => $string_filter_types,
    #"mpi_get_section_name"     => $string_filter_types,
    #"mpi_install_section_name" => $string_filter_types,
    "mpi_details"               => $string_filter_types,
    "merge_stdout_stderr"       => $string_filter_types,
    #"environment"              => $string_filter_types,
    #"configure_arguments"      => $string_filter_types,
    "vpath_mode"                => $string_filter_types,
    #"result_message"           => $string_filter_types,
    "start_test_timestamp"      => $string_filter_types,
    "submit_test_timestamp"     => $string_filter_types,
    "test_duration_interval"    => $string_filter_types,
);

$columns['once'] = array(
    "platform_hardware" => $string_filter_types,
    "os_name"           => $string_filter_types,
    "os_version"        => $string_filter_types,
    #"platform_type"    => $string_filter_types,
    #"platform_id"      => $string_filter_types,
    "$cluster_field"    => $string_filter_types,
    #"hostname"         => $string_filter_types,
    "mpi_name"          => $string_filter_types,
    "mpi_version"       => $string_filter_types,
);

$columns["runs"] = array(
    "test_name"               => $string_filter_types,
    "test_command"            => $string_filter_types,
    "test_np"                 => $numeric_filter_types,
    "test_build_section_name" => $string_filter_types,
    "test_run_section_name"   => $string_filter_types,
);

$columns["installs"] = $columns["general_b"];
$columns["builds"] = $columns["general_b"];

# Encode cgi param name prefixes as a means to slim down the query string
# X: Encode cgi param field names
$cgi_abbrevs = array(
    'menufield'   => 'mef_',
    'mainfield'   => 'maf_',
    'textfield'   => 'tf_',
    'filter_types' => 'ft_',
);

# Populate menus with fields from db

$clause = "";

# Gather selectable menu items

$words_to_numerals = array(
    #"One"   => 1,
    "Two"   => 2,
    "Three" => 3,
    "Four"  => 4,
    "Five"  => 5,
    "Six"   => 6,
    "Seven" => 7,
    "Eight" => 8,
    "Nine"  => 9,
    "Ten"   => 10,
);

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
# X: Add week-by-week, month-by-month
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

# X: loop through elems in HTML 'name' attribute, instead of this absurd
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

$menu = array();
$menu = populate_menu(array_keys($columns["once"]), "once");

$by_atoms = array(
    "*by_test_case" => "By test case",
    "by_test_run" => "By test run",
);

# --- End query screen vars

# Print html head (query frame & results frame may need this script/style)
print "\n<html>";
print "\n<head><title>Open MPI Test Reporter</title>";

print "\n<script language='javascript' type='text/javascript'>";
print $javascript;
print "\n</script>";

print "\n<style type='text/css'>";
print $style;
print "\n</style>";
print "\n</head>";

$_GET['1-page'] = true;

# If no parameters passed in, show the user entry panel
if ((! isset($_GET['go']) and ! isset($_GET['just_results'])) or
    (! $_GET) or
    ($_GET['1-page']))
{
    $cols = 1;

    # Because the CGI array will not be 2D, we have to do a makeshift 2D array by prefixing
    # CGI names with things like "field_" or "mainfield_"

    # Generate Main Menu

    $main_pulldowns .= "\n\n<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";
    $main_pulldowns .= "\n<tr bgcolor=$gray>";
    $main_pulldowns .= "\n<th colspan=2>Main Menu <tr>";
    $main_pulldowns .= repeat("\n<th bgcolor='$gray'>Field <th bgcolor='$gray'>Menu", $cols);

    $i = 0;
    foreach (array_keys($main_menu) as $field) {

        $main_pulldowns .= "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
            "\n<td bgcolor=$lgray><font>$field_labels[$field]:" .
            "\n<td><select name='" . $cgi_abbrevs['mainfield'] . "$field'>";

        $j = 0;
        $starred = false;
        foreach ($main_menu[$field]["options"] as $item) {
            $starred = (preg_match('/^\*/',$item) ? true : false);
            $item = preg_replace("/^\*/i",'',$item);
            $main_pulldowns .= "\n<option " .
                            ($starred ? " selected " : "") .
                            "style='width: $menu_width;' value='$item' " .
                            ($main_menu[$field]["javascript"][$j] ?
                                "onclick='javascript:" . $main_menu[$field]["javascript"][$j] . "'" :
                                "") .
                            ">" .

                            # phases is the only labeled mainfield
                            ($phase_labels[$item] ? $phase_labels[$item] : $item);

            $j++;

        }

        $main_pulldowns .= "\n</select>";
    }
    $main_pulldowns .= "\n</table>";

    # Generate pulldowns table

    $pulldowns .= "\n\n<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";
    $pulldowns .= "\n<tr bgcolor=$gray>";
    $pulldowns .= "\n<th colspan=3>Selections <tr>";
    $pulldowns .= repeat("\n<th bgcolor='$gray'>Field <th bgcolor='$gray'>Menu <th bgcolor='$gray'>" .
                    # "<a href=' " .
                    #     "\njavascript:toggle_checkboxes" .
                    #         "( " . join(",", lsprintf_('"%s"', prefix("agg_", array_keys($menu)))) . ")' " .
                    # "class='lgray_ln'>" .
                    "Aggregate" .
                    # "</a>" .
                    "",
                  $cols);

    $i = 0;
    foreach (array_keys($menu) as $field) {

        $pulldowns .= "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
            "\n<td bgcolor=$lgray><font>$field_labels[$field]:" .
            "\n<td><select name='" . $cgi_abbrevs['menufield'] . "$field'>";

        $starred = false;
        foreach (array_merge(array($All), $menu[$field]) as $item) {

            # X: functionalize the whole 'default selection' thing
            $starred = (preg_match('/^\*/',$item) ? true : false);
            $item = preg_replace("/^\*/i",'',$item);
            $pulldowns .= "\n<option " .
                            ($starred ? "selected" : "") .
                            " style='width: $menu_width;' value='$item'>$item";
        }
        $pulldowns .= "\n</select>";

        # check the first three by default
        $pulldowns .= "\n<td><input type='checkbox' name='agg_$field' id='agg_$field' " .
                        (($i > 3) ? "checked" : " ") . ">";
    }
    $pulldowns .= "\n</table>";

    # X: Merge the following two foreach loops

    # Generate advanced textfield filters (this should be thought of as a
    # logical extension of the $filters panel)

    $advanced .= "\n\n<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";
    $advanced .= "\n<tr bgcolor=$gray>";
    $advanced .= "\n<th colspan=3>Advanced <tr>";
    $advanced .= repeat("\n<th bgcolor='$gray'>Field <th bgcolor='$gray'>Text <th bgcolor='$gray'>", $cols);

    $i = 0;
    foreach (array("advanced") as $t) {
        foreach (array_keys($columns[$t]) as $textfield) {

            $advanced .= "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
                        "\n<td bgcolor=$lgray><font>".
                        ($field_labels[$textfield] ? $field_labels[$textfield] : $textfield) . ":" .
                        "\n<td><input type='textfield' name='" . $cgi_abbrevs['textfield'] . "$textfield'>" .
                        "\n<td><select name='" . $cgi_abbrevs['filter_types'] . "$textfield'>";

            foreach ($columns[$t][$textfield] as $filter_type) {
                $advanced .= sprintf("\n<option>%s</option>", $filter_type);
            }
            $advanced .= "\n</select>";
        }
    }

    $advanced .= "\n<tr>";
    $advanced .= "\n<td bgcolor=$gray align=center colspan=3><input type='submit' value='Save'>";
    $advanced .= "\n</table>";

    # Generate textfield filters

    $filters .= "\n\n<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";
    $filters .= "\n<tr bgcolor=$gray>";
    $filters .= "\n<th colspan=3>$Filters ";

    # X: Need to create javascript import/export functions to get this working
    # $filters .= "\n<a href='javascript:popup(\"900\",\"750\",\"Advanced $Filters\",\"" .
    #              strip_quotes($advanced) .
    #              "\",\"\")' class='lgray_ln'>[+]</a>";

    $filters .= "\n<tr>";
    $filters .= repeat("\n<th bgcolor='$gray'>Field <th bgcolor='$gray'>Text <th bgcolor='$gray'>", $cols);

    $i = 0;
    foreach (array_keys($textfield_tables) as $t) {

        $divider = $textfield_tables[$t]["label"];
        $filters .= $divider ? "\n<tr><th colspan=3 bgcolor=$gray align='center'>$divider" : "";

        foreach (array_keys($columns[$t]) as $textfield) {
            $filters .= "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
                        "\n<td bgcolor=$lgray><font>" .
                        ($field_labels[$textfield] ? $field_labels[$textfield] : $textfield) . ":" .
                        "\n<td><input type='textfield' name='" . $cgi_abbrevs['textfield'] . "$textfield'>" .
                        "\n<td><select name='" . $cgi_abbrevs['filter_types'] . "$textfield'>";

            foreach ($columns[$t][$textfield] as $filter_type) {
                $filters .= sprintf("\n<option " .
                            "style='width: $ft_menu_width;' " .
                            ">%s</option>", $filter_type);
            }
            $filters .= "\n</select>" .  "";
        }
    }
    $filters .= "\n</table>";


    # Other settings

    $other .= "\n<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";
    $other .= "\n<tr bgcolor=$gray>";
    $other .= "\n<th colspan=3>Settings ";
    $other .= "\n<tr><td bgcolor=$lgray>Count";

    $starred = false;
    foreach (array_keys($by_atoms) as $by_atom) {

        $starred = (preg_match('/^\*/', $by_atom) ? true : false);

        $other .= "\n<td><input type='radio' name='by_atom' value='" . $by_atom . "' " .
                   ($starred ? " checked " : "") .  ">" .
                  "<font>$by_atoms[$by_atom]" .
                  "";
    }
    $other .= "\n<tr><td bgcolor=$lgray>Display";
    $other .= "\n<td colspan=2><input type='checkbox' name='sql'>SQL$sp";
    $other .= "\n<input type='checkbox' name='cgi'>CGI$sp";
    #$other .= "\n<input type='checkbox' checked name='1-page'>1-page$sp";
    #$other .= "\n<input type='hidden' name='1-page' value='on'>1-page$sp";
    $other .= "\n</table>";

    # --- Print it all

    # html body
    print "\n<body>";

    # 1-page option is initially spawning a new page, but shouldn't
    print "\n<form name=$form_id target=" . (($_GET['1-page'] == 'on') ? "_self" : "_self") . ">";
    print "\n<table align=center border=1 cellspacing=1 cellpadding=5 width=95%>";
    print "\n<th align=center rowspan=4 bgcolor=$dgray><font size=24pt color=$lllgray>" .
            "<a href='$domain' class='lgray_ln'>" .
                "<img width=55 height=55 src='./open-mpi-logo.png'>" .
            "</a><br>" .
            "<img width=55 height=525 src='./logo.gif'>";
    #print "\n<th align=center colspan=2 rowspan=1 bgcolor=$dgray><font size=24pt color=$lllgray>" .
    #       "Open MPI $br Test $br Reporter";
    print "\n<tr><td bgcolor=$lllgray valign=top>";
    print $main_pulldowns;
    print "\n<td bgcolor=$lllgray rowspan=3 valign=top>";
    print $filters;
    print "\n<tr><td bgcolor=$lllgray>";
    print $pulldowns;
    print "\n<tr><td bgcolor=$lllgray>";
    print $other;
    print "\n<tr bgcolor=$gray>";
    print "\n<td bgcolor=$gray colspan=3>";
    print "\n<table align=center border=1 cellspacing=1 cellpadding=5>";
    print "\n<tr>";
    print "\n<td bgcolor=$lllgray valign=center><input type='submit' name='go' value='Table'>";
    print "\n<td bgcolor=$lllgray valign=center><input type='reset' value='Reset'>";
    print "\n<td bgcolor=$lgray valign=center>";
    print "\n<a href='./reporter_help.html' class='lgray_ln' target=_blank>[Help]</a>";
    #print "\n<td bgcolor=$lllgray valign=center><input type='submit' value='Graph'>";
    print "\n</form>";
    print "\n</table>";
    print "\n</table>";
    print "\n<br><br><br>";
}

if (isset($_GET['go']))
# while (1)
{

    # In the query tool, there is just a single 'level' of detail per
    # invocation of the script. So we can mostly ignore nested [$level] arrays

    # Print a report ...

    if ($_GET['cgi'] == 'on')
        dump_cgi_params();

    # --- Hack CGI params

    # mainfield_ params are a little quirkier than the others

    # Are they filtering on a phase-specific field?
    $which_phases = which_phase_specific_filter($_GET);
    $phases['per_level'] = $which_phases ? $which_phases : $phases['per_level'];

    # Did they select a phase?
    if (($_GET[$cgi_abbrevs['mainfield'] . 'phase'] == $All)) {

        # Make sure their phase-specific filters don't conflict with their
        # phase selection
        # (If $which_phases is an array of all possible phases ...)
        if (sizeof($which_phases) == sizeof($phases['per_script']))
            $phases['per_level'] = $phases['per_script'];
        else
            $phases['per_level'] = $which_phases;
    } else {
        $phases['per_level'] = array($_GET[$cgi_abbrevs['mainfield'] . 'phase']);
    }

    $res_filter  = get_results_filter($_GET[$cgi_abbrevs['mainfield'] . 'success']);
    $sql_filters = get_date_filter($_GET[$cgi_abbrevs['mainfield'] . "$timestamp"]);
    $sql_filters = array_merge($sql_filters, get_menu_filters($_GET));
    $sql_filters = array_merge($sql_filters, get_textfield_filters($_GET));

    $sql_filters['per_script'] = $sql_filters;

    $config['filter'][$level] = array();

    # Blech - I'll use this gnarly config var to filter on 'success'
    foreach ($phases['per_level'] as $phase)
        $config['filter'][$level][$phase] = $res_filter;

    $cgi_selects = array();

    # agg_timestamp is an oddball agg_ in that it creates a select
    $agg_timestamp = $_GET[$cgi_abbrevs['mainfield'] . 'agg_timestamp'];
    if ($agg_timestamp != "-")
        $cgi_selects = array($agg_timestamp_selects[$agg_timestamp]);

    $cgi_selects = array_merge($cgi_selects, get_select_fields($_GET));

    # Show less when they checkbox "aggregate"
    $cgi_selects = array_filter($cgi_selects, "is_not_rolled");

    # Add additional information if they select only a single phase

    # if (sizeof($phases['per_level']) == 1)
    #     $cgi_selects =
    #         array_merge($cgi_selects, $config['add_params'][$level][$phases['per_level'][0]]);

    $selects['per_script']['params'] = $cgi_selects;

    $config['by_run'][$level] = strstr($_GET["by_atom"],"by_test_run") ? true : false;

    # Print a title for each level-section
    $level_info = "";
    if ($config['show'][$level]) {
        if ($config['label'][$level]) {
            $level_info .= "\n<br><font size='+3'>" . $config['label'][$level] . "</font>";
            $level_info .= "\n<br><font size='-1'>" .
                            ($config['by_run'][$level] ?
                                "(By $client test run)" :
                                "(By $client test case)") .
                            "</font><br><br>";
        }
        #$level_info .= "\n<br><i>$level</i><br>";
        $level_info .= "\n<table border='0' width='100%'>";
        $level_info .= "\n<tr>";
        $level_info .= "\n<td valign='top'>";
    }

    #
    # if (sizeof($config['suppress'][$level])) {
    #     foreach ($phases['per_script'] as $ph) {
    #         if (! $config['suppress'][$level][$ph])
    #             array_push($phases['per_level'], $ph);
    #     }
    # }

    # Push another field onto "select list" each iteration
    # (This line is the critical piece to the 'level' idea)
    # if ($params['all'])
    #     array_push($selects['per_script']['params'], array_shift($params['all']));

    $selects['per_level']['params'] = array();
    $selects['per_level']['results'] = array();

    # Split out selects into params and results
    $selects['per_level']['params'] =
        array_merge(
            ($config['by_run'][$level] ?
                array_diff($selects['per_script']['params'],$fields_run_key) :
                $selects['per_script']['params'])
            #($config['by_run'][$level] ? $fields_run_key : null),
        );

    # We always need to get the first table by case, before aggregating
    # runs from that result set
    $selects['per_level']['results'] =
        get_phase_result_selects($phases['per_level'], 'by_case');

    $unioned_queries = array();

    # Compose phase-specific queries and union them for each level

    foreach ($phases['per_level'] as $phase) {

        # db table names are identical to phase names used in this script
        $db_table = $phase;

        # Check to see if there are special filters for this level & phase
        if ($config['filter'][$level][$phase])
            $sql_filters['per_phase'] =
                array_merge($sql_filters['per_script'], $config['filter'][$level][$phase]);
        else
            $sql_filters['per_phase'] = $sql_filters['per_script'];

        # Create a tmp list of select fields to copy from and manipulate
        $selects['per_phase']['all'] = array();
        $selects['per_phase']['all'] =
            array_merge(
                ($config['by_run'][$level] ?
                    array_diff($selects['per_level']['params'],$fields_run_key) :
                    $selects['per_level']['params']),
                ($config['by_run'][$level] ?
                    $fields_run_key :
                    null),
                (($config['add_params'][$level][$phase] and
                 (sizeof($phases['per_level']) < 3)) ?
                    $config['add_params'][$level][$phase] :
                     null),

                 $results['from_perm_tbl'][$phase],

                # Give good reason to add that far right link!
                (($config['details'][$level][$phase] and
                  ! $config['by_run'][$level] and
                 (sizeof($phases['per_level']) == 1)) ?
                    $config['details'][$level][$phase] :
                     null)
            );

        # Assemble GROUP BY and ORDER BY clauses.
        # If we do an SQL string function, trim it to just the arg
        # (groupbys and orderbys are the same lists as selects, without the string functions
        # and result fields)
        $groupbys = array();
        $orderbys = array();

        # [ ] Use a combo of array_map and array_filter here
        foreach ($selects['per_phase']['all'] as $s) {

            # Do not group or sort on these two aggregates
            if (@preg_match("/test_pass|success/i", $s))
                continue;

            $s = get_as_alias($s);
            array_push($groupbys, $s);
            array_push($orderbys, $s);
        }

        $groupbys_str = join(",\n", $groupbys);
        $orderbys_str = join(",\n", $orderbys);
        $selects_str = join(",\n", $selects['per_phase']['all']);

        # Compose SQL query
        $cmd = "\nSELECT $selects_str \nFROM $db_table JOIN $once_db_table USING (run_index) ";
        $cmd .= ((sizeof($sql_filters['per_phase']) > 0) ?
                "\nWHERE " . join("\n AND \n", $sql_filters['per_phase']) :
                "") . " ";

        array_push($unioned_queries, $cmd);

    }   # foreach ($phases['per_level'] as $phase)

    # Create a plain-english description of the filters
    if (sizeof($sql_filters['per_script']) > 0)
        $filters_desc_html_table = "<table border=1><tr><th bgcolor=$lgray colspan=2>Query Description" .
            sprintf_("\n<tr>%s", array_map('sql_to_en', $sql_filters['per_script'])) .

            # This setting is not used at the $sql_filters level
            "<tr><td bgcolor=$lgray>Count <td bgcolor=$llgray>" .
            ($config['by_run'][$level] ? "By test run" : "By test case") .
            "</table><br>";
    else
        $filters_desc_html_table = null;

    # Concat the results from the three phases
    $cmd = join("\n UNION ALL \n", $unioned_queries);

    $cmd = "\nSELECT * INTO TEMPORARY TABLE tmp FROM (" . $cmd . ") as u;";

    # Do they want to see the sql query?
    if ($_GET['sql'] == 'on')
        print("\nSQL: <pre>" . html_to_txt($cmd) . "</pre>");

    pg_query_("\n$cmd");

    # Unfortunately, we need to split out 'params', 'results', and 'details'
    # fields so we can create headers and linked data correctly
    $selects['per_level']['params'] =
        array_map('get_as_alias',
            array_merge(
                $selects['per_level']['params'],
                (($config['add_params'][$level] and (sizeof($phases['per_level']) < 3)) ?
                    $config['add_params'][$level][$phases['per_level'][0]] : # blech!
                    null)
            )
        );
    $selects['per_level']['details'] =
        array_map('get_as_alias',
            array_merge(

                # Give good reason to add that far right link!
                (($config['details'][$level][$phase] and
                  ! $config['by_run'][$level] and
                 (sizeof($phases['per_level']) == 1)) ?
                    $config['details'][$level][$phase] :
                     null)
            )
        );
    $selects['per_level']['all'] =
        array_merge(
            $selects['per_level']['params'],
            $selects['per_level']['results'],
            $selects['per_level']['details']
        );

    # Select from the unioned tables which is now named 'tmp'
    $cmd = "\nSELECT " .
            join(",\n", $selects['per_level']['all']) .  " " .
            "\n\tFROM tmp ";
    if ($groupbys_str)
        $cmd .= "\n\tGROUP BY $groupbys_str ";
    if ($orderbys_str)
        $cmd .= "\n\tORDER BY $orderbys_str ";

    $sub_query_alias = 'run_atomic';

    if ($config['by_run'][$level]) {

        $selects['per_script']['params'] =
            get_non_run_key_params($selects['per_script']['params']);

        $cmd = "\nSELECT " .
                join(",\n",
                    array_merge(
                        $selects['per_level']['params'],
                        get_phase_result_selects($phases['per_level'], 'by_run')
                    )
                ) .
                "\nFROM ($cmd) as $sub_query_alias " .
                "\nGROUP BY $sub_query_alias.". join(",\n$sub_query_alias.",$selects['per_level']['params']);
    }

    # Do they want to see the SQL query?
    if ($_GET['sql'] == 'on')
        print("\nSQL: <pre>" . html_to_txt($cmd) . "</pre>");

    $rows = pg_query_("\n$cmd");

    # Create a new temp table for every level
    $cmd = "\nDROP TABLE tmp;";
    pg_query_("\n$cmd");

    # --- Generate headers

    # Param headers
    $headers['params'] = array();
    foreach (array_map('get_as_alias', $selects['per_level']['params']) as $key) {
        $header = $field_labels[$key];
        array_push($headers['params'], $header);
    }

    $data_html_table = "";

    if ($rows) {

        $data_html_table .= "\n\n<$align><table border=1 width='100%'>";

        # Display headers
        $data_html_table .= sprintf_("\n<th bgcolor='$thcolor' rowspan=2>%s", $headers['params']);

        foreach ($phases['per_level'] as $ph) {
            $data_html_table .= sprintf("\n<th bgcolor='$thcolor' colspan=2>%s", $phase_labels[$ph]);
        }
        if ($config['details'][$level] and (sizeof($phases['per_level']) == 1))
            $data_html_table .= sprintf("\n<th bgcolor='$thcolor' rowspan=2>%s", "[i]");

        $data_html_table .= ("\n<tr>");

        # Yucky hard-coding, but will it ever be anything but pass/fail here?
        foreach ($phases['per_level'] as $p) {
            $data_html_table .= sprintf("\n<th bgcolor='$thcolor'>%s", 'Pass');
            $data_html_table .= sprintf("\n<th bgcolor='$thcolor'>%s", 'Fail');
        }

        # Display data rows
        while ($row = array_shift($rows)) {

            $details_html_table = "";

            # Make the row clickable if there's clickable info for this query
            if ($config['details'][$level] and (sizeof($phases['per_level']) == 1)) {

                $len = sizeof($selects['per_level']['details']);
                $lf_cols = array_splice($row, sizeof($row) - $len, $len);

                $details_html_table = "\n\n" .
                    "<table border=1 width=100%><tr><th bgcolor=$thcolor>Details" .
                    "<tr><td bgcolor=$lllgray width=100%>";

                for ($i = 0; $i < $len; $i++) {
                    $field = $selects['per_level']['details'][$i];
                    $field  = $field_labels[$field] ? $field_labels[$field] : $field;
                    $details_html_table .= "\n<br><b>" .
                            $field . "</b>:<br>" .
                            "<tt>" . txt_to_html($lf_cols[$i]) . "</tt><br>";
                }
                $details_html_table .= "</table></body>";
            }

            # Translate_data_cell result fields
            for ($i = 0; $i < sizeof($row); $i++) {
                $row[$i] =
                    (! @empty($translate_data_cell[$row[$i]])) ? $translate_data_cell[$row[$i]] : $row[$i];
            }

            # 'pass/fail' are always in the far right cols
            $len = sizeof($phases['per_level']) * sizeof($results_types);
            $result_cols = array_splice($row, sizeof($row) - $len, $len);

            $data_html_table .= "\n<tr>" . sprintf_("\n<td bgcolor=$white>%s", $row);

            for ($i = 0; $i < sizeof($result_cols); $i += 2) {
                    $data_html_table .= "\n<td align='right' bgcolor='" .
                            (($result_cols[$i] > 0) ? $lgreen : $lgray) . "'>$result_cols[$i]";
                    $data_html_table .= "\n<td align='right' bgcolor='" .
                            (($result_cols[$i + 1] > 0) ? $lred : $lgray) . "'>" . $result_cols[$i + 1];
            }

            if ($details_html_table) {

                $data_html_table .= "<td align=center><a href='javascript:popup(\"900\",\"750\",\"" .
                     "[" . $config['label'][$level] . "] " .
                     "$phase_labels[$phase]: Detailed Info\",\"" .
                     strip_quotes($details_html_table) . "\",\"\",\" font-family:Courier,monospace\")' " .
                        " class='lgray_ln'><font size='-2'>" .
                     "[i]</font><a>";
            }
        }
        $data_html_table .= "\n</table>";
        $rows = true;
    }

    # Some basic info about this report's level-of-detail
    if ($level_info)
        print $level_info;

    # Report description (mostly echoing the user input and filters)
    if ($filters_desc_html_table and ! $_GET['just_results']) {
        print "<a name=report></a>";
        print "<br><table width=100%><tr>";
        print "<td valign=top>$filters_desc_html_table";
        print "<td valign=top align='right'><a href='$domain'><img src='open-mpi-logo.png' border=0 height=75></a>";
        print "</table><br>";
    }

    # Do not show a blank table
    if (! $rows) {

        print "<b><i>No data available for the specified query.</i></b>";

    } else {

        # Insert useful information on the left-hand side?
        print "\n\n<$align>" .
              "\n\n<!-- report_start -->\n\n" .
              "<table width='100%' cellpadding=5>" .
              "<tr>" .
              #"<th bgcolor='$lgray' rowspan=2 colspan=2 valign='top' width=0px>[insert link here]" .
              #"<font size='+2'>Level: " . $level . "</font>" .
              "";

        # Aggregates description popup
        if (0) {
        #if ($desc_html_table)
            print
              "<br><a href='javascript:popup(\"500\",\"550\",\"[" . $config['label'][$level] . "] " .
                    " Aggregated Fields\",\"" .
                      strip_quotes($desc_html_table) . "<p align=left><i>$aggregate_explanation</i>\",\"\")' " .
                        " class='lgray_ln'><font size='-2'>" .
              "[Aggregated Fields]</font><a>";
        }

        # *broken*
        # Additional info popup
        $details = $config['info'][$level]['runs']['name'];
        if ($details) {
            print
              "<br><a href='$details' class='lgray_ln'><font size='-2'>" .
              "[More Detail]</font><a>";
        }

        print "<td bgcolor='$lgray'>";
        print $data_html_table;
        print "\n</table>";
        print "\n\n<!-- report_end -->\n\n";

        # Mark this level as 'shown'
        $config['show'][$level] = null;
    }

    print "\n<br><br><table border=1><tr><td bgcolor=$lgray><a href='" . $domain .
            $_SERVER['PHP_SELF'] . '?' .
            dump_cgi_params_trimnulls($_GET) .
            "' class='lgray_ln'><font size='-1'>[Link to this query]</a>" .
            "</table>";

}   # if (! isset($_GET['go']))

#pg_close();
exit;


# Return the element of the list that begins with *
function is_starred($str) {
    return preg_match('/^\s*\*/',$str);
}

# pg_query_ that returns a 1D list
function pg_query_simple($cmd) {

    $rows = array();
    if ($GLOBALS['res'] = pg_query($GLOBALS["conn"], $cmd)) {
        while ($row = pg_fetch_row($GLOBALS['res'])) {
            array_push($rows, $row);
        }
    }
    else {
        debug("\n<br>postgres: " . pg_last_error() . "\n" . pg_result_error());
    }
    return array_map('join',$rows);
}

# pg_query that returns a 2D list
function pg_query_($cmd) {

    $rows = array();
    if ($GLOBALS['res'] = pg_query($GLOBALS["conn"], $cmd)) {
        while ($row = pg_fetch_row($GLOBALS['res'])) {
            array_push($rows, $row);
        }

        # Think about the advantages in returning a hash of results
        # versus an array (esp. wrt readability)
        # $rows = pg_fetch_all($GLOBALS['res']);
    }
    else {
        debug("\n<br>postgres: " . pg_last_error() . "\n" . pg_result_error());
    }
    return $rows;
}

function debug($str) {
    if ($GLOBALS['debug'] or $GLOBALS['verbose'])
        print("\n$str");
}

function var_dump_($a) {
    if ($GLOBALS['verbose'])
        var_dump("\n<br>$a");
}

# actually see the nice identation var_dump provides
function var_dump_html($desc,$var) {
    if ($GLOBALS['verbose'])
        var_dump("\n<br><pre>$desc",$var,"</pre>");
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

# ' = 047 x27
# " = 042 x22
# Strip quotes from html.
# Needed for sending 'content' argument to a javascript popup function
function strip_quotes($str) {
    return preg_replace('/\x22|\x27/','',$str);
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

# sprintf for arrays. Return the entire array sent through
# sprintf, concatenated
# This really seems like an array_map sort of thing, but
# php has a different concept of map than perl
#
# Returns a string
function sprintf_($format, $arr) {
    $str = "";
    foreach ($arr as $s) {
        $str .= sprintf($format,$s);
    }
    return $str;
}

# sprintf for arrays. Return the entire array sent through
# sprintf
# This really seems like an array_map sort of thing, but
# php has a different concept of map than perl
#
# Returns an array()
function lsprintf_($format, $arr) {
    $arr2 = array();
    foreach ($arr as $s) {
        array_push($arr2, sprintf($format,$s));
    }
    return $arr2;
}

# Convert some txt chars to html codes
function txt_to_html($str) {
    $str = preg_replace('/\n\r|\n|\r/','<br>',$str);
    #$str = preg_replace('/\s+/','&nbsp;',$str);
    return $str;
}

# Convert some html codes to txt chars
function html_to_txt($str) {
    $str = preg_replace('/<\w+>/','*tag*',$str);
    return $str;
}

# Convert some html codes to txt chars
function html_to_txt2($str) {
    $str = preg_replace('/<br>/',' - ',$str);
    $str = preg_replace('/<\w+>/','',$str);
    return $str;
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

# Prints an HTML table of _GET and _POST vars
function dump_cgi_params() {

    global $lgray;
    global $dgray;

    $cols = 3;

    print "\n\n<table width=80% border=1>";
    print "\n\n<tr><th bgcolor=$dgray colspan=" . $cols * 2 . ">_GET";

    $i = 0;
    foreach (array_keys($_GET) as $k) {
        print "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
            "<td bgcolor=$lgray>" . $k . "<td>$_GET[$k]";
    }
    print "\n\n</table>";

    # print "\n\n<table width=80% border=1>";
    # print "\n\n<tr><th bgcolor=$dgray colspan=" . $cols * 2 . ">_POST";

    # foreach (array_keys($_POST) as $k) {
    #     print "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
    #         "<td bgcolor=$lgray>" . $k . "<td>$_POST[$k]";
    # }
    # print "\n\n</table>";
}

# Returns a trimmed query string
function dump_cgi_params_trimnulls($params) {

    global $cgi_abbrevs;

    foreach (array_keys($params) as $k) {

        # Only hash these textfield-filter_type pairs if BOTH are non-null
        # X: textfield_ shouldn't be a magic string
        if (preg_match("/" . $cgi_abbrevs['textfield'] . "(\w+)|" .
                             $cgi_abbrevs['filter_types'] . "(\w+)/i", $k, $m)) {

            $f     = $m[1];
            $type  = "" . $cgi_abbrevs['filter_types'] . "$f";
            $field = "" . $cgi_abbrevs['textfield'] . "$f";

            if ($params[$field]) {
                $hash[$type] = $params[$type];
                $hash[$field] = $params[$field];
            }

        } else {
            $hash[$k] = $params[$k];
        }
    }

    $str = "";
    foreach (array_keys($hash) as $k) {
        if ($hash[$k] != null)
            $str .= '&' . $k . "=$_GET[$k]";
    }
    return $str;
}

# return string concatenated to itself x times
function repeat($str, $x) {
    print $debug;
    $orig = $str;
    for ($i = 0; $i < $x-1; $i++){
        $orig .= $str;
    }
    return $orig;
}

# return string concatenated to itself x times
function exit_($str) {
    print $str;
    exit;
}

# Take in a filter (e.g., 'yesterday', 'today', etc.), and return the SQL date
# filter
# X: Create a get_en_date_string function
function get_date_filter($filter) {

    global $words_to_numerals;

    $filters = array();

    # (Currently, we're only doing all-levels filtering on timestamp)
    if (@preg_match("/past.*week/i", $filter, $m)) {

        array_push($filters, "start_test_timestamp > now() - interval '1 week'");
    }
    elseif (@preg_match("/yesterday/i", $filter, $m)) {
        array_push($filters, "start_test_timestamp > 'yesterday'");

    }
    elseif (@preg_match("/today/i", $filter, $m)) {
        array_push($filters, "start_test_timestamp > date_trunc('day', now())");
    }
    elseif (@preg_match("/past\s*(\w+)\s*(\w+)/i", $filter, $m)) {
        array_push($filters, "start_test_timestamp > now() - interval '" .
                    $words_to_numerals[$m[1]] . " " . $m[2] . "'");

    }
    return $filters;
}

# The idea is that the 'Aggregate' (or 'Roll') checkbox makes for a more
# generalized report


# Return list of WHERE filters
function get_menu_filters($params) {

    global $All;
    global $cgi_abbrevs;

    $filters = array();

    foreach (array_keys($params) as $p) {
        if (preg_match("/^" . $cgi_abbrevs['menufield'] . "(\w+)$/i", $p, $m)) {
            $value = $params[$p];
            if ($value != $All)
                array_push($filters, $m[1] . " = '" . $value . "'");
        }
    }
    return $filters;
}

# Return list of test results (pass/fail)
function get_results_filter($param) {

    $filters = array();

    if (preg_match("/pass/i", $param)) {
        array_push($filters, "success = 't'");
    }
    elseif (preg_match("/fail/i", $param)) {
        array_push($filters, "success = 'f'");
    }

    return $filters;
}

# Return list of WHERE filters
# X: Provide more flexible AND|OR searching
function get_textfield_filters($params) {

    global $cgi_abbrevs;

    $filters = array();

    foreach (array_keys($params) as $p) {

        if (preg_match("/^" . $cgi_abbrevs['textfield'] . "(\w+)$/i", $p, $m)) {

            $field = $m[1];
            $value = strip_quotes($params[$p]);
            $type  = $params["" . $cgi_abbrevs['filter_types'] . "$field"];

            if (! preg_match("/^\s*$/i", $value)) {

                if (preg_match("/contains/i", $type))
                    array_push($filters, $field . " ~ '" . $value . "'");
                elseif (preg_match("/begins\s*with/i", $type))
                    array_push($filters, $field . " ~ '^" . $value . "'");
                elseif (preg_match("/ends\s*with/i", $type))
                    array_push($filters, $field . " ~ '" . $value . "$'");
                elseif (preg_match("/does\s*not\s*contain/i", $type))
                    array_push($filters, $field . " !~ '" . $value . "'");

                elseif (preg_match("/equals/i", $type))
                    array_push($filters, $field . " = '" . $value . "'");
                elseif (preg_match("/less/i", $type))
                    array_push($filters, $field . " < '" . $value . "'");
                elseif (preg_match("/greater/i", $type))
                    array_push($filters, $field . " > '" . $value . "'");
            }
        }
    }
    return $filters;
}

# X: This function should get scrapped someday.
#    We should be able to show all phases, broken into three tables
# If a phase specific field is filtered on, return the name of that phase
function which_phase_specific_filter($params) {

    global $columns;
    global $textfield_tables;
    global $cgi_abbrevs;

    # [!] We have to switch the ordering of how we pick up on phase-specific fields.
    #     In other words, check phase-specific fields before phase-independent fields.

    foreach (array_reverse(array_keys($textfield_tables)) as $t) {

        foreach (array_keys($params) as $p) {

            # The only phase-specific fields are textfields (for now, anyway)
            if (preg_match("/^" . $cgi_abbrevs['textfield'] . "(\w+)$/i", $p, $m)) {

                $field = $m[1];
                $value = $params[$p];

                if (! preg_match("/^\s*$/i", $value)) {

                    # X: Not liking how I use is_int (what if the key is a string?)
                    if (is_int(array_search($field, array_keys($columns[$t])))) {

                        return $textfield_tables[$t]["phases"];
                    }
                }
            }
        }
    }

    # return all the phases by default
    return $textfield_tables["general_a"]["phases"];
}

# Are we grouping on $field?
function is_rolled($field) {
    $field = get_as_alias($field);
    if ($_GET["agg_$field"] == 'on')
        return true;
}
function is_not_rolled($field) {
    $field = get_as_alias($field);
    if ($_GET["agg_$field"] != 'on')
        return true;
}


# Return list of field_ selects
function get_select_fields($params) {

    global $field_clauses;
    global $cgi_abbrevs;

    $selects = array();

    foreach (array_keys($params) as $p) {
        if (preg_match("/^" . $cgi_abbrevs['menufield'] . "(\w+)$/i", $p, $m)) {
            $f = $m[1];
            array_push($selects, ($field_clauses[$f] ? $field_clauses[$f] : $f));
        }
    }
    return $selects;
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

# prefix a list of strings with $str, and return the list
function prefix($prefix, $list) {

    $arr = array();

    foreach ($list as $elem) {
        array_push($arr, $prefix . $elem);
    }
    return $arr;
}

function populate_menu($list, $table) {

    foreach ($list as $field) {

        if (preg_match("/timestamp/i", $field)) {
            $clause = "substring($field from 0 for 11) as $field";
        } else {
            $clause = $field;
        }

        if ($_GET['sql'] == 'on')
            print("\nSQL: <pre>" . html_to_txt($cmd) . "</pre>");

        $alias = get_as_alias($field);

        $cmd = "SELECT $clause FROM $table " .
            "GROUP BY $alias " .
            "ORDER BY $alias ;";

        $rows = array_map('html_to_txt2', pg_query_simple($cmd));

        $menu[$alias] = array();
        $menu[$alias] = $rows;
    }
    return $menu;
}

?>
</body>
</html>
