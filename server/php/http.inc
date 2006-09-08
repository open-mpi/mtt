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
# Functions that operate-on HTTP constructs
#   (pass $_GET or $_POST to them)
#
#

include_once("$topdir/reporter.inc");

# Return list of WHERE filters
function get_menu_filters($params) {

    global $All;
    global $cgi_abbrevs;

    $filters = array();

    foreach (array_keys($params) as $p) {
        if (preg_match("/^" . $cgi_abbrevs['menufield'] . "(\w+)$/i", $p, $m)) {
            $value = $params[$p];
            if ($value != $All and $value != null)
                array_push($filters, $m[1] . " = '" . $value . "'");
        }
    }
    return $filters;
}

# Return list of test results (pass/fail)
function get_results_filter($params) {

    global $cgi_abbrevs;

    $filters = array();

    if (preg_match("/pass/i", $params[$cgi_abbrevs['mainfield'] . 'success'])) {
        array_push($filters, "success = 't'");
    }
    elseif (preg_match("/fail/i", $params[$cgi_abbrevs['mainfield'] . 'success'])) {
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

                    # X: Not liking how we use is_int (what if the key is a string?)
                    if (is_int(array_search($field, array_keys($columns[$t])))) {

                        return $textfield_tables[$t]["phases"];
                    }
                }
            }
        }
    }

    # return all the phases by default
    return null;
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
            $clause = ($field_clauses[$f] ? $field_clauses[$f] : $f);
            array_push($selects, strtolower($clause));
        }
    }
    return $selects;
}

# Prints an HTML table of _GET and _POST vars
function dump_cgi_params($params, $title) {

    global $lgray;
    global $dgray;

    $cols = 3;

    print "\n\n<table width=80% border=1>";
    print "\n\n<tr><th bgcolor=$dgray colspan=" . $cols * 2 . ">$title";

    $i = 0;
    foreach (array_keys($params) as $k) {
        print "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
            "<td bgcolor=$lgray>" . $k . "<td>$params[$k]";
    }
    print "\n\n</table>";
}

# Returns a trimmed query string
function dump_cgi_params_trimnulls($params) {

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

# Return the element of the list that begins with *
function is_starred($str) {
    return preg_match('/^\s*\*/',$str);
}


?>
