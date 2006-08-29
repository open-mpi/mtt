<!--

 Copyright (c) 2006 Sun Microsystems, Inc.
                         All rights reserved.
 $COPYRIGHT$

 Additional copyrights may follow

 $HEADER$

-->

<html>
<head>
    <title>Open MPI Test Results</title>

    <script language="javascript" type="text/javascript">

        function popup(width,height,title,content,style)
        {
            newwindow2=window.open('','name','height=' + height + ',width=' + width + ' scrollbars=yes');
            var tmp = newwindow2.document;
            tmp.write('<html><head><title>' + title + '</title>');
            tmp.write('<body ' + style + '>' + content + '</body></html>');
            tmp.close();
        }

    </script>

    <style type="text/css">
        a.lgray_ln:link    { color: #F8F8F8 } /* for unvisited links */
        a.lgray_ln:visited { color: #555555 } /* for visited links */
        a.lgray_ln:active  { color: #FFFFFF } /* when link is clicked */
        a.lgray_ln:hover   { color: #FFFF40 } /* when mouse is over link */
        </style>

</head>
<body>
<?php

#
#
# Nightly email summary report
#
# Basic idea: iterate over the three MTT phases, gradually displaying higher
# granularity of test results.  SQL-wise, this means adding an additional
# select/grouping item to the query after each iteration
#
#

#     
#   todo:
#     
# [ ] Create "alerts", a la Google News Alerts
#     e.g., "email me when this type of error occurs"
# [ ] Offload more string processing to postgres
# [ ] Change anything hardcoded (e.g., col names) to dynamically eval'd 
#     (create a variant of array_map)
# [-] Use pg_select, not pg_query (nevermind, php.net says pg_select is
#     experimental)
# [ ] Do not print tables with 0 rows of data
# [ ] Format cgi option (txt, html, pdf)
# [ ] Graphing
# [ ] Alias function names to cut-down on verbosity?
# [x] Display pass and fail in a single row
# [ ] Look into query optimization (e.g., stored procedures,
#     saved queries, EXPLAIN/ANALYZE ...)
# [ ] Somehow unify Run.pm with correctness.sql - using an xml file?
# [ ] Use references where appropriate (e.g., returning large arrays?)
# [ ] Use open-mpi.org CSS stylesheets
# [ ] Add <tfoot> row showing totals (maybe play with <tbody> to delineate tables
# [ ] Add row numbering
# [ ] Throttling - e.g., "this query will generate a ton of data, let's look at it
#     in chunks"
# [x] Fix the newline issues in the Detailed Info popups (set font to courier)
# [x] Include more shades in the colorized pass/fail columns
# [ ] Experiment with levels_strike_column array (esp.for three-phase merging todo)
# [ ] Come up with better naming scheme for query clause lists (e.g.,
#     selects['slave']['all']['main'][$phase], etc.)
# [ ] Try to better split out printing/querying
# [ ] Get rid of php warnings that show up from command-line
#     
     
$GLOBALS['verbose'] = 0;
$GLOBALS['debug'] = 0;
$GLOBALS['nosql'] = 0;
$GLOBALS['res'] = 0;
$GLOBALS['html'] = 1;

$_GET['debug'] = (isset($GLOBALS['debug']) && $GLOBALS['debug']) ? 'y' : 
     (isset($_GET['debug']) ? $_GET['debug'] : 'n');

# HTML variables

$domain  = "http://www.open-mpi.org";

$client = "MTT";

$lgray   = "#C0C0C0";
$llgray  = "#DEDEDE";
$lllgray = "#E8E8E8";
$lred    = "#FFC0C0";
$lgreen  = "#C0FFC0";
$lyellow = "#FFFFC0";
$white   = "#FFFFFF";
$align   = "center";

$thcolor  = $llgray;

# Corresponding db tables for "MPI Install", "Test Build", and "Test Run" phases
$phases['per_script'] = array(
    "installs",
    "builds",
    "runs"
);
$br = " ";
$phase_labels = array(
    "installs" => "MPI" . $br . "Installs",
    "builds"   => "Test" . $br . "Builds",
    "runs"     => "Test" . $br . "Runs",
);
# Corresponding db tables for "MPI Install", "Test Build", and "Test Run" phases
$atoms = array(
    "case",
    "run",
);

# Corresponding db tables for "MPI Install", "Test Build", and "Test Run" phases
$results = array(
    "pass",
    "fail",
);

# Note: test_pass/success fields are appended to all SELECTs,
#       and are thus not listed in the following arrays.
#       For now, comment out fields we're not including in the summary report.

# phase => array(fields belonging to phase)

$cluster_field = 
    "('<font size=-2>' || platform_id || '<br>' || hostname || '</font>') as cluster";

# Common to all three phases on the left side of table
$params['left_common'] = array(
    "platform_hardware",
    "platform_type",
    #"platform_id",
    "$cluster_field",
    #"os_name",     # what does this field tell us that platform type does not?
    #"os_version",  # what does this field tell us that os_name does not?
    "mpi_name",
    #"hostname",
    "start_run_timestamp",
    "mpi_version",
    #"start_test_timestamp",
    #"submit_test_timestamp",
    #"test_duration_interval",
    #"mpi_get_section_name",
    #"merge_stdout_stderr",
    #"stderr",
    #"stdout",
    #"environment",
    #"mtt_version_major",
    #"mtt_version_minor",
);

$params['installs'] = array(
    "compiler_name as section",     # hmm, installs section is compiler - odd
    "mpi_install_section_name as section_name",
    #"compiler_version",
    #"configure_arguments",
    #"vpath_mode",
    #"result_message",
);

$params['builds'] = array(
    "test_build_section_name as section",
    "compiler_name as section_name",
    #"compiler_version",
    #"configure_arguments",
    #"result_message",
);

$params['runs'] = array(
    "test_run_section_name as section",
    "test_name as section_name",
    #"test_build_section_name",
    #"test_command",
    "test_np",
    #"result_message",
);

# Common to all three phases on the right side of table
$params['right_common'] = array(
    #"submit_test_timestamp",
    #"test_duration_interval",
    #"mpi_get_section_name",
    #"merge_stdout_stderr",
    #"stderr",
    #"stdout",
    #"environment",
    #"mtt_version_major",
    #"mtt_version_minor",
);

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

var_dump_("\n256: results = ",$results);
var_dump_("get_phase_result_selects ", get_phase_result_selects(array("installs","builds"), 'by_run'));


# db field name => html column header This could be done using the SQL 'as'
# construct (?), but that's a lot of regexp-ing
#
# Or use pg_fetch_all which returns a hash, not a numerically indexed array
# (we're okay as long as php can preserve the array creation order)
$sp = "&nbsp;";
$field_labels = array(
    "platform_hardware"        => "Hardware",
    "platform_type"            => "Os",
    "platform_id"              => "Cluster",
    "cluster"                  => "Cluster",
    "os_name"                  => "Os",
    "os_version"               => "Os".$sp."ver",
    "mpi_name"                 => "Mpi",
    "mpi_version"              => "Mpi".$sp."rev",
    "hostname"                 => "Host",
    "start_test_timestamp"     => "Date",
    "start_run_timestamp"      => "Timestamp" .$sp."(GMT)",
    "submit_test_timestamp"    => "Submit".$sp."time",
    "test_duration_interval"   => "Duration",
    "mpi_get_section_name"     => "Section",
    "mpi_install_section_name" => "Section",
    "test_build_section_name"  => "Section",
    "test_run_section_name"    => "Section",
    "section"                  => "Section",
    "merge_stdout_stderr"      => "Merge".$sp."outputs",
    "stderr"                   => "Stderr",
    "stdout"                   => "Stdout",
    "environment"              => "Env",
    "mtt_version_major"        => "Mtt".$sp."ver".$sp."maj",
    "mtt_version_minor"        => "Mtt".$sp."ver".$sp."min",
    "compiler_name"            => "Compiler",
    "compiler_version"         => "Compiler".$sp."ver",
    "configure_arguments"      => "Config".$sp."args",
    "vpath_mode"               => "Vpath",
    "result_message"           => "Result".$sp."msg",
    "test_name"                => "Test",
    "name"                     => "Test name",
    "section_name"             => "Test name",
    "test_command"             => "Cmd",
    "test_np"                  => "Np",
    "result_message"           => "Test".$sp."msg",
    "test_message"             => "Test".$sp."msg",
    "test_pass"                => "Result",
    "success"                  => "Result",
    "count"                    => "Count",
    "date"                     => "Date",
    "time"                     => "Time",
);

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
    #'ia32' => 'i86pc',
);

# Initialize params
$params['all'] = array_merge($params['left_common']);

# Setup db connection
$dbname = isset($_GET['db']) ? $_GET['db'] : "mtt";
$dbname = isset($argv)       ? $argv[1]    : $dbname;
$user   = "mtt";
$pass   = "3o4m5p6i";

$GLOBALS["conn"] = pg_connect("host=localhost port=5432 dbname=$dbname user=$user password=$pass");

debug("\n<br>postgres: " . pg_last_error() . "\n" . pg_result_error());

$once_db_table = "once";

# By default, don't print a boatload of tables, just a few iterations
# If they use &verbose=y, print the boatload
$level_param = isset($_GET['level']) ? $_GET['level'] : 0;

$num_cols = sizeof($params['left_common']) + sizeof($params['right_common']) +
            max(array_map('sizeof', array($params['runs'], $params['builds'], $params['installs'])));
debug("num_cols = " . $num_cols);

#
# The report configuration
#
# (The following hash would be nicer as an external config file)
#

$first_lev  = 1;
$second_lev = 2;
$third_lev  = 5;
$fourth_lev = 6;

if (isset($_GET['verbose']) && $_GET['verbose'] == 'y') {
    $config['show'] = array_fill(0, $num_cols, true);
    var_dump_("\nconfig[show] = ", $config['show']);
}

# I liked the up/down buttons, oh well
#
elseif (isset($_GET['go']) && $_GET['go'] == 'down') {
    if ($_GET['level'] < ($num_cols - 1))
        $config['show'] = array(++$_GET['level'] => true);
    else
        $config['show'] = array($_GET['level'] => true);
}
elseif (isset($_GET['go']) && $_GET['go'] == 'up') {
    if ($_GET['level'] > 0)
        $config['show'] = array(--$_GET['level'] => true);
    else
        $config['show'] = array($_GET['level'] => true);
}

# Default level-specific values
else {
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
    $first_lev => true,
    $second_lev => true,
);
$config['label'] = array(
    $first_lev => "$client Executive Summary",
    $second_lev => "$client Cluster Summary",
    $third_lev => "$client Test Suites Summary",
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
$config['details'] = array(
    6 => array(
        'runs' => array(
                    "test_command",
                    "result_message",
                    "stderr",
                    "stdout",
                    "environment",
        ),
    ),
);

# Create SQL filters
# (Currently, we're only doing all-levels filtering on timestamp)
$sql_filters['per_script'] = array();
$date_format = "m-d-Y";
$time_format = "g:i a";
$en_date_range = "";
if (@preg_match("/last.*week/", $_GET['date'], $m)) {
    array_push($sql_filters['per_script'], "start_test_timestamp > now() - interval '1 week'");
    $en_date_range .=
        date($date_format . " " . $time_format, time() - (7 * 24 * 60 * 60)) . " - " . 
        date($date_format . " " . $time_format);
}
elseif (@preg_match("/all|infinity/", $_GET['date'], $m)) {
    $en_date_range .= "All dates";
}
else {
    array_push($sql_filters['per_script'], "start_test_timestamp > 'yesterday'");

    # 'yesterday' in postgres means yesterday at 12:00 am
    $en_date_range .=
          "Start: " . date($date_format, time() - (1 * 24 * 60 * 60)) . " 12:00 am" .
          "<br>End: &nbsp;" . date($date_format . " " . $time_format);
}
$en_date_range = txt_to_html($en_date_range);

# Display webpage title
$sp = '&nbsp;';
print <<<EOT
<$align>
<table width='1%' rules='rows' border=2 cellpadding=10>
    <tr><td width='1%'>
        <a href='http://www.open-mpi.org/'><img src='/images/open-mpi-logo.png' border=0></a>
    <td width='1%'>
        <font size='+7'>Open&nbsp;MPI Test&nbsp;Results</font>
        <br><font size='-1'>$en_date_range</font><br>
</table>
EOT;


$selects['per_script']['params'] = array();
$done = null;
$max_desc_len = 80;
$level = -1;    # I know -1 is absured, but I don't feel like changing the levels config

# Loop level-by-level
while (1) {

    $level++;

    if ($done or ($level == $num_cols))
        break;

    # Print a title for each level-section
    $level_info = "";
    if (isset($config['show'][$level])) {
        if ($config['label'][$level]) {
            $level_info .= "\n<br><font size='+3'>" . $config['label'][$level] . "</font>";
            $level_info .= "\n<br><font size='-1'>" . 
                            (isset($config['by_run'][$level]) ? 
                                "(By $client test run)" : 
                                "(By $client test case)") . 
                            "</font><br><br>";
        }
        #$level_info .= "\n<br><i>$level</i><br>";
        $level_info .= "\n<table border='0' width='100%'>";
        $level_info .= "\n<tr>";
        $level_info .= "\n<td valign='top'>";
    };

    # Determine which phases will be used at this level
    # Default: show all phases
    $phases['per_level'] = array();

    if (isset($config['suppress'][$level]) && 
        sizeof($config['suppress'][$level])) {
        foreach ($phases['per_script'] as $ph) {
            if (! isset($config['suppress'][$level][$ph]))
                array_push($phases['per_level'], $ph);
        }
    } else
        $phases['per_level'] = $phases['per_script'];

    var_dump_('phases[per_level] = ', $phases['per_level']);

    # Push another field onto "select list" each iteration
    # (This line is the critical piece to the 'level' idea)
    if ($params['all'])
        array_push($selects['per_script']['params'], array_shift($params['all']));

    $selects['per_level']['params'] = array();
    $selects['per_level']['results'] = array();

    # Split out selects into params and results
    $selects['per_level']['params'] = 
        array_merge(
            (isset($config['by_run'][$level]) ? 
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

        # Avoid a boatload of tables, show only several levels-of-detail
        if (! isset($config['show'][$level]) or 
            isset($config['suppress'][$level][$phase])) 
            continue;
        elseif (! isset($_GET['verbose']) and !
                array_search(true,$config['show']))
            $done = 1;

        # Check to see if there are special filters for this level & phase
        if (isset($config['filter'][$level][$phase]))
            $sql_filters['per_phase'] = 
                array_merge($sql_filters['per_script'], $config['filter'][$level][$phase]);
        else
            $sql_filters['per_phase'] = $sql_filters['per_script'];

        # Create a tmp list of select fields to copy from and manipulate
        $selects['per_phase']['all'] = array();
        $selects['per_phase']['all'] = 
            array_merge(
                (isset($config['by_run'][$level]) ? 
                    array_diff($selects['per_level']['params'],$fields_run_key) : 
                    $selects['per_level']['params']),
                (isset($config['by_run'][$level]) ?
                    $fields_run_key : 
                    null),
                (isset($config['add_params'][$level][$phase]) ?
                    $config['add_params'][$level][$phase] :
                     null),

                 $results['from_perm_tbl'][$phase],

                (isset($config['details'][$level][$phase]) ?
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
            if (@preg_match("/test_pass|success/", $s))
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

        # Create a plain-english description of the filters
        if (sizeof($sql_filters['per_phase']) > 0)
            $filters_desc = "<ul>" .
                     sprintf_("\n<li>%s", array_map('sql_to_en', $sql_filters['per_phase'])) . "</ul>";
        else
            $filters_desc = null;

    }   # foreach ($phases['per_level'] as $phase)
    

    # Are we skipping this level?
    if (! isset($config['show'][$level]))
        continue;

    # Concat the results from the three phases
    $cmd = join("\n UNION ALL \n", $unioned_queries);

    $cmd = "\nSELECT * INTO TEMPORARY TABLE tmp FROM (" . $cmd . ") as u;";

    # Do they want to see the sql query?
    if ($_GET['debug'] == 'y')
        print("\n<br>SQL: <pre>" . html_to_txt($cmd) . "</pre><br><br>");

    pg_query_("\n$cmd");

    # Unfortunately, we need to split out 'params', 'results', and 'details'
    # fields so we can create headers and linked data correctly
    $selects['per_level']['params'] =
        array_map('get_as_alias', 
            array_merge(
                $selects['per_level']['params'],
                (isset($config['add_params'][$level]) ?
                    $config['add_params'][$level][$phases['per_level'][0]] : # blech!
                    null)
            )
        );
    $selects['per_level']['details'] =
        array_map('get_as_alias', 
            array_merge(
                (isset($config['details'][$level][$phase]) ?
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
            "\n\tFROM tmp " .
            "\n\tGROUP BY $groupbys_str " .
            "\n\tORDER BY $orderbys_str " .
            "";

    $sub_query_alias = 'run_atomic';

    if (isset($config['by_run'][$level])) {

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
    
    var_dump_("\n651: [level: $level] selects = ", $selects);
    var_dump_("\n651: [level: $level] params = ", $params);
    var_dump_("\n651: [level: $level] results = ", $results);
    var_dump_("\n651: [level: $level] get_non_run_key_params(selects['per_script']['params']selects) = ", 
                get_non_run_key_params($selects['per_script']['params']));

    # Do they want to see the SQL query?
    if ($_GET['debug'] == 'y')
        print("\n<br>SQL: <pre>" . html_to_txt($cmd) . "</pre><br><br>");

    $rows = pg_query_("\n$cmd");

    # Create a new temp table for every level
    $cmd = "\nDROP TABLE tmp;";
    pg_query_("\n$cmd");

    # Do not show a blank table
    if (! $rows)
        continue;

    # Generate headers

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
        if (isset($config['details'][$level]))
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
            if (isset($config['details'][$level])) {

                $len = sizeof($selects['per_level']['details']);
                $lf_cols = array_splice($row, sizeof($row) - $len, $len);

                $details_html_table = "\n\n" .
                    "<table border=1 width=100%><tr><th bgcolor=$thcolor>Details" . 
                    "<tr><td bgcolor=$lllgray width=100%>";

                for ($i = 0; $i < $len; $i++) {
                    $details_html_table .= "\n<br><b>" . $selects['per_level']['details'][$i] . "</b>:<br>" . 
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
            $len = sizeof($phases['per_level']) * 2;
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
    }

    # Some basic info about this report's level-of-detail
    if ($level_info)
        print $level_info;

    print "\n\n<$align><table border='0' width='100%' cellpadding=5>" .
          "<tr><th bgcolor='$lgray' rowspan='2' colspan='2' valign='top' width='5%'>" .
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

    # Filters popup
    if ($filters_desc) {
        print
          "<br><a href='javascript:popup(\"500\",\"100\",\"[" . $config['label'][$level] . "] Filters\",\"" .
          $filters_desc . "\",\"\")' class='lgray_ln'><font size='-2'>" .
          "[Filters]</font><a>";
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

    if ($config['show'][$level])
        print("</table><br>");

    # Mark this level as 'shown'
    $config['show'][$level] = null;

}   # while (1)

pg_close();
exit;

function pg_query_($cmd) {

    $rows = array();
    if ($GLOBALS['res'] = pg_query($GLOBALS["conn"], $cmd)) {
        while ($row = pg_fetch_row($GLOBALS['res'])) {
            array_push($rows, $row);
        }

        # Think about the advantages in returning a hash of results
        # versus an array (esp. wrt readability)
        #$rows = pg_fetch_all($GLOBALS['res']);
    }
    else {
        print("\n<br>postgres: " . pg_last_error() . "\n" . pg_result_error());
    }
    return $rows;
}

function debug($str) {
    if ($GLOBALS['debug'] or $GLOBALS['verbose'])
        print("\n$str");
}

function var_dump_($a) {
    if ($GLOBALS['debug'] or $GLOBALS['verbose'])
        var_dump("\n$a");
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
function sql_to_en($str) {

    global $translate_data_cell;
    global $field_labels;

    # open single quote   &#145;  
    # close single quote  &#146;  
    # open double quotes  &#147;  
    # close double quotes &#148;  

    debug("\nsql_to_en($str) ...\n");

    $q = '[\x22|\x27]?';
    if (@preg_match("/(\w+_timestamp)/i", $str, $m)) {
        $what = $m[1];
        if (@preg_match("/>\s+$q(\w+)$q/", $str, $m)) {
            $comp = "is later than";
            $filter = $m[1];
        }
        elseif (@preg_match("/<\s+$q(\w+)$q/", $str, $m)) {
            $comp = "is earlier than";
            $filter = $m[1];
        }
        elseif (@preg_match("/=\s+$q(\w+)$q/", $str, $m)) {
            $comp = "is equal to";
            $filter = $m[1];
        }

        if (@preg_match("/yesterday/i", $filter, $m))
            $filter_parens = "(12am)";

        $en_exp = $field_labels[$what] . " " . $comp . " " . $filter .  
            ($filter_parens ? " $filter_parens" : "") .  ".";
    }
    elseif (@preg_match("/test_pass|success/i", $str, $m)) {
        $what = "result";
        if (@preg_match("/\=\s+$q(\w+)$q/", $str, $n)) {
            $comp = "is equal to";
            $filter = $translate_data_cell[$n[1]];
        }
        $en_exp = "Show only $what\x73 that are a &#145$filter&#146.";
    }

    debug("\nen_exp = $en_exp\n");
    return $en_exp;
}

# sprintf for arrays. Return the entire array sent through 
# sprintf, concatenated
# This really seems like an array_map sort of thing, but 
# php has a different concept of map than perl
function sprintf_($format, $arr) {
    $str = "";
    foreach ($arr as $s) {
        $str .= sprintf($format,$s);
    }
    return $str;
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

# Take a list of phases and the type of atom, and return a list of result
# aggregates for those phases
function get_phase_result_selects($phases, $atom) {

    global $results;

    var_dump_("\nglobal: results = ",$results);
    var_dump_("\nphases = ",$phases);
    var_dump_("\natmo = ",$atom);

    $tmp = array();

    foreach ($phases as $p) {
        $tmp = array_merge($tmp, $results['from_tmp_tbl'][$p][$atom]);
    }
    var_dump_('tmp = ',$tmp);
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


?>
</body>
</html>
