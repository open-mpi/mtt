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
# The query screen generator
#
#

$topdir = ".";
include_once("$topdir/reporter.inc");
include_once("$topdir/database.inc");
include_once("$topdir/html.inc");

function dump_query_screen() {

    global $lgray, $llgray;

    $defaults = setup_defaults();
    $layout = setup_layout();

    # Fill-in form using last invocation's input
    $main_menu = menu_carryover($defaults);

    # Generate advanced popup menus
    $entries = get_menus_info(array_keys($main_menu["text"]));

    # Generate advanced popup menus
    $links = selection_popups($defaults, $entries);

    # Generate Menu
    $i = 0;
    $cols = 1;
    $td = "<td bgcolor=$lgray>";
    $ctd = "<td bgcolor=$lgray align=center>";
    $ztd = "<td bgcolor=$lgray width=33%>";
    $table_elem = "\n\n<table width=100% align=center cellspacing=1 cellpadding=5>";

    foreach (array_keys($layout) as $section) {
        $layout[$section]['html'] = "\n$table_elem";

        # Display input textfields
        foreach ($layout[$section]['fields'] as $field) {
            $layout[$section]['html'] .=
                "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
                "\n$ztd " .
                "\n" . $links[$field] . ":" .
                "\n$td " .
                "\n<input type='textfield' " .
                    "name='text_$field' " .
                    "id='text_$field' " .
                    "value='" . $main_menu["text"][$field] . "'>";

        # No checkbox for a timestamp field
        # Timestamp column is added using, e.g. "by hours"
        if (! preg_match("/timestamp/i", $field))
            $layout[$section]['html'] .=
                "\n$td " .
                "\n<input type='checkbox' " .
                    "name='show_$field' " .
                    "id='show_$field' " . $main_menu["show"][$field] . ">" .
                "\n";
        }
        $layout[$section]['html'] .= '</table>';
    }

    $layout['bottom']['html'] = 
        $table_elem .
        "\n<tr>$ctd " .
        "\n<input type='reset' value='Reset'>&nbsp;" .
        "\n<input type='submit' name='go' value='Report'>" .
        "\n</table>";

    # Print the screen
    print html_head();
    print "\n";
    print "\n<body>";

    print "\n <div align=left>";
    print "\n <table width=100% align=center border=1 cellspacing=1";
    print "\n   <form name=report target=_self>";
    print "\n   <tr><td>";
    print "\n" . $layout['topleft']['html'];
    print "\n   <td rowspan=2>";
    print "\n" . $layout['right']['html'];
    print "\n   <tr><td>";
    print "\n" . $layout['bottomleft']['html'];
    print "\n   <tr>";
    print "\n   <td align=center colspan=2>";
    print        $layout['bottom']['html'];
    print        carryover_cgi_params($_GET);
    print "\n   </form>";
    print "\n </table>";
    print "\n </div>";
}

# Carry input params over between invocations of the script
# Note: this string must be printed between the <form> tags
function carryover_cgi_params($params) {

    foreach (array_keys($params) as $k) {
        if (! $params[$k])
            $str .= "\n<input type='hidden' name='$k' value='$params[$k]'>";
    }
    return $str;
}

# Populate menus with entries (listed in columns_arg) from database
function get_menus_info($columns_arg) {

    $columns_arg = array_flip($columns_arg);

    $tables = array(
        "compute_cluster",
        "submit",
        "mpi_get",
        "compiler",
        "mpi_install",
        "test_build",
        "test_run",
        "results",
    );

    # Do *not* provide menus for these fields
    $big_columns = array(
        "command" => 1,
        "configure_arguments" => 1,

        # Results
        "environment" => 1,
        "merge_stdout_stderr" => 1,
        "result_stdout" => 1,
        "result_stderr" => 1,
        "start_timestamp" => 1,
        "stop_timestamp" => 1,
        "duration" => 1,
        "submit_timestamp" => 1,
    );

    # Gather database columns
    $columns = array();
    $entries = array();
    $tmp = array();
    foreach ($tables as $table) {
        $tmp = get_table_fields($table);
        $columns[$table] = $tmp["column_name"];
    }

    # Gather all available entries for the above columns
    foreach ($tables as $table) {
        foreach ($columns[$table] as $column) {
            if ($big_columns[$column] or ! isset($columns_arg[$column]))
                continue;

            $cmd = "SELECT $column FROM $table " .
                   "WHERE $column != 'bogus' " .
                   "GROUP BY $column ORDER BY $column DESC;";
            $entries[$column][] = simple_select($cmd);
        }
    }

    $entries["start_timestamp"][] = array(
        "today",
        "yesterday",
        "past 12 hours",
        "past 24 hours",
        "past 1 day",
        "past 2 days",
        "past 3 days",
        "past 1 week",
        "past 2 weeks",
    );
    $entries["start_timestamp"][] = array(
        "by second",
        "by minute",
        "by hour",
        "by month",
        "by year",
    );
    return $entries;
}

# Prints an HTML table of _GET and _POST vars
function debug_cgi($params, $title) {

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

# Return javascript code to bring popup selections
# back into the main window's textfields
function jscript_export($entries, $field) {

	$script .= <<<EOT

    <script language=javascript>

        function exportVars() {
            var str = '';
            var items = new Array();
EOT;

    $for_loop = <<<EOT

            for (i = 0; i < document.adv._%s.length; i++) {
                if (document.adv._%s.options[i].selected) {
                    items.push(document.adv._%s.options[i].text);
                }
            }
EOT;

    # THERE SHOULD BE NO NEED TO CREATE ''TWO'' FOR LOOPS
    # HERE
    $i = 0;
    foreach ($entries as $entry) {
        $script .= sprintf($for_loop, $i, $i, $i);
        $i++;
    }

	$script .= <<<EOT

            str = items.join(';');
            if (items.length > 0) {
                window.opener.document.report.text_$field.value = str;
            }
            window.close();
        }

    </script>
EOT;

    return $script;
}

# Provide logical labels for form controls
function label($str) {

    $labels = array(
        'start_timestamp' => "date_range",
        'submit_timestamp' => "date_range",
    );
    $label = $labels[$str];

    if ($label)
        return $label;
    else 
        return $str;
}

# Return an array of default values for textfields
function setup_defaults() {

    return array(
        # results
        "start_timestamp"   => 'past 24 hours',

        # submit
        "http_username" =>
            isset($_SERVER['PHP_AUTH_USER']) ?
            $_SERVER['PHP_AUTH_USER'] : "",
        "local_username"    => 'all',
        "hostname"          => 'all',

        # mpi_install
        "platform_hardware" => 'all',
        "os_name"           => 'all',
        "mpi_name"          => 'all',
        "mpi_version"       => 'all',
    );
}

# Return an array to represent the
# screen's layout
function setup_layout() {

    # results
    $layout['topleft']['fields'] = array(
        'start_timestamp'
    );
    # submit
    $layout['bottomleft']['fields'] = array(
        'http_username',
        'local_username',
        'hostname',
    );
    # mpi_install
    $layout['right']['fields'] = array(
        'platform_hardware',
        'os_name',
        'mpi_name',
        'mpi_version',
    );
    foreach (array_keys($layout) as $k)
        $layout['report']['fields'][] = $k;

    return $layout;
}

# Return an array of selection menu popups
function selection_popups($defaults, $entries) {

    global $lgray, $llgray;

    # For small menus in popup windows
    $table_elem = "\n\n<table align=center border=1 cellspacing=1 cellpadding=5>";
    $td = "<td align='center' bgcolor='$llgray'>";
    $td2 = "<td align='center' bgcolor='$llgray' colspan=2>";
    $th2 = "<th align='center' bgcolor='$lgray' colspan=2>";

    # Generate a popup window containing one or
    # more menus, for every textfield displayed in
    # the main window
    foreach (array_keys($defaults) as $field) {

        # Disallow multiple selection for date range
        if (! preg_match("/timestamp/i", $field))
            $multiple = "multiple";

        $i = 0;

        $menu = "\n<form id=adv name=adv>" .
                "\n$table_elem" .
                "\n<tr>$th2 $field<tr>";

        # Each column keys to an array of arrays (one array of which is
        # normally the available entries in the database) 
        foreach (array_keys($entries[$field]) as $k) {

            $size = sizeof($entries[$field][$k]);
            $menu .= "\n$td" .
                     "\n<select name='_".$i++."' $multiple size='10'>";

            foreach ($entries[$field][$k] as $entry) {
                $menu .= 
                    sprintf("\n<option style='width: 220px;' " .
                                       "name='%s' value='%s'>%s", 
                                       $entry, $entry, $entry);
            }
            $menu .= "\n</select>";
        }

        $menu .=
            "\n<tr>$td2" .
            "\n<input type='submit' name='insert' onclick='javascript:exportVars();' value='Insert'>" .
            "\n</table>" .
            "\n</form>";

        $num_menus = sizeof($entries[$field]);

        $link =
            "\n<a class='black_ln' href='javascript:popup(" .
                "\n\"" . (350 * $num_menus) . "\"," .
                "\n\"300\"," .
                "\n\"Title\"," .
                "\n\"" . htmlentities(jscript_export($entries[$field], $field), ENT_QUOTES) . "\"," .
                "\n\"" . htmlentities($menu, ENT_QUOTES) . "\"," .
                "\n\"font-family:Courier,monospace\"" . 
            ")'><font size='$sfont'>" . label($field) . "</font>" .
            "</a>";

        $links[$field] = $link;
    }
    return $links;
}

# carry over textfields and checkboxes from the last invocation
function menu_carryover($defaults) {

    foreach (array_keys($defaults) as $k) {
        if (isset($_GET["text_$k"]))
            $menu["text"][$k] = $_GET["text_$k"];
        else
            $menu["text"][$k] = $defaults[$k];

        if (isset($_GET["go"]))
            if (isset($_GET["show_$k"])) {
                if ($_GET["show_$k"] == "on")
                    $menu["show"][$k] = "checked";
            }
            else
                $menu["show"][$k] = "";
        else
            $menu["show"][$k] = "checked";
    }
    return $menu;
}

function html_head() {

    $javascript = <<<EOT

    function popup(width,height,title,script,content,style) {

        newwindow2=window.open('','name','height=' + height + ',width=' + width + ',scrollbars=yes');
        var tmp = newwindow2.document;
        tmp.write('<html><head>' + script + '<title>' + title + '</title></head>');
        tmp.write('<body ' + style + '>' + content + '</body></html>');
        tmp.close();
    }

    // X: combine the following two functions

    // Disable all objects passed to the function
    function disable() {

        for (i = 0; i < arguments.length; i++) {

            // alert("list[i] = " + arguments[i]);

            // Aack! How do we check to see if the val is defined!
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

    a.black_ln:link    { color: #000000 } /* for unvisited links */
    a.black_ln:visited { color: #555555 } /* for visited links */
    a.black_ln:active  { color: #FFFFFF } /* when link is clicked */
    a.black_ln:hover   { color: #FFFF40 } /* when mouse is over link */
    td {font-size: 75%; }

EOT;

    # Print html head (query frame & results frame may need this script/style)
    $html_head = "";
    $html_head .= "\n<html>";
    $html_head .= "\n<head><title>Open MPI Test Reporter</title>";

    $html_head .= "\n<script language='javascript' type='text/javascript'>";
    $html_head .= "\n$javascript";
    $html_head .= "\n</script>";

    $html_head .= "\n<style type='text/css'>";
    $html_head .= "\n$style";
    $html_head .= "\n</style>";
    $html_head .= "\n</head>";

    return $html_head;
}

?>
