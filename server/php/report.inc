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
    $headers['params']  = array_map('replace_underscores', array_keys($query['select']));
    $headers['details'] = array_map('replace_underscores', array_keys($query['select_more']));
    $headers['results'] = array_keys($query['aggregates']);
    $headers['phases']  = $phases;

    print "<br><table>" .
          "<tr><td>Current time (GMT): <td>" . $datefields["current"] .
          "<tr><td>Date range (GMT): <td>" . $datefields["absolute"] .
          "</table><br>";

    # Print either a summary or detail table,
    # depending on whether a 'select_more' parameter is set
    if ($headers['details'])
        detail_table($headers, $resource);
    else
        summary_table($headers, $resource);

    print info_pointers($datefields);

    print "\n<br><hr><br>";

    pg_close();
}

# Void function to print out a summary style HTML data table
function summary_table($headers, $resource) {

    global $thcolor, $gray, $dgray, $lgray, $llgray,
           $lllgray, $lred, $lgreen, $lyellow, $white;

    $self = 'http://' . $_SERVER['SERVER_NAME'] . $_SERVER['REQUEST_URI'];

    # Append the detail params to the URL
    foreach (detail_columns() as $column)
        $appendage .= "&more_$column";

    # URL format for a drilldown
    $drilldown = "<a href='" . $self . $appendage . "%s%s' " .
                 "class='black_ln' " .
                 "target='_self'>%s" .
                 "</a>";

    # Some headers that link to drilled down reports
    $rformat = '&test_result=%s';
    $phase = '&phase=mpi_install';
    $labels['_if'] = sprintf($drilldown, $phase, sprintf($rformat, "fail"), "fail");
    $labels['_ip'] = sprintf($drilldown, $phase, sprintf($rformat, "pass"), "pass");
    $labels['_is'] = sprintf($drilldown, $phase, sprintf($rformat, "skip"), "skip");
    $labels['_it'] = sprintf($drilldown, $phase, sprintf($rformat, "timed"), "timed");

    $phase = '&phase=test_build';
    $labels['_bf'] = sprintf($drilldown, $phase, sprintf($rformat, "fail"), "fail");
    $labels['_bp'] = sprintf($drilldown, $phase, sprintf($rformat, "pass"), "pass");
    $labels['_bs'] = sprintf($drilldown, $phase, sprintf($rformat, "skip"), "skip");
    $labels['_bt'] = sprintf($drilldown, $phase, sprintf($rformat, "timed"), "timed");

    $phase = '&phase=test_run';
    $labels['_rf'] = sprintf($drilldown, $phase, sprintf($rformat, "fail"), "fail");
    $labels['_rp'] = sprintf($drilldown, $phase, sprintf($rformat, "pass"), "pass");
    $labels['_rs'] = sprintf($drilldown, $phase, sprintf($rformat, "skip"), "skip");
    $labels['_rt'] = sprintf($drilldown, $phase, sprintf($rformat, "timed"), "timed");

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
    print "\n<div align=center>" .

          "\n\n<!-- report_start -->\n\n" .

          "\n<table width='100%' cellpadding=5>" .
          "\n<tr>" .
          "\n<td bgcolor='$lgray'>" .
          "\n<div align=center>" .
          "\n<table border=1 width='100%'>";

    # Display headers
    $num_cols = count($headers['params']) +
                count($headers['results']) + 1;

    if (isset($_GET['table_title']))
        print "\n<tr><th bgcolor='$thcolor' colspan=$num_cols>" .
              "\n<i><b><br>" .  $_GET['table_title'] . "<br><br></b></i>";

    print
        "<tr>" .
        sprintf_("\n<th bgcolor='$thcolor' rowspan=2>%s", $headers['params']);

    $num_result_types = array(
        "mpi_install" => 2,
        "test_build" => 2,
        "test_run" => 4,
    );

    # Print result headers
    $total_results_cols = 0;
    foreach ($headers['phases'] as $phase) {
        print sprintf("\n<th bgcolor='$thcolor' " .
                      "colspan='$num_result_types[$phase]'>%s",
                      replace_underscores($phase));
        if ($num_result_types[$phase])
            $total_results_cols += $num_result_types[$phase];
    }

    print "\n<tr>";

    foreach ($headers['results'] as $result) {
        print sprintf("\n<th bgcolor='$thcolor'>%s", $labels[$result]);
    }

    $i = 0;

    # Print data rows
    while ($row = pg_fetch_row($resource)) {

        if ($i++ > $max_rows)
            break;

        # Results are always in the far right cols
        $results = array_splice($row, sizeof($row) - $total_results_cols);

        print "\n<tr>" . sprintf_("\n<td bgcolor=$white>%s", $row);

        $i = 0;

        # Each phase has differing result types
        foreach ($headers['phases'] as $phase) {
            $cols = $num_result_types[$phase];

            $pass = $results[$i];
            $fail = $results[$i+1];
            $skip = $results[$i+2];
            $time = $results[$i+3];

            print "\n<td align='right' bgcolor='" .
                    (($pass > 0) ? $lgreen : $lgray) . "'>$pass";

            print "\n<td align='right' bgcolor='" .
                    (($fail > 0) ? $lred : $lgray) . "'>$fail";

            if ($cols > 2)
                print "\n<td align='right' bgcolor='" .
                        (($skip > 0) ? $lyellow : $lgray) . "'>$skip";
            if ($cols > 3)
                print "\n<td align='right' bgcolor='" .
                        (($time > 0) ? $lyellow : $lgray) . "'>$time";

            $i += $cols;
        }
    }

    print "\n</table>" .
          "\n</table>" .
          "\n\n<!-- report_end -->\n\n";
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
        print sprintf("\n<th bgcolor='$thcolor' " .
                      "colspan='$num_result_types[$phase]'>%s",
                      replace_underscores($phase));
        if ($num_result_types[$phase])
            $num_cols['results'] += $num_result_types[$phase];
    }
    $num_cols['details'] = sizeof($headers['details']);
    $num_cols['params'] = sizeof($headers['params']);

    print "\n<tr>";

    foreach ($headers['results'] as $result) {
        print sprintf("\n<th bgcolor='$thcolor'>%s", $labels[$result]);
    }

    $i = 0;

    # Print data rows
    while ($row = pg_fetch_row($resource)) {

        if ($i++ > $max_rows)
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
            $bordercolor = (($pass > 0) ? $lgreen  : "");
        elseif ($fail)
            $bordercolor = (($fail > 0) ? $lred    : "");
        elseif ($skip)
            $bordercolor = (($skip > 0) ? $lyellow : "");
        elseif ($time)
            $bordercolor = (($time > 0) ? $lyellow : "");

        print "<br><table border='1'><tr><td bgcolor='$bordercolor'>";

        $td = "<td bgcolor='$lgray'>";
        $tdl = "<td bgcolor='$white'>";

        $i = 0;
        print "<table border='1' width='100%'>";
        foreach ($headers['params'] as $header) {
            print (($i % 1 == 0) ? "\n<tr>" : "") .
                  "\n$td <b>$header</b> $tdl " . $row[$i];
            $i++;
        }
        $i = 0;
        foreach ($headers['details'] as $header) {
            print (($i % 1 == 0) ? "\n<tr>" : "") .
                  "\n$td <b>$header</b> $tdl " . 
                  "\n<pre>$details[$i]</pre>";
            $i++;
        }
        print "</table>";
        print "</table>";
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
        $tables = array('all_phases');
    else
        $tables = suffix_list($query['phases'], '_view');

    foreach (array_keys($query['aggregates']) as $aggregate) {
        $aggregates[] = $query['aggregates'][$aggregate];
    }

    # Compile lists for SELECT, GROUP BY,
    # and ORDER BY statments
    $selects = array_merge(
        $query['select'],
        $aggregates,
        $query['select_more']
    );

    $groupbys = array_merge(
        array_keys($query['select']),
        array_keys($query['select_more'])
    );

    $orderbys = array_merge(
        array_keys($query['select'])
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
    if (isset($_phases["mpi_install"])) {
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
    if (isset($_phases["test_build"])) {
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
    if (isset($_phases["test_run"])) {
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
function info_pointers($datefields) {

    global $lgray, $llgray;

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
                  "\n<td bgcolor=$lgray>%s<td align=center bgcolor=$llgray>" .
                  "\n<a href='%s'".
                  "' class='black_ln'>[Link]</a>";

        $links = "\n<div align=left><br>" .
                 "\n<table border=1 width=20%>" .
                 "\n<tr><th bgcolor='$lgray' colspan=2>bookmarks";
        $links .= sprintf($href, "relative date range", $rel_link);
        $links .= sprintf($href, "absolute date range", $abs_link);
        $links .= "\n</table>" .
                  "\n</div>";
    }
    return $links;
}

# 1. Generate WHERE clause pieces from user-entered textfields
# 2. Generate SELECT items from user-entered checkboxes
function process_input_fields($params) {

    $query['where'] = array();
    $query['select'] = array();

    # These fields will not be string searchable
    $special_fields = array(
        "timestamp",
        "duration",
        "phase",
    );

    foreach (array_keys($params) as $k) {

        if (preg_match("/" . join("|", $special_fields) . "/i", $k))
            continue;

        # If it's a textfield, tokenize it and add each
        # item to WHERE clause
        elseif (preg_match("/^text_/i", $k)) {
            $column = strip_prefix($k);

            # No WHERE clause, if field is blank or "all"
            if (preg_match("/^\s*all\s*$|^\s*$/i", $params[$k], $m))
                continue;

            $clauses = array();
            foreach (tokenize($params[$k]) as $t) {
                $clauses[] = "$column ~* '$t'";
            }
            $query['where'][] = "(" . join(" OR ", $clauses) . ")";
        }
        # If it's a "show" checkbox, add it to SELECT clause
        elseif (preg_match("/^show_/i", $k)) {
            $column = strip_prefix($k);

            if (isset($params[$k]))
                $query['select'][$column] = $column;
        }
        # If it's a "more" param, add it to the ''end'' of the SELECT clause
        elseif (preg_match("/^more_/i", $k)) {
            $column = strip_prefix($k);

            if (isset($params[$k]))
                $query['select_more'][$column] = $column;
        }
    }
    return $query;
}

# Grab phase field
function process_phase_field($params) {
    if (isset($params['phase']))
        return tokenize($params['phase']);
    else
        return array("mpi_install", "test_build", "test_run");
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
    $date["current"] = $now;

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

            $format2 = "substring($timestamp_name from 0 for %d) || ':00' as $timestamp_name";
            $format3 = "substring($timestamp_name from 0 for %d) as $timestamp_name";

            if (preg_match("/by(?:-| *)sec(?:onds?)?/i", $token)) {
                $clause = $timestamp_name;

            } elseif (preg_match("/by(?:-| *)min(?:utes?)?/i", $token)) {
                $clause = sprintf($format3, 17);

            } elseif (preg_match("/by(?:-| *)hours?/i", $token)) {
                $clause = sprintf($format2, 14);

            } elseif (preg_match("/by(?:-| *)days?/i", $token)) {
                $clause = sprintf($format3, 11);

            } elseif (preg_match("/by(?:-| *)mon(?:ths?)?/i", $token)) {
                $clause = sprintf($format3, 8);

            } elseif (preg_match("/by(?:-| *)years?/i", $token)) {
                $clause = sprintf($format3, 5);
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
    $date["absolute"] = $absolute;

    return $date;
}

# Remove the prefix part of the parameter,
# which will leave only a database column name
function strip_prefix($str) {
    return preg_replace('/^more_|^show_|^text_/', '', $str);
}

# Reference: http://www.php.net/strtok
function tokenize($string) {
    $tokens = array();

    $c = "/\s*;\s*/";
    if (preg_match($c, $string))
        return preg_split($c, $string);

    for ($next_token = strtok($string, ' ');
         $next_token !== false;
         $next_token = strtok(' ')) {

        if ($next_token{0} == '"')
            $next_token =
                $next_token{strlen($next_token) - 1} == '"' ?
                     substr($next_token, 1, -1) :
                     substr($next_token, 1) . ' ' . strtok('"');
        $tokens[] = $next_token;
    }

    return $tokens;
}

function replace_underscores($str) {
    return preg_replace('/_/', ' ', $str);
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
    );

    foreach (array_keys($layout) as $column)
        if (isset($columns[$column]))
            $ordering[$column] = $columns[$column];

    return $ordering;
}

# Add these to select statements for Detail reports
function detail_columns() {
    return array(
        "exit_status",
        "start_timestamp",
        "duration",
        "result_message",
        "result_stdout",
        "result_stderr",
        "environment",
        "client_serial",
    );
}

?>
