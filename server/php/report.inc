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
# Print a report in tabular format
#
#

$topdir = ".";
include_once("$topdir/reporter.inc");
include_once("$topdir/database.inc");
include_once("$topdir/http.inc");
include_once("$topdir/config.inc");
include_once("$topdir/html.inc");
include_once("$topdir/help.inc");

$groupbys_str = "";
$orderbys_str = "";
$selects_str  = "";

$selects                         = array();
$selects['per_script']['params'] = array();
$selects['per_level']['all']     = array();
$selects['per_level']['details'] = array();
$selects['per_level']['params']  = array();
$selects['per_level']['results'] = array();
$selects['per_phase']['all']     = array();

$filters = array();

$sfont = "-0";

$conn = null;

if (! ($conn = pg_connect("host=localhost port=5432 dbname=$dbname user=$user password=$pass")))
    exit_("<br><b><i>Could not connect to database server.</i></b>");

# Dump query description, results table, and link to query
function dump_report() {

    # global declarations
    global $dbname, $user, $pass;
    global $domain;
    global $phases, $phase_labels;
    global $selects, $filters;
    global $results_types;
    global $fields_run_key;
    global $tables;
    global $config, $level;
    global $help;
    global $field_labels, $All;
    global $groupbys_str, $orderbys_str, $selects_str;
    global $cgi_abbrevs;
    global $timestamp, $abs_date_range;
    global $thcolor, $gray, $dgray, $lgray, $llgray, 
           $lllgray, $lred, $lgreen, $lyellow, $white;
    global $sfont;
    global $mpi_logo_path, $mpi_logo_url, $url_basename;

    if (! ($conn = pg_connect("host=localhost port=5432 dbname=$dbname user=$user password=$pass")))
        exit_("<br><b><i>Could not connect to database server.</i></b>");

    debug("\n<br>postgres: " . pg_last_error() . "\n" . pg_result_error());

    # In the query tool, there is just a single '$level' of detail per
    # invocation of the script

    if ($_GET['cgi'] == 'on')
        debug_cgi($_GET, "GET");

    # --- Hack CGI params

    $phases['per_level'] = get_phase_selection($_GET);

    $filters = get_date_filter($_GET[$cgi_abbrevs['mainfield'] . "$timestamp"]);
    $filters = array_merge($filters, get_menu_filters($_GET));
    $filters = array_merge($filters, get_textfield_filters($_GET));
    $filters = array_merge($filters, get_results_filter($_GET));

    $selects['per_script']['params'] = get_selects();

    # Split out selects into params and results
    $selects['per_level']['params'] =
        array_merge(
            (isset($config['by_run'][$level]) ?
                array_diff($selects['per_script']['params'], $fields_run_key) :
                $selects['per_script']['params'])
        );

    var_dump_html("[dump_report " . __LINE__ . "] selects:", $selects);

    # We always need to get the first table by case, before aggregating
    # runs from that result set
    $selects['per_level']['results'] =
        get_phase_result_selects($phases['per_level'], 'by_case');

    $unioned_queries = array();

    # Compose phase-specific queries and union them for each level

    foreach ($phases['per_level'] as $phase) {
        array_push($unioned_queries, create_phase_level_query($phase));
    }

    # Concat the results from the three phases
    $cmd = join("\n UNION ALL \n", $unioned_queries);

    $cmd = "\nSELECT * INTO TEMPORARY TABLE tmp FROM (" . $cmd . ") as u;";

    debug_sql($cmd);

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

    debug_sql($cmd);

    $resource = pg_query_("\n$cmd", $conn);

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

    # This block should be useful for a customized report (e.g., summary.php)
    if (isset($_GET['just_results'])) {
        dump_data_table($headers, $resource);
        return;
    }

    $filters_desc_html_table = filters_description($filters);

    list($width, $height, $type, $attr) = getimagesize($mpi_logo_path);

    # Report description (echo user input)
    if ($filters_desc_html_table and ! isset($_GET['just_results'])) {
        $filters_desc_html_table = "<a name=report></a>" .
                                   "<br><table width=100%><tr>" .
                                   "<td valign=top>$filters_desc_html_table" .
                                   "<td valign=top align='right'><a href='$url_basename'> " .
                                   "<img src='$mpi_logo_url' border=0 " .
                                   "height=" . $height * 0.6 . " " .
                                   "width=" . $width * 0.6 . " " .
                                   "alt='$url_basename'></a>" .
                                   "</table><br>";
    } else
        $filters_desc_html_table = null;

    if (! isset($_GET['no_description']))
        print $filters_desc_html_table;

    dump_data_table($headers, $resource);

    print info_pointers();
    print help(phases_help($phases));

    print "\n<br><hr><br>";

    pg_close();
}

# void function to print out html data table
function dump_data_table($headers, $resource) {

    # global declarations
    global $phases, $phase_labels;
    global $selects;
    global $field_labels;
    global $results_types;
    global $translate_data_cell;
    global $thcolor, $gray, $dgray, $lgray, $llgray, 
           $lllgray, $lred, $lgreen, $lyellow, $white;

    # Do not print an empty table
    if (pg_num_rows($resource) < 1) {
        if (isset($_GET['blank_if_null']))
            exit;

        print "<b><i>No data available for the specified query.</i></b>";
        return;
    }
    
   $max_rows = 5000;

    # Be nice to the server, show only the first max_rows
    if (pg_num_rows($resource) > $max_rows) {
        print "<i>Displaying first $max_rows rows, please trim your query.</i>";
    }
    
    # Insert useful information on the left-hand side?
    print "\n\n<div align=center>" .
          "\n\n<!-- report_start -->\n\n" .
          "<table width='100%' cellpadding=5>" .
          "<tr>" .
          #"<th bgcolor='$lgray' rowspan=2 colspan=2 valign='top' width=0px>[insert link here]" .
          "" .
          "\n<td bgcolor='$lgray'>" .
          "\n\n<div align=center><table border=1 width='100%'>";

    # Display headers
    $num_cols = count($headers['params']) +         # params headers
               (count($phases['per_level']) * 2) +  # results headers
                1;                                  # [i]

    if (isset($_GET['table_title']))
        print "\n<tr><th bgcolor='$thcolor' colspan=$num_cols>" .
              "\n<i><b><br>" .  $_GET['table_title'] . "<br><br></b></i>";

    print 
        "<tr>" . sprintf_("\n<th bgcolor='$thcolor' rowspan=2>%s", $headers['params']);

    $i = 1;
    foreach ($phases['per_level'] as $ph) {
        print 
            sprintf("\n<th bgcolor='$thcolor' colspan=2>%s", 
                $phase_labels[$ph] . help("<sup>[" . $i++ . "]</sup>"));
    }
    if ($selects['per_level']['details'])
        print sprintf("\n<th bgcolor='$thcolor' rowspan=2>%s", "[i]");

    print "\n<tr>";

    # Yucky hard-coding, but will it ever be anything but pass/fail here?
    foreach ($phases['per_level'] as $p) {
        print sprintf("\n<th bgcolor='$thcolor'>%s", 'Pass');
        print sprintf("\n<th bgcolor='$thcolor'>%s", 'Fail');
    }

    if (isset($_GET['details_inline'])) {
        $details_inline = true;
        $cellcolor      = $llgray;
        $border         = 0;

        print "\n</table>" .
              "\n</table>";
    }
    else {
        $details_inline = false;
        $cellcolor      = $white;
        $border         = 1;
    }

    $i = 0;
    # Display data rows
    while ($row = pg_fetch_row($resource)) {

        if ($i++ > $max_rows)
            break;

        $details_html_table = "";

        # Make the row clickable if there's clickable info for this query
        if ($selects['per_level']['details']) {

            $len = sizeof($selects['per_level']['details']);
            $linked_field_cols = array_splice($row, sizeof($row) - $len, $len);

            $details_html_table = "\n\n" .
                "<table border=$border width=100%><tr><th bgcolor=$thcolor>Details" .
                "<tr><td bgcolor=$lllgray width=100%>";

            for ($i = 0; $i < $len; $i++) {
                $field = $selects['per_level']['details'][$i];
                $field = $field_labels[$field] ? $field_labels[$field] : $field;
                $details_html_table .= "\n<br><b>" .
                        $field . "</b>:<br>" .
                        "<tt>" . txt_to_html($linked_field_cols[$i]) . "</tt><br>";
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

        if ($details_inline)
            print "\n<br><table border=1 width=100%>";

        print "\n<tr>" . sprintf_("\n<td bgcolor=$cellcolor>%s", $row);

        for ($i = 0; $i < sizeof($result_cols); $i += 2) {
            print "\n<td align='right' bgcolor='" .
                    (($result_cols[$i] > 0) ? $lgreen : $lgray) . "'>$result_cols[$i]";
            print "\n<td align='right' bgcolor='" .
                    (($result_cols[$i + 1] > 0) ? $lred : $lgray) . "'>" . $result_cols[$i + 1];
        }

        if ($details_html_table) {

            if (! $details_inline)
                print "\n<td align=center bgcolor=$lgray>" .
                      "\n<a href='javascript:popup(\"900\",\"750\",\"" .
                      "$phase_labels[$phase]: Detailed Info\",\"" .
                      htmlentities(strip_quotes($details_html_table)) . "\",\"\",\" font-family:Courier,monospace\")' " .
                         " class='lgray_ln'><font size='$sfont'>" .
                      "[i]</font><a>";
            else
                print "\n<td align=center bgcolor=$lgray>" .
                      "\n<font size='$sfont'>[i]</font>" .
                      "\n<tr><td align=center colspan=$num_cols>" . strip_quotes($details_html_table);
        }
        if ($details_inline)
            print "\n</table>";
    }

    print "\n</table>";
    print "\n</table>";
    print "\n\n<!-- report_end -->\n\n";
}

$abs_date_range = "";

# Return an HTML table describing the SQL filters used in $filters
function filters_description($filters) {

    global $config, $level;
    global $thcolor, $gray, $dgray, $lgray, $llgray, 
           $lllgray, $lred, $lgreen, $lyellow, $white;
    global $help;
    global $sfont;
    global $abs_date_range;
    global $conn;

    $now = array_shift(pg_query_simple(
                "SELECT substring(now() from 0 for 20)", $conn));

    # Create a plain-english description of the filters
    if (sizeof($filters) > 0) {
        $filters_desc_html_table = "<table border=1 width=60%><tr>" .
            "<th bgcolor=$lgray colspan=2>Query Description" .
            "<tr><td bgcolor=$lgray>Current Time (GMT) <td bgcolor=$llgray><i>$now";

        foreach ($filters as $filter) {
            $tuple = sql_to_en($filter);

            if (! $tuple[0])
                continue;
            
            # blech - crude way of snarfing absolute date range
            if (preg_match("/date/i", $tuple[0]))
                $abs_date_range = $tuple[1];

            $filters_desc_html_table .=
                sprintf("\n<tr><td bgcolor=$lgray>%s<td bgcolor=$llgray>%s",
                    ascii_sp_to_html_sp($tuple[0]), 
                    ascii_sp_to_html_sp($tuple[1]));
        }
        $count = (isset($config['by_run'][$level]) ? "By test run" : "By test case");
        $filters_desc_html_table .= 
            # The 'Count' setting is not used at the $filters level
            "<tr><td bgcolor=$lgray>Count <td bgcolor=$llgray>" .
            $count . " *" .
                help("<tr><td colspan=2 bgcolor=$lllgray><i><font size='$sfont'>*" .
                    $help[$count] . "</font></i>") .
            "</table>" .
            "";
    }
    else
        $filters_desc_html_table = null;

    return $filters_desc_html_table;
}

# Return an array of all that's to be included in SELECT
function get_selects() {
    
    global $phases;
    global $config, $level;
    global $cgi_abbrevs;
    global $agg_timestamp_selects;

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
    return array_unique($cgi_selects);
}

# Create a subquery at the phase level for combining into a single table
function create_phase_level_query($phase) {

    global $filters;
    global $selects;
    global $results;
    global $config, $level;
    global $fields_run_key;
    global $phases;
    global $once_db_table;
    global $groupbys_str, $orderbys_str, $selects_str;

    # db table names are identical to phase names used in this script
    $db_table = $phase;

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
    $cmd .= ((sizeof($filters) > 0) ?  "\nWHERE " . join("\n AND \n", $filters) : "") .
            " ";

    return $cmd;
}

# Use implicit selection, as well as process of elimination to determine which
# phases should be shown
function get_phase_selection($params) {

    global $All;
    global $phases;
    global $cgi_abbrevs;

    $phase_selection = array();
    $selected        = array();
    $selected        = $params[$cgi_abbrevs['mainfield'] . 'phase'];
    $all_phases      = $phases['per_script'];
    $which_phases    = which_phase_specific_filter($params);

    # Select phase specific filter, no phase menu selection
    #     which phases
    # Select phase specific filter, phase menu selection
    #     selected
    # Select general filter, phase menu selection
    #     selected
    # No filter, phase menu selection
    #     selected
    # Select general filter, no phase menu selection
    #     all
    # No filter, no phase menu selection
    #     all

    if (sizeof($which_phases) < sizeof($all_phases) and $which_phases != null)
        $phase_selection = $which_phases;
    elseif ($which_phases == null and $selected != $All)
        $phase_selection = array($selected);
    elseif (sizeof($which_phases) == sizeof($all_phases) and $selected != $All)
        $phase_selection = array($selected);
    # elseif (sizeof($which_phases) == sizeof($all_phases) and $selected == $All)
    #     $phase_selection = $all_phases;
    # elseif ($which_phases == null and $selected == $All)
    #     $phase_selection = $all_phases;
    else
        $phase_selection = $all_phases;

    return $phase_selection;
}

# Show links to point user to more info ...
function info_pointers() {

    global $thcolor, $gray, $dgray, $lgray, $llgray,
           $lllgray, $lred, $lgreen, $lyellow, $white;
    global $domain, $url_basename, $url_filename;
    global $sfont;
    global $cgi_abbrevs;
    global $abs_date_range, $timestamp, $dash;

    $tstamp = $cgi_abbrevs['mainfield'] . $timestamp;

    $query_string1 = dump_query_string($_GET) . 
                     '&no_bookmarks';
    $query_string2 = preg_replace(
                        '/(&' . $tstamp . '=)([^&]+)/',
                        '${1}'.$abs_date_range, $query_string1 . 
                        '&no_bookmarks');

    if (! isset($_GET['no_bookmarks'])) {

        $links = "\n<div align=left><br>" .
                 "\n<table border=1 width=20%><tr><th bgcolor='$lgray' colspan=2>Bookmarks";

        # Can't be a relative link to an absolute date range report
        $links .= "\n<tr>" .
                  "\n<td bgcolor=$lgray>Relative date range<td align=center bgcolor=$llgray><a href='" . $domain .
                      $_SERVER['PHP_SELF'] . '?' .
                      $query_string1 .
                  "' class='black_ln'><font size='$sfont'>[Link]</font></a>";

        $links .= "\n<tr>" .
                  "\n<td bgcolor=$lgray>Absolute date range<td align=center bgcolor=$llgray><a href='" . $domain .
                      $_SERVER['PHP_SELF'] . '?' .
                      $query_string2 .
                  "' class='black_ln'><font size='$sfont'>[Link]</font></a>";

        $links .= "\n</table>" .
                  "\n</div>";
    }

    if (isset($_GET['info_links'])) {

        $links .= "\n<div align=left><br>" .
                 "\n<table border=1 width=20%><tr><th bgcolor='$lgray' colspan=2>More Info";

        $links .= "\n<tr><td bgcolor=$lgray>Summary Report<td align=center bgcolor=$llgray><a href='" . 
                  perfect_url("$url_basename/summary.php") . "' class='black_ln'><font size='$sfont'>[Link]</font></a>" .
                  "";

        $links .= "\n<tr><td bgcolor=$lgray>Custom Reports<td align=center bgcolor=$llgray><a href='" . 
                  perfect_url("$url_basename/index.php"). "' class='black_ln'><font size='$sfont'>[Link]</font></a>" .
                  "";

        $links .= "\n</table>" .
                  "\n</div>";

    }
    return $links;
}

# Return HTML string displaying explanation of phases
function phases_help($phases) {

    global $help, $sfont;

    $i = 1;
    $phases_help = "\n<div align=left><br>" .
                   "\n<table border=0 width=100%><tr><td>" .
                   "\n<i><font size='$sfont'>" . 
                   "\n" . $help['Phase'] . "</font>";

    foreach ($phases['per_level'] as $ph) {
        $phases_help .= 
            "\n<br><b><font size='$sfont'><sup>[" . $i++ . "]</sup></b> " . $help[$ph] . "</font>";
    }
    $phases_help .= "\n</i></table>" .
                    "\n</div>";

    return $phases_help;
}

?>
