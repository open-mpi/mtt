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
include_once("$topdir/html.inc");

# Dump query description, results table, and link to query
function dump_report() {

    global $thcolor, $gray, $dgray, $lgray, $llgray, $lllgray, $white;

    if ($_GET['cgi'] == 'on')
        debug_cgi($_GET, "GET");

    # Process input params
    $phases       = process_phase_field($_GET);
    $datefields   = process_date_field($_GET);
    $inputfields  = process_input_fields($_GET);
    $resultfields = get_result_cases($phases, $_GET);

    $query = array_merge_recursive(
        $datefields,
        $inputfields,
        $resultfields
    );
    $query['phases'] = $phases;

    $query['select'] = order_columns($query['select']);

    # Compose query
    $cmd = compose_sql($query);

    $resource = do_pg_query("\n$cmd");

    # Generate headers
    $headers['params']  = array_keys($query['select']);
    $headers['details'] = array_keys($query['select_more']);
    $headers['results'] = array_keys($query['aggregates']);
    $headers['phases']  = $phases;

    $num_rows = pg_num_rows($resource);

    $basic_info = basic_info($datefields, $phases, $num_rows);
    $permalinks = permalinks($datefields);

    # Print general info/links up top
    print "<table width='100%'><tr>" .
          "<td>$basic_info" .
          "<td align='right'>$permalinks" .
          "</table><br>";
    
    # Print either a summary or detail report,
    # depending on whether a 'select_more' parameter is set
    $do_detailed = $headers['details'] ? true : false;

    if ($do_detailed)
        detail_table($headers, $resource);
    else
        summary_table($headers, $resource);

    print "\n<br><hr><br>";

    pg_close();
}

# Void function to print out a summary style HTML data table
function summary_table($headers, $resource) {

    global $thcolor, $gray, $dgray, $lgray, $llgray,
           $lllgray, $white;

    # Do not print an empty table
    if (pg_num_rows($resource) < 1) {
        print "<b><i>No data available for the specified query.</i></b>";
        return;
    }

    $max_rows = 5000;

    # Be nice to the server, show only the first max_rows
    if (pg_num_rows($resource) > $max_rows) {
        print "<i>Displaying first $max_rows rows, please trim your query.</i>";
    }

    # Insert useful information on the left-hand side?
    print "\n<div align=center>" .

          "\n\n<!-- report_start -->\n\n" .

          "\n<table width='100%' cellpadding=5>" .
          "\n<tr>" .
          "\n<td bgcolor='$lgray'>" .
          "\n<div align=center>" .
          "\n<table border=1 width='100%'>";

    # Display headers
    $format = "\n<th bgcolor='$thcolor' rowspan=2>%s";

    print "<tr>" . sprintf($format, '#');
    foreach ($headers['params'] as $header)
        printf($format, label($header));

    $num_result_types = array(
        "mpi_install" => 2,
        "test_build" => 2,
        "test_run" => 4,
    );

    # Setup sequence of result colors
    $phases = $headers['phases'];
    $result_colors = result_colors($phases);

    # Create links for drilled-down queries
    $labels = drilldown_basic($headers['phases']);

    # Print result headers
    $total_results_cols = 0;
    foreach ($headers['phases'] as $phase) {
        printf("\n<th bgcolor='$thcolor' " .
                      "colspan='$num_result_types[$phase]'>%s",
                      $labels[$phase]);
        if ($num_result_types[$phase])
            $total_results_cols += $num_result_types[$phase];
    }

    print "\n<tr>";

    foreach ($headers['results'] as $result) {
        printf("\n<th bgcolor='$thcolor'>%s", $labels[$result]);
    }

    $r = 1;

    # Print data rows
    while ($row = pg_fetch_row($resource)) {

        if ($r > $max_rows)
            break;

        # Results are always in the far right cols
        $results = array_splice($row, sizeof($row) - $total_results_cols);

        # printf formats
        $format  = "\n<td bgcolor='%s' align='right'>%s";
        $formatg = "\n<td bgcolor='$lgray' align='right'>%s";
        $formatw = "\n<td bgcolor='$white'>%s";

        print "\n<tr>" . sprintf($formatg, $r++);
        foreach ($row as $cell)
            printf($formatw, $cell);

        $i = 0;
        $j = 0;

        foreach ($headers['phases'] as $phase) {
            
            # Each phase has differing result types
            $_results =
                array_splice($results, 0, $num_result_types[$phase]);

            # Link result counts to filtered drill-down reports
            $ret = drilldown_filters($headers,
                                  $row,
                                  $_results,
                                  $phase);
            list($pass,
                 $fail,
                 $skip,
                 $time) = $ret['links'];

            list($pass_count,
                 $fail_count,
                 $skip_count,
                 $time_count) = $ret['counts'];

            printf($format,
                    (($pass_count > 0) ? $result_colors[$j] : $lgray), $pass);
            $j++;
            printf($format,
                    (($fail_count > 0) ? $result_colors[$j] : $lgray), $fail);
            $j++;
            if (! is_null($skip)) {
                printf($format,
                        (($skip_count > 0) ? $result_colors[$j] : $lgray), $skip);
                $j++;
            }
            if (! is_null($time)) {
                printf($format,
                        (($time_count > 0) ? $result_colors[$j] : $lgray), $time);
                $j++;
            }

            # Tally totals for all result counts
            foreach ($ret['counts'] as $count) {
                $totals[$i++] += $count;
            }
        }
    }

    $i = 0;

    # Print results totals in last row
    print "\n<tfoot><tr>" .
          "\n<td align='left' " .
                "bgcolor='$lgray' " .
                "colspan='" . (sizeof($headers['params']) + 1) . "'>" .
          "\n<b>Totals</b>";

    foreach ($totals as $total) {
        print "\n<td align='right' " .
                     "bgcolor='" . (($total > 0) ? $result_colors[$i] : $lgray) . "'" .
                 "><b>$total</b>";
        $i++;
    }
    print "\n</tfoot>" .
          "\n</table>" .
          "\n</table>" .
          "\n\n<!-- report_end -->\n\n";
}

# Return a sequence of result cell bgcolors
function result_colors($phases) {

    global $lred, $lgreen, $lyellow;

    $_phases = array_flip($phases);

    if (isset($_phases['mpi_install'])) {
        $colors [] = $lgreen;
        $colors [] = $lred;
    }
    if (isset($_phases['test_build'])) {
        $colors [] = $lgreen;
        $colors [] = $lred;
    }
    if (isset($_phases['test_run'])) {
        $colors [] = $lgreen;
        $colors [] = $lred;
        $colors [] = $lyellow;
        $colors [] = $lyellow;
    }
    return $colors;
}

# Create links that drill down by phase, result, and a set of general params
function drilldown_filters($headers, $params, $results, $phase) {

    $qstring_arr = $_GET;
    $test_results = array(
        'pass',
        'fail',
        'skip',
        'timed',
    );

    $self = 'http://' . $_SERVER['SERVER_NAME'] . $_SERVER['SCRIPT_NAME'];
    foreach (detail_columns($phase) as $column)
        $qstring_arr["more_$column"] = null;

    $format = "<a href='$self?%s' class='black_ln' target='_self'>%s</a>";

    $j = 0;
    foreach ($results as $count) {

        $i = 0;
        # Loop over header names
        foreach ($headers['params'] as $param) {
            $qstring_arr["text_$param"] = $params[$i++];
        }
        $qstring_arr['test_result'] = $test_results[$j];
        $qstring_arr['phase'] = $phase;

        $ret['links'][] = sprintf($format, arr2qstring($qstring_arr), $count);
        $ret['counts'][] = $count;
        $j++;
    }

    return $ret;
}

# Create links that drill down by phase and/or result
function drilldown_basic($phases) {

    $self = 'http://' . $_SERVER['SERVER_NAME'] . $_SERVER['REQUEST_URI'];

    $test_results = array(
        "fail",
        "pass",
        "skip",
        "timed",
    );

    # Some headers that link to drilled down reports
    foreach ($phases as $phase) {
        
        # Add phase-specific columns to the report
        $appendage = "";
        foreach (detail_columns($phase) as $column)
            $appendage .= "&more_$column";

        $drilldown = esc_percent("<a href='$self$appendage") . "%s' " .
                     "class='black_ln' " .
                     "target='_self'>%s" .
                     "</a>";
        $links[$phase] = sprintf($drilldown, "&phase=$phase", label($phase));
        foreach ($test_results as $result) {
            $links[result_str($phase, $result)] =
                sprintf($drilldown, "&phase=$phase&test_result=$result", label($result));
        }
    }

    return $links;
}

# Generate the shorthand for the given phase-result code (see get_result_cases)
function result_str($phase, $result) {
    $abbrevs = array(
        'mpi_install' => 'i',
        'test_build' => 'b',
        'test_run' => 'r',
    );
    return '_' . $abbrevs[$phase] . substr($result, 0, 1);
}

# Used to print literal '%' symbols in a printf
function esc_percent($str) {
    return preg_replace('/%/', '%%', $str);
}

# Void function to print out a summary style HTML data table
function detail_table($headers, $resource) {

    global $thcolor, $gray, $dgray, $lgray, $llgray,
           $lllgray, $lred, $lgreen, $lyellow, $white;

    # Do not print an empty table
    if (pg_num_rows($resource) < 1) {
        print "<b><i>No data available for the specified query.</i></b>";
        return;
    }

    $max_rows = 5000;

    # Be nice to the server, show only the first max_rows
    if (pg_num_rows($resource) > $max_rows) {
        print "<i>Displaying first $max_rows rows, please trim your query.</i>";
    }

    $num_result_types = array(
        "mpi_install" => 2,
        "test_build" => 2,
        "test_run" => 4,
    );

    # Print result headers
    $num_cols['results'] = 0;
    foreach ($headers['phases'] as $phase) {
        if ($num_result_types[$phase])
            $num_cols['results'] += $num_result_types[$phase];
    }
    $num_cols['details'] = sizeof($headers['details']);
    $num_cols['params'] = sizeof($headers['params']);

    print "\n<tr>";

    foreach ($headers['results'] as $result) {
        printf("\n<th bgcolor='$thcolor'>%s", $labels[$result]);
    }

    $r = 0;

    # Remove duplicated headers
    $headers = array_unique(
        array_merge(
            $headers['params'],
            $headers['details']
        )
    );

    # Print data rows
    while ($row = pg_fetch_row($resource)) {

        if ($r++ > $max_rows)
            break;

        # Results are always in the far right cols
        $results = array_splice($row, $num_cols['params']);

        # Details are always in the far far right cols
        $details = array_splice($results, $num_cols['results']);

        $pass = $results[0];
        $fail = $results[1];
        $skip = $results[2];
        $time = $results[3];

        if ($pass)
            $bgcolor = (($pass > 0) ? $lgreen  : "");
        elseif ($fail)
            $bgcolor = (($fail > 0) ? $lred    : "");
        elseif ($skip)
            $bgcolor = (($skip > 0) ? $lyellow : "");
        elseif ($time)
            $bgcolor = (($time > 0) ? $lyellow : "");

        print "<table border='1' width='100%'>" .
              "<tr><td bgcolor='$bgcolor'>";

        $td = "<td bgcolor='$lgray' width='10%' valign='top'>";
        $tdl = "<td bgcolor='$white'>";

        $values =
            array_merge(
                $row,
                $details
            );

        $i = 0;
        print "<table border='1' width='100%'>";
        foreach ($headers as $header) {
            print (($i % 1 == 0) ? "\n<tr>" : "") .
                  "\n$td <b>" . label($header) . "</b> $tdl " .
                  "\n<pre>" . wordwrap($values[$i], 100) . "</pre>";
            $i++;
        }
        print "</table>";
        print "</table><br>";
    }

    print "\n</table>" .
          "\n</table>" .
          "\n\n<!-- report_end -->\n\n";
}

# Compose an SQL SELECT statement
function compose_sql($query) {

    $selects = array();
    $nl = "\n\t";

    # Determine table (or views) to SELECT from
    if (sizeof($query['phases']) > 1)
        $tables = array('all_view');
    else
        $tables = suffix_list($query['phases'], '_view');

    foreach (array_keys($query['aggregates']) as $aggregate) {
        $aggregates[] = $query['aggregates'][$aggregate];
    }

    # Compile lists for SELECT, GROUP BY,
    # and ORDER BY clauses
    $selects = array_unique(
        array_merge(
            $query['select'],
            $aggregates,
            $query['select_more']
        )
    );

    $groupbys = array_unique(
        array_merge(
            array_keys($query['select']),
            array_keys($query['select_more'])
        )
    );

    $orderbys =  array_unique(
        array_merge(
            array_keys($query['select'])
        )
    );

    # Piece together all the clauses
    $cmd  = "\n SELECT ";
    $cmd .=     "$nl" . join(",$nl", $selects);

    $cmd .= "\n FROM ";
    $cmd .=     "$nl" . join(",$nl", $tables);

    if ($query['where']) {
        $cmd .= "\n WHERE ";
        $cmd .=     "$nl" . join("$nl AND $nl", $query['where']);
    }

    if (array_keys($query['select'])) {
        $cmd .= "\n GROUP BY ";
        $cmd .=     "$nl" . join(",$nl ", $groupbys);

        $cmd .= "\n ORDER BY ";
        $cmd .=     "$nl" . join(",$nl ", $orderbys);
    }

    $cmd .= ";";

    return $cmd;
}

# Return 
# 1. An array of SQL COUNT(CASE ...) clauses
#    which will be used to tally the result numbers
# 2. A result filter (optional)
# (Reference: postgresql.org/docs/7.3/static/functions-conditional.html)
function get_result_cases($phases, $params) {

    $_phases = array_flip($phases);

    $test_result = $params['test_result'];

    if (preg_match('/pass|true|1/i', $test_result))
        $filter = 'pass';
    elseif (preg_match('/fail|false|0/i', $test_result))
        $filter = 'fail';
    elseif (preg_match('/skip|2/i', $test_result))
        $filter = 'skip';
    elseif (preg_match('/time|3/i', $test_result))
        $filter = 'timed';

    $format = "COUNT(CASE WHEN %s THEN '%s' END) as %s";

    # MPI Installs
    if (isset($_phases['mpi_install'])) {
        $str = '_ip';
        $when['pass'] = "pass = '$str'";
        $results['aggregates'][$str] =
            sprintf($format, $when['pass'], $str, $str);

        $str = '_if';
        $when['fail'] = "fail = '$str'";
        $results['aggregates'][$str] =
            sprintf($format, $when['fail'], $str, $str);
    }

    # Test Builds
    if (isset($_phases['test_build'])) {
        $str = '_bp';
        $when['pass'] = "pass = '$str'";
        $results['aggregates'][$str] =
            sprintf($format, $when['pass'], $str, $str);

        $str = '_bf';
        $when['fail'] = "fail = '$str'";
        $results['aggregates'][$str] =
            sprintf($format, $when['fail'], $str, $str);
    }

    # Test Runs
    if (isset($_phases['test_run'])) {
        $str = '_rp';
        $when['pass'] = "pass = '$str'";
        $results['aggregates'][$str] =
            sprintf($format, $when['pass'], $str, $str);

        $str = '_rf';
        $when['fail'] = "fail = '$str'";
        $results['aggregates'][$str] =
            sprintf($format, $when['fail'], $str, $str);

        $str = '_rs';
        $when['skip'] = "skipped = '$str'";
        $results['aggregates'][$str] =
            sprintf($format, $when['skip'], $str, $str);

        $str = '_rt';
        $when['timed'] = "timed_out = '$str'";
        $results['aggregates'][$str] =
            sprintf($format, $when['timed'], $str, $str);
    }

    $results['where'] = $when[$filter];

    return $results;
}

# Show links to point user to more info ...
function permalinks($datefields) {

    $domain    = $_SERVER['SERVER_NAME'];
    $uri       = $_SERVER['REQUEST_URI'];
    $script    = $_SERVER['SCRIPT_NAME'];
    $datefield = $datefields["absolute"] . ';' . $datefields["rollup"];

    # Create links to report using relative and absolute date ranges
    $rel_link = "http://$domain$uri&no_bookmarks";
    $abs_link = rewrite_url($rel_link, "text_start_timestamp", $datefield);

    # Can't be a relative link to an absolute date range report
    if (! isset($_GET['no_bookmarks'])) {
        $href = "\n<tr>" .
                  "\n<td><b>%s</b>:<td>" .
                  "\n<a href='%s'".
                  "' class='black_ln'>Permalink</a>";

        $links = "\n<table>" .
                  sprintf($href, "Relative date range", $rel_link) .
                  sprintf($href, "Absolute date range", $abs_link) .
                  "\n</table>";
    }
    return $links;
}

# Print current time, date range, phases, and
# result filter for the report
function basic_info($datefields, $phases, $num_rows) {

    $ret = "<table>" .
          "<tr><td><b>Current time (GMT)</b>:<td>" . $datefields["current"] . 
          "<tr><td><b>Date range (GMT)</b>: <td>" . $datefields["absolute"] .
          "<tr><td><b>Phase(s)</b>:<td>" . join(", ", $phases);

    if ($_GET["test_result"])
        $ret .= "<tr><td><b>Result</b>:<td>" . $_GET["test_result"] . " only";

    $ret .= "<tr><td><b>Number of rows</b>:<td>" . $num_rows .
            "</table>";

    return $ret;
}


# 1. Generate WHERE clause pieces from user-entered textfields
# 2. Generate SELECT items from user-entered show/hide menus
function process_input_fields($params) {

    $query['where'] = array();
    $query['select'] = array();

    # These fields will not be string searchable
    $special_fields = array(
        "timestamp",
        "duration",
        "phase",
    );

    # Some special enumerated types
    $enums = array(
        'bitness' => array(
            1 => 32,
            2 => 64,
            3 => '32/64',
        ),
        'endian' => array(
            1 => 'little',
            2 => 'big',
        ),
        'vpath_mode' => array(
            1 => 'no vpath',
            2 => 'relative',
            3 => 'absolute',
        ),
    );

    foreach (array_keys($params) as $k) {

        if (preg_match("/" . join("|", $special_fields) . "/i", $k))
            continue;

        # If it's a textfield, tokenize it and add each
        # item to WHERE clause
        elseif (preg_match("/^text_/i", $k)) {
            $column = strip_prefix($k);

            $clauses = array();

            # Compose WHERE clause(s) on special enumerated types
            if (preg_match("/" . join('|', array_keys($enums)) . "/i", $column)) {
                $filters = array_flip($enums[$column]);
                foreach (tokenize($params[$k]) as $t) {
                    if (preg_match("/unknown/i", $t))
                        continue;
                    $clauses[] = "$column = $filters[$t]";
                }
                continue;
            }

            # No WHERE clause, if field is blank or "all"
            if (preg_match("/^\s*all\s*$|^\s*$/i", $params[$k]))
                continue;

            foreach (tokenize($params[$k]) as $t) {
                $clauses[] = "$column ~* '$t'";
            }
            $query['where'][] = "(" . join(" OR ", $clauses) . ")";
        }
        # If "show" is selected, add it to SELECT clause
        elseif (preg_match("/^show_/i", $k)) {
            $column = strip_prefix($k);

            if ($params[$k] == 'on')
                $query['select'][$column] = $column;
        }
        # If it's a "more" param, add it to the ''end'' of the SELECT clause
        elseif (preg_match("/^more_/i", $k)) {
            $column = strip_prefix($k);

            if (isset($params[$k]))
                $query['select_more'][$column] = $column;
        }
    }

    # Compose SELECT clause(s) on special enumerated types
    foreach (array_keys($enums) as $enum) {
        if (isset($query['select'][$enum])) {
            $query['select'][$enum] =
                "(CASE ";
            foreach (array_keys($enums[$enum]) as $k)
                $query['select'][$enum] .=
                    "WHEN $enum = $k THEN '" . $enums[$enum][$k] . "' ";
            $query['select'][$enum] .=
                "ELSE 'unknown' END) as $enum";
        }
    }

    return $query;
}

# Arguments:
# 1. English filter (e.g., 'yesterday' or
#    'past x days')
# 2. Optional timestamp string description (e.g.,
#    "by second", "by hour", ...)
#
# Return the SQL date filter (and string function)
function process_date_field($params) {

    $date = array();
    $tokens = array();

    $sep = '[\s\+]';
    $c = '/\s*;\s*/';

    # Remove the GMT offset from fetched string
    $format = "replace(date_trunc('second', %s), '+00', '')";

    $now = select_scalar("SELECT " . sprintf($format, "now()"));
    $date['current'] = $now;

    $timestamp_name = "start_timestamp";
    $timestamp_param = $params["text_$timestamp_name"];

    if (preg_match($c, $timestamp_param, $m))
        $tokens = tokenize($timestamp_param);
    else
        $tokens[] = $timestamp_param;

    foreach ($tokens as $token) {

        # Do date filtering
        if (! preg_match("/by /i", $token)) {

            # Yesterday
            if (preg_match("/yesterday/i", $token, $m)) {
                $operand = "timestamp without time zone 'yesterday'";
                $where = "$timestamp_name > $operand";
                $absolute =
                    select_scalar("SELECT " . sprintf($format, $operand)) . " - $now";
            }
            # Today
            elseif (preg_match("/today/i", $token, $m)) {
                $operand = "timestamp without time zone 'today'";
                $where = "$timestamp_name > $operand";
                $absolute =
                    select_scalar("SELECT " . sprintf($format, $operand)) . " - $now";
            }
            # Past x increments
            elseif (preg_match(
                        "/past$sep*" .
                        "(\w+)$sep*" .
                        "(\w+)/i", $token, $m)) {

                $operand = "now() - interval '" . strtonumeral($m[1]) . " $m[2]'";
                $where = "$timestamp_name > $operand";
                $absolute =
                    select_scalar("SELECT " . sprintf($format, $operand)) . " - $now";
            }
            # Range (e.g., date1 - date2)
            elseif (preg_match("/(?:between)?" .
                                "(.*)" .
                                "(?:through|thru|and| - )" .
                                "(.*)/i", $token, $m)) {
                $where =
                    "$timestamp_name > '$m[1]'" . " AND " .
                    "$timestamp_name < '$m[2]'";
                $absolute = "$m[1] - $m[2]";
            }
        }
        # Do date aggregation
        else {

            $format2 = "\n substring($timestamp_name from 0 for %d) || ':00 - ' || " .
                       "\n substring($timestamp_name + interval '1 %s' from 0 for %d)  || ':00' " .
                       "\n   as $timestamp_name";
            $format3 = "\n substring($timestamp_name from 0 for %d) || ' - ' || " .
                       "\n substring($timestamp_name + interval '1 %s' from 0 for %d) " .
                       "\n   as $timestamp_name";

            if (preg_match("/by(?:-| *)sec(?:onds?)?/i", $token)) {
                $clause = $timestamp_name;

            } elseif (preg_match("/by(?:-| *)min(?:utes?)?/i", $token)) {
                $clause = sprintf($format3, 17, "minute", 17);

            } elseif (preg_match("/by(?:-| *)hours?/i", $token)) {
                $clause = sprintf($format2, 14, "hour", 14);

            } elseif (preg_match("/by(?:-| *)days?/i", $token)) {
                $clause = sprintf($format3, 11, "day", 11);

            } elseif (preg_match("/by(?:-| *)mon(?:ths?)?/i", $token)) {
                $clause = sprintf($format3, 8, "month", 8);

            } elseif (preg_match("/by(?:-| *)years?/i", $token)) {
                $clause = sprintf($format3, 5, "year", 5);
            }
            $date["rollup"] = $token;
        }
    }

    # PROTECT AGAINST AN EMPTY DATE RANGE.
    # OUGHT TO PRINT A JAVASCRIPT ALERT AS WELL
    if (! $where) {
        $operand = "now() - interval '24 hours'";
        $where = "$timestamp_name > $operand";
        $absolute =
            select_scalar("SELECT " . sprintf($format, $operand)) . " - $now";
        $date['select'][$timestamp_name] = $timestamp_name;
    }

    $date['select'][$timestamp_name] = $clause;
    $date['where'] = $where;
    $date['absolute'] = $absolute;

    return $date;
}

# Remove the prefix part of the parameter,
# which will leave only a database column name
function strip_prefix($str) {
    return preg_replace('/^more_|^show_|^text_/', '', $str);
}

# '_' to ' '
function us2sp($str) {
    return preg_replace('/_/', ' ', $str);
}

# ' ' to '_'
function sp2us($str) {
    return preg_replace('/\s+/', '_', $str);
}

# Function to rewrite URL, with new $value set for $field
function rewrite_url($url, $field, $value) {
    $t_url = preg_replace("/$field=[^\&]+/", "$field=$value", $url);
    return $t_url;
}

function suffix_list($arr, $sfx) {
    $tmp = array();
    foreach ($arr as $a)
        $tmp[] = $a . $sfx;
    return $tmp;
}

# Loop through column aliases, and return
# a left-to-right ordering of SELECT clauses
function order_columns($columns) {

    $layout = array(
        # results
        'start_timestamp'   => 1,
        # submit
        'http_username'     => 1,
        'local_username'    => 1,
        'hostname'          => 1,
        # mpi_install
        'platform_hardware' => 1,
        'os_name'           => 1,
        'mpi_name'          => 1,
        'mpi_version'       => 1,
        'bitness'           => 1,
        'endian'            => 1,
        'compiler_name'     => 1,
        'compiler_version'  => 1,
        # phase-specific
        'suite_name'        => 1,
        'test_name'         => 1,
        'np'                => 1,
    );

    foreach (array_keys($layout) as $column)
        if (isset($columns[$column]))
            $ordering[$column] = $columns[$column];

    return $ordering;
}

# Add these to select statements for Detail reports
function detail_columns($phase) {
    
    $phases = array($phase => 1);
    
    # MPI Install
    if (isset($phases['mpi_install']))
        $phase_columns = array(
            'compiler_name',
            'compiler_version',
            'configure_arguments',
            'vpath_mode',
            'bitness',
            'endian',
        );

    # Test Build
    if (isset($phases['test_build']))
        $phase_columns = array(
            'compiler_name',
            'compiler_version',
            'suite_name',
            'bitness',
        );

    # Test Run
    if (isset($phases['test_run']))
        $phase_columns = array(
            'variant',
            'test_name',
            'command',
            'np',
        );

    $results_columns = array(
        'exit_status',
        'start_timestamp',
        'duration',
        'result_message',
        'result_stdout',
        'result_stderr',
        'environment',
        'client_serial',
    );
    
    return array_merge(
        $phase_columns,
        $results_columns
    );
}

# Convert English words to integers (1-10)
function strtonumeral($str) {

    $words_to_numerals = array(
        'zero'  => 0,
        'one'   => 1,
        'two'   => 2,
        'three' => 3,
        'four'  => 4,
        'five'  => 5,
        'six'   => 6,
        'seven' => 7,
        'eight' => 8,
        'nine'  => 9,
        'ten'   => 10,
    );

    $converted = $words_to_numerals[strtolower($str)];

    if ($converted)
        return $converted;
    else
        return $str;
}

?>
