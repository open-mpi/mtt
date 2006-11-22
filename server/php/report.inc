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

    # global declarations
    global $timestamp;
    global $thcolor, $gray, $dgray, $lgray, $llgray,
           $lllgray, $lred, $lgreen, $lyellow, $white;

    if ($_GET['cgi'] == 'on')
        debug_cgi($_GET, "GET");

    # Process input params
    $phases       = process_phase_field($_GET);
    $datefields   = process_date_field($_GET);
    $textfields   = process_textfields($_GET);
    $resultfields = get_result_cases($phases);

    $query = array_merge_recursive(
        $datefields,
        $textfields,
        $resultfields
    );
    $query['phases'] = $phases;

    $query['select'] = order_columns($query['select']);

    # Compose query
    $cmd = compose_sql($query);

    $resource = do_pg_query("\n$cmd");

    # Generate headers
    $headers['params']  = array();
    $headers['params']  = array_map('replace_underscores', array_keys($query['select']));
    $headers['results'] = array_keys($query['aggregates']);
    $headers['phases']  = $phases;

    print "<br><table>" .
          "<tr><td>Current time (GMT): <td>" . $datefields["current"] .
          "<tr><td>Date range (GMT): <td>" . $datefields["absolute"] .
          "</table><br>";

    dump_data_table($headers, $resource);

    print info_pointers($datefields);

    print "\n<br><hr><br>";

    pg_close();
}

# void function to print out html data table
function dump_data_table($headers, $resource) {

    # global declarations
    global $thcolor, $gray, $dgray, $lgray, $llgray,
           $lllgray, $lred, $lgreen, $lyellow, $white;

    $results_types = array("pass", "fail");

    # Some header labels
    $labels = array(
        '_if' => "fail",
        '_ip' => "pass",
        '_is' => "skip",
        '_it' => "timed",
        '_bf' => "fail",
        '_bp' => "pass",
        '_bs' => "skip",
        '_bt' => "timed",
        '_rf' => "fail",
        '_rp' => "pass",
        '_rs' => "skip",
        '_rt' => "timed",
    );

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
    $num_cols = count($headers['params']) +
                count($headers['results']) + 1;

    if (isset($_GET['table_title']))
        print "\n<tr><th bgcolor='$thcolor' colspan=$num_cols>" .
              "\n<i><b><br>" .  $_GET['table_title'] . "<br><br></b></i>";

    print
        "<tr>" .
        sprintf_("\n<th bgcolor='$thcolor' rowspan=2>%s", $headers['params']);

    # Number of result types for each phase
    $num_result_types = array(
        "mpi_install" => 2,
        "test_build" => 2,
        "test_run" => 4,
    );

    $total_result_cols = 0;
    foreach ($headers['phases'] as $phase) {
        print sprintf("\n<th bgcolor='$thcolor' " .
                      "colspan='$num_result_types[$phase]'>%s",
                      replace_underscores($phase));
        if ($num_result_types[$phase])
            $total_result_cols += $num_result_type[$phase];
    }

    print "\n<tr>";

    foreach ($headers['results'] as $result) {
        print sprintf("\n<th bgcolor='$thcolor'>%s", $labels[$result]);
    }

    $i = 0;
    # Display data rows
    while ($row = pg_fetch_row($resource)) {

        if ($i++ > $max_rows)
            break;

        # Results are always in the far right cols
        $len = (sizeof($headers['phases']) * sizeof($results_types)) + 2;
        $result_cols = array_splice($row, sizeof($row) - $len, $len);

        print "\n<tr>" . sprintf_("\n<td bgcolor=$white>%s", $row);

        $i = 0;

        # Each phase has differing result types
        foreach ($headers['phases'] as $phase) {
            $cols = $num_result_types[$phase];

            $pass = $result_cols[$i];
            $fail = $result_cols[$i+1];
            $skip = $result_cols[$i+2];
            $time = $result_cols[$i+3];

            if ($cols > 0)
                print "\n<td align='right' bgcolor='" .
                        (($pass > 0) ? $lgreen : $lgray) .  "'>$pass";
            if ($cols > 1)
                print "\n<td align='right' bgcolor='" .
                        (($fail > 0) ? $lred : $lgray) .    "'>$fail";
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

# Compose an SQL SELECT statement
function compose_sql($query) {

    $selects = array();
    $nl = "\n\t";

    # Determine table (or views) to SELECT from
    if (sizeof($query['phases']) > 1)
        $tables = array('all_phases');
    else
        $tables = suffix_list($query['phases'], '_view');

    # Compile list of aggregate clauses
    foreach (array_keys($query['aggregates']) as $aggregate) {
        $aggregates[] = $query['aggregates'][$aggregate];
    }

    $selects = array_merge(
        $query['select'],
        $aggregates
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
        $cmd .=     "$nl" . join(",$nl ", array_keys($query['select']));

        $cmd .= "\n ORDER BY ";
        $cmd .=     "$nl" . join(",$nl ", array_keys($query['select']));
    }

    $cmd .= ";";

    return $cmd;
}

# Return an array of SQL COUNT(CASE ...) clauses
# which will be used to tally the result numbers
# (Reference: postgresql.org/docs/7.3/static/functions-conditional.html)
function get_result_cases($phases) {

    $_phases = array_flip($phases);

    $result_cases = array();

    # MPI Installs
    if (isset($_phases["mpi_install"])) {
        $result_cases['aggregates']['_ip'] =
            "COUNT(CASE WHEN pass = '_ip' THEN '_ip' END) as _ip";
        $result_cases['aggregates']['_if'] =
            "COUNT(CASE WHEN fail = '_if' THEN '_if' END) as _if";
    }

    # Test Builds
    if (isset($_phases["test_build"])) {
        $result_cases['aggregates']['_bp'] =
            "COUNT(CASE WHEN pass = '_bp' THEN '_bp' END) as _bp";
        $result_cases['aggregates']['_bf'] =
            "COUNT(CASE WHEN fail = '_bf' THEN '_bf' END) as _bf";
    }

    # Test Runs
    if (isset($_phases["test_run"])) {
        $result_cases['aggregates']['_rp'] =
            "COUNT(CASE WHEN pass = '_rp' THEN '_rp' END) as _rp";
        $result_cases['aggregates']['_rf'] =
            "COUNT(CASE WHEN fail = '_rf' THEN '_rf' END) as _rf";
        $result_cases['aggregates']['_rs'] =
            "COUNT(CASE WHEN skipped = '_rs' THEN '_rs' END) as _rs";
        $result_cases['aggregates']['_rt'] =
            "COUNT(CASE WHEN timed_out = '_rt' THEN '_rt' END) as _rt";
    }

    return $result_cases;
}

# Show links to point user to more info ...
function info_pointers($datefields) {

    global $thcolor, $gray, $dgray, $lgray, $llgray,
           $lllgray, $lred, $lgreen, $lyellow, $white;
    global $domain, $url_basename;

    # Create links to report using relative and absolute date ranges
    $rel_link = dump_query_string($_GET) .  '&no_bookmarks';
    $abs_link = rewrite_url($rel_link, "text_start_timestamp", $datefields["absolute"]);

    # Can't be a relative link to an absolute date range report
    if (! isset($_GET['no_bookmarks'])) {

        $href = "\n<tr>" .
                  "\n<td bgcolor=$lgray>%s<td align=center bgcolor=$llgray>" .
                  "\n<a href='".$domain.$_SERVER['PHP_SELF']."?%s'".
                  "' class='black_ln'>[Link]</a>";

        $links = "\n<div align=left><br>" .
                 "\n<table border=1 width=20%>" .
                 "\n<tr><th bgcolor='$lgray' colspan=2>bookmarks";
        $links .= sprintf($href, "relative date range", $rel_link);
        $links .= sprintf($href, "absolute date range", $abs_link);
        $links .= "\n</table>" .
                  "\n</div>";
    }

    if (isset($_GET['info_links'])) {

        $href =  "\n<tr><td bgcolor=$lgray>%s<td align=center bgcolor=$llgray>" .
                 "\n<a href='".perfect_url("$url_basename/%s")."' class='black_ln'>" .
                 "\n<font size='-0'>[Link]</font></a>";

        $links .= "\n<div align=left><br>" .
                 "\n<table border=1 width=20%><tr><th bgcolor='$lgray' colspan=2>More Info";

        $links .= sprintf($href, "Summary Report", "summary.php");
        $links .= sprintf($href, "Custom Reports", "reporter.php");
        $links .= "\n</table>" .
                  "\n</div>";

    }

    return $links;
}

# 1. Generate WHERE clause pieces from user-entered textfields
# 2. Generate SELECT items from user-entered checkboxes
function process_textfields($params) {

    $query['where'] = array();
    $query['select'] = array();

    # These fields will not be string searchable
    $special_fields = array(
        "timestamp",
        "duration",
        "phase",
        "result"
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

            $format = "substring($timestamp_name from 0 for %d) as $timestamp_name";
            $format2 = "substring($timestamp_name from 0 for %d) || ':00' as $timestamp_name";

            if (preg_match("/by(?:-| *)sec(?:onds?)?/i", $token)) {
                $clause = $timestamp_name;

            } elseif (preg_match("/by(?:-| *)min(?:utes?)?/i", $token)) {
                $clause = sprintf($format, 17);

            } elseif (preg_match("/by(?:-| *)hours?/i", $token)) {
                $clause = sprintf($format2, 14);

            } elseif (preg_match("/by(?:-| *)days?/i", $token)) {
                $clause = sprintf($format, 11);

            } elseif (preg_match("/by(?:-| *)mon(?:ths?)?/i", $token)) {
                $clause = sprintf($format, 8);

            } elseif (preg_match("/by(?:-| *)years?/i", $token)) {
                $clause = sprintf($format, 5);
            }
        }
    }

    # PROTECT AGAINST AN EMPTY DATE RANGE
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
    return preg_replace('/^show_|^text_/', '', $str);
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
# an ordering of clauses
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

# Returns a trimmed query string
function dump_query_string($params) {

    global $cgi_abbrevs;

    foreach (array_keys($params) as $k) {

        # Only hash these textfield-filter_type pairs if BOTH are non-null
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

?>
