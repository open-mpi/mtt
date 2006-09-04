<?php

#
#
# Print a report in tabular format
#
#

$topdir = ".";
include_once("$topdir/database.inc");
include_once("$topdir/http.inc");
include_once("$topdir/config.inc");
include_once("$topdir/html.inc");
include_once("$topdir/reporter.inc");

if (! ($conn = pg_connect("host=localhost port=5432 dbname=$dbname user=$user password=$pass")))
    exit_("<br><b><i>Could not connect to database server.</i></b>");

debug("\n<br>postgres: " . pg_last_error() . "\n" . pg_result_error());

# Store SQL filters
$sql_filters['per_script'] = array();
$selects['per_script']['params'] = array();

# In the query tool, there is just a single 'level' of detail per
# invocation of the script. So we can mostly ignore nested [$level] arrays

if ($_GET['cgi'] == 'on') {
    dump_cgi_params($_GET, "GET");
    #dump_cgi_params($_POST, "POST");
}

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

# Blech - We'll use this gnarly config var to filter on 'success'
foreach ($phases['per_level'] as $phase)
    $config['filter'][$level][$phase] = $res_filter;

$cgi_selects = array();

# agg_timestamp is an oddball agg_ in that it creates a select
$agg_timestamp = $_GET[$cgi_abbrevs['mainfield'] . 'agg_timestamp'];
if ($agg_timestamp != "-")
    $cgi_selects = array($agg_timestamp_selects[$agg_timestamp]);

$cgi_selects = array_merge($cgi_selects, get_select_fields($_GET));

# Add additional information if they select only a single phase

if (sizeof($phases['per_level']) == 1)
    $cgi_selects =
        array_merge($cgi_selects, $config['add_params'][$level][$phases['per_level'][0]]);

# Show less when they checkbox "aggregate"
$cgi_selects = array_filter($cgi_selects, "is_not_rolled");

# Use array_unique as a safeguard against SELECT-ing duplicate fields
$selects['per_script']['params'] = array_unique($cgi_selects);

$config['by_run'][$level] = strstr($_GET["by_atom"],"by_test_run") ? true : null;

# Print a title for each level-section
$level_info = "";
if (isset($config['show'][$level])) {
    if (isset($config['label'][$level])) {
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
}

$selects['per_level']['params'] = array();
$selects['per_level']['results'] = array();

# Split out selects into params and results
$selects['per_level']['params'] =
    array_merge(
        (isset($config['by_run'][$level]) ?
            array_diff($selects['per_script']['params'], $fields_run_key) :
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
                array_diff($selects['per_level']['params'], $fields_run_key) :
                $selects['per_level']['params']),
            (isset($config['by_run'][$level]) ?
                $fields_run_key :
                null),
            # (($config['add_params'][$level][$phase] and
            #  (sizeof($phases['per_level']) < 3)) ?
            #     $config['add_params'][$level][$phase] :
            #      null),

             $results['from_perm_tbl'][$phase],

            # Give good reason to add that far right link!
            (($config['details'][$level][$phase] and
              ! isset($config['by_run'][$level]) and
              ! isset($_GET['no_details']) and
             (sizeof($phases['per_level']) == 1)) ?
                $config['details'][$level][$phase] :
                 null)
        );

    # Assemble GROUP BY and ORDER BY clauses.
    # If we do an SQL string function, trim it to just the arg (groupbys and
    # orderbys are the same lists as selects, without the string functions and
    # result fields)
    $groupbys = array();
    $orderbys = array();

    # [ ] Use a combo of array_map and array_filter here
    foreach (array_unique($selects['per_phase']['all']) as $s) {

        # Do not group or sort on these two aggregates
        if (preg_match("/test_pass|success/i", $s))
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
        (isset($config['by_run'][$level]) ? "By test run" : "By test case") .
        "</table><br>";
else
    $filters_desc_html_table = null;

# Concat the results from the three phases
$cmd = join("\n UNION ALL \n", $unioned_queries);

$cmd = "\nSELECT * INTO TEMPORARY TABLE tmp FROM (" . $cmd . ") as u;";

# Do they want to see the sql query?
if (isset($_GET['sql']))
    if ($_GET['sql'] == 'on')
        print("\n<br>SQL: <pre>" . html_to_txt($cmd) . "</pre>");

pg_query_("\n$cmd", $conn);

# Unfortunately, we need to split out 'params', 'results', and 'details'
# fields so we can create headers and linked data correctly
$selects['per_level']['params'] =
    array_map('get_as_alias',
        array_merge(
            $selects['per_level']['params']
            # (($config['add_params'][$level] and (sizeof($phases['per_level']) < 3)) ?
            #     $config['add_params'][$level][$phases['per_level'][0]] : # blech!
            #     null)
        )
    );
$selects['per_level']['details'] =
    array_map('get_as_alias',
        array_merge(

            # Give good reason to add that far right link!
            (($config['details'][$level][$phase] and
              ! isset($config['by_run'][$level]) and
              ! isset($_GET['no_details']) and
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
        join(",\n", array_unique($selects['per_level']['all'])) .  " " .
        "\n\tFROM tmp ";
if ($groupbys_str)
    $cmd .= "\n\tGROUP BY $groupbys_str ";
if ($orderbys_str)
    $cmd .= "\n\tORDER BY $orderbys_str ";

$sub_query_alias = 'run_atomic';

if (isset($config['by_run'][$level])) {

    $selects['per_script']['params'] =
        get_non_run_key_params($selects['per_script']['params']);

    $cmd = "\nSELECT " .
            join(",\n",
                array_unique(
                    array_merge(
                        $selects['per_level']['params'],
                        get_phase_result_selects($phases['per_level'], 'by_run')
                    )
                )
            ) .
            "\nFROM ($cmd) as $sub_query_alias " .
            "\nGROUP BY $sub_query_alias.". join(",\n$sub_query_alias.",$selects['per_level']['params']);
}

# Do they want to see the SQL query?
if (isset($_GET['sql']))
    if ($_GET['sql'] == 'on')
        print("\n<br>SQL: <pre>" . html_to_txt($cmd) . "</pre>");

$rows = pg_query_("\n$cmd", $conn);

# Create a new temp table for every level
$cmd = "\nDROP TABLE tmp;";
pg_query_("\n$cmd", $conn);

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
    if ($config['details'][$level] and 
        ! isset($_GET['no_details']) and
        (sizeof($phases['per_level']) == 1))
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
        # X: Stop repeating this same ole' three-way AND condition -> make it a single bool!
        if ($config['details'][$level] and 
            ! isset($_GET['no_details']) and
            (sizeof($phases['per_level']) == 1)) {

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

        # translate_data_cell result fields
        for ($i = 0; $i < sizeof($row); $i++) {
            $row[$i] = 
                (! empty($translate_data_cell[$row[$i]])) ? $translate_data_cell[$row[$i]] : $row[$i];
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

            $data_html_table .= "<td align=center bgcolor=$lgray><a href='javascript:popup(\"900\",\"750\",\"" .
                 "[" . isset($config['label'][$level]) . "] " .
                 "$phase_labels[$phase]: Detailed Info\",\"" .
                 strip_quotes($details_html_table) . "\",\"\",\" font-family:Courier,monospace\")' " .
                    " class='lgray_ln'><font size='-2'>" .
                 "[i]</font><a>";
        }
    }
    $data_html_table .= "\n</table>";
    $rows = true;
}

# This block should be useful for a customized report (e.g., summary.php)
if (isset($_GET['just_results'])) {
    $just_results = $data_html_table;
}

# Some basic info about this report's level-of-detail
if ($level_info)
    $report .= $level_info;

# Report description (mostly echoing the user input and filters)
if ($filters_desc_html_table and ! isset($_GET['just_results'])) {
    $report .= "<a name=report></a>";
    $report .= "<br><table width=100%><tr>";
    $report .= "<td valign=top>$filters_desc_html_table";
    $report .= "<td valign=top align='right'><a href='$domain'><img src='$topdir/images/open-mpi-logo.png' border=0 height=75></a>";
    $report .= "</table><br>";
}

# Do not show a blank table
if (! $rows) {

    $report .= "<b><i>No data available for the specified query.</i></b>";

} else {

    # Insert useful information on the left-hand side?
    $report .= "\n\n<$align>" .
          "\n\n<!-- report_start -->\n\n" .
          "<table width='100%' cellpadding=5>" .
          "<tr>" .
          #"<th bgcolor='$lgray' rowspan=2 colspan=2 valign='top' width=0px>[insert link here]" .
          #"<font size='+2'>Level: " . $level . "</font>" .
          "";

    # Aggregates description popup
    if (0) {
    #if ($desc_html_table)
        $report .=
          "<br><a href='javascript:popup(\"500\",\"550\",\"[" . $config['label'][$level] . "] " .
                " Aggregated Fields\",\"" .
                  strip_quotes($desc_html_table) . "<p align=left><i>$aggregate_explanation</i>\",\"\")' " .
                    " class='lgray_ln'><font size='-2'>" .
          "[Aggregated Fields]</font><a>";
    }

    # *broken*
    # Additional info popup
    $details = isset($config['info'][$level]['runs']['name']);
    if ($details) {
        $report .=
          "<br><a href='$details' class='lgray_ln'><font size='-2'>" .
          "[More Detail]</font><a>";
    }

    $report .= "<td bgcolor='$lgray'>";
    $report .= $data_html_table;
    $report .= "\n</table>";
    $report .= "\n\n<!-- report_end -->\n\n";

    # Mark this level as 'shown'
    $config['show'][$level] = null;
}

var_dump_html('config: ', $config);

$report .= "\n<br><br><table border=1><tr><td bgcolor=$lgray><a href='" . $domain .
        $_SERVER['PHP_SELF'] . '?' .
        dump_cgi_params_trimnulls($_GET) .
        "' class='lgray_ln'><font size='-1'>[Link to this query]</a>" .
        "</table>";

pg_close();

# Dump query description, results table, and link to query
function dump_report() {
    global $report;
    return $report;
}

# Dump only the results table
function dump_results_only() {
    global $just_results;
    return $just_results;
}

?>
