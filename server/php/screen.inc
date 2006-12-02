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

# Print user dash-board 
function dump_query_screen() {

    global $dgray;

    debug_cgi($_GET, "GET");

    $phases   = process_phase_field($_GET);
    $defaults = setup_defaults($phases);
    $layout   = setup_layout($phases);

    # Fill-in form using last invocation's input
    $lasttime = form_carryover($defaults);

    # Generate advanced popup menus
    $entries = get_menus_info($defaults);

    # Generate advanced popup menus
    $links = selection_popups($defaults, $entries);

    # Generate each of the screen's HTML components
    $layout = setup_layout_html($layout, $lasttime, $links);

    $self = "http://" . $_SERVER['SERVER_NAME'] . $_SERVER['PHP_SELF'];
    $phase_specific = $layout['farright']['html'] ? true : false;

    # Table cell tags
    $tds2 = "<td rowspan='2' bgcolor='$dgray' width='1%'>";
    $tds3 = "<td rowspan='3' bgcolor='$dgray' width='1%'>";
    $td1  = "<td rowspan='1' bgcolor='$dgray'>";
    $td2  = "<td rowspan='2' bgcolor='$dgray'>";
    $td3  = "<td rowspan='3' bgcolor='$dgray'>";

    # Display some additional fields for phase-specific querying
    if ($phase_specific) {
        $layout['farright']['html'] =
            "\n$td2" .
            "\n" . $layout['farright']['html'];
        $colspan = 4;
    }
    else {
        $layout['farright']['html'] = "";
        $colspan = 3;
    }

    $tdb = "\n<td align='center' bgcolor='$dgray' colspan='$colspan'>";
    $tdt = "\n<td align='center' bgcolor='$dgray' colspan='" . ($colspan - 1) . "'>";

    # Print the screen
    print html_head() .
          "\n" .
          "\n<body>" .
          "\n<form method='get' id='report' name='report' action='$self'>" .
          "\n <div align='left'>" .
          "\n <table width='100%' align='center' border='1' cellspacing='1'>" .
          "\n   <tr>" .
          "\n" . $tds3 .
          "\n" . $layout['farleft']['html'] .
          "\n    $tdt" .
          "\n" . $layout['top']['html'] .
          "\n   <tr>" .
          "\n" . $td1 .
          "\n" . $layout['topleft']['html'] .
          "\n" . $td2 .
          "\n" . $layout['right']['html'] .
          "\n" . $layout['farright']['html'] .
          "\n   <tr>" .
          "\n" . $td1 .
          "\n" . $layout['bottomleft']['html'] .
          "\n   <tr>" .
          "\n    $tdb" .
                 $layout['bottom']['html'] .
                 hidden_carryover($_GET) .
          "\n </table>" .
          "\n </div>" .
          "\n </form>";
}

# Populate menus with entries (listed in columns_arg) from database
function get_menus_info($columns_arg) {

    $tables = array(
        'compute_cluster',
        'submit',
        'mpi_get',
        'compiler',
        'mpi_install',
        'test_build',
        'test_run',
        'results',
    );

    # Do *not* provide menus for these fields
    $big_columns = array(
        'command' => 1,
        'configure_arguments' => 1,
        'bitness' => 1,
        'endian' => 1,

        # Results
        'environment' => 1,
        'merge_stdout_stderr' => 1,
        'result_stdout' => 1,
        'result_stderr' => 1,
        'start_timestamp' => 1,
        'stop_timestamp' => 1,
        'duration' => 1,
        'submit_timestamp' => 1,
    );

    # Gather database columns
    $columns = array();
    $entries = array();
    $tmp = array();
    foreach ($tables as $table) {
        $tmp = get_table_fields($table);

        $size = sizeof($tmp['column_name']);
        for ($i = 0; $i < $size; $i++) {
            $column = $tmp['column_name'][$i];
            $default = $tmp['column_default'][$i];
            $default = preg_replace("/::.*$/i", '', $default);
            $columns[$table][$column] = $default;
        }
    }

    # Gather all available entries for the above columns
    foreach ($tables as $table) {
        foreach (array_keys($columns[$table]) as $column) {
            if ($big_columns[$column] or
                ! isset($columns_arg[$column]))
                continue;

            # Put most recent 'r' numbers at the top of the menu
            $ordering = "ASC";
            if (preg_match("/mpi_version/i", $column))
                $ordering = "DESC";

            $cmd = "SELECT $column FROM $table " .
                   "WHERE $column != " . $columns[$table][$column] . " " .
                   "GROUP BY $column ORDER BY $column $ordering;";
            $entries[$column][] = array_merge(
                                    array("all"),
                                    simple_select($cmd)
                                  );
        }
    }

    # Some special enumerated types
    $enums = enums_table();

    # Hmmm. "all" and "unknown" are treated the same
    foreach (array_keys($enums) as $enum)
        $entries[$enum][] = array_merge(
            array("all"),
            array_values($enums[$enum]), 
            array('unknown')
        );

    $entries['start_timestamp'][] = array(
        'today',
        'yesterday',
        'past 12 hours',
        'past 24 hours',
        'past 2 days',
        'past 3 days',
        'past 1 week',
        'past 2 weeks',
    );
    $entries['start_timestamp'][] = array(
        'by second',
        'by minute',
        'by hour',
        'by day',
        'by month',
        'by year',
    );
    return $entries;
}

# Return the list of fields prefixed with "text_" in the input
function get_textfields($params) {
    foreach (array_keys($params) as $param) 
        if (preg_match("/^text_(\w+)/i", $param, $m))
            $fields[] = $m[1];

    return $fields;
}

# Return javascript code to bring popup selections
# back into the main window's textfields
function jscript_export($entries, $field) {

	$script .= <<<EOT

    <script language='javascript'>

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

# 1. Two values to compare
# 2. An array->key combo
function checked($var1, $var2) {
    if (is_array($var1)) {
        if ($var1[$var2])
            return 'checked';
    }
    elseif ($var1 == $var2) {
        return 'checked';
    }
}

# Return an array to represent the
# screen's layout
function setup_layout($phases) {

    $single_phase = (sizeof($phases) == 1) ? true : false;

    # phase
    $layout['top']['fields'] = array(
        'all_phases',
        'mpi_install',
        'test_build',
        'test_run',
    );

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
    # phase-specific
    if ($single_phase) {
        if (array_search('mpi_install', $phases) !== false)
            $layout['farright']['fields'] = array(
                'configure_arguments',
                'compiler_name',
                'bitness',
                'endian',
            );
        elseif (array_search('test_build', $phases) !== false)
            $layout['farright']['fields'] = array(
                'suite_name',
                'compiler_name',
                'compiler_version',
                'bitness',
            );
        elseif (array_search('test_run', $phases) !== false)
            $layout['farright']['fields'] = array(
                'suite_name',
                'test_name',
                'np',
                'command',
            );
    }

    foreach (array_keys($layout) as $k)
        $layout['report']['fields'][] = $k;

    return $layout;
}

# Return the query screen HTML components
function setup_layout_html($layout, $lasttime, $links) {

    global $lgray, $llgray;

    # Generate Menu
    $i    = 0;
    $cols = 1;
    $ctd  = "<td bgcolor='$lgray' align='center'>";
    $ctd2 = "<td bgcolor='$lgray' align='center' colspan='2'>";
    $td33 = "<td bgcolor='$lgray' width='33%'>";
    $tbl  = "\n\n<table width='100%' align='center' cellspacing='1' cellpadding='5'>";

    # No veil (show/hide menu) for some fields since
    # they would widen the summary table by several
    # screen widths. Timestamp column is added
    # using, e.g. "by hours".
    $veilless_cols = array(
        'timestamp$',
         '^command$',
         '^configure_arguments$'
    );

    # IMPORTANT: SET SECTIONS CONTAINING TEXT FIELDS FIRST, 
    # WE'LL OVERWRITE THE OTHER SECTIONS AFTERWARDS (see below)
    foreach (array_keys($layout) as $section) {
        $layout[$section]['html'] = "\n$tbl";

        # Display textfields and show/hide menus
        foreach ($layout[$section]['fields'] as $field) {

            $td = "<td bgcolor='$lgray'>";
            $veil = true;
            if (preg_match("/" . join('|', $veilless_cols) . "/i", $field)) {
                $veil = false;
                $td = "<td bgcolor='$lgray' colspan='2'>";
            }

            # Textfield
            $layout[$section]['html'] .=
                "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
                "\n$td33 " .
                "\n" . $links[$field] . ":" .
                "\n$td " .
                "\n<input type='text' " .
                    "name='text_$field' " .
                    "id='text_$field' " .
                    # Carried over from last invocation
                    "value='" . $lasttime["text_$field"] . "'>";

            $selections = array('show', 'hide');

            # Carryover from last invocation
            # or 'show' by default
            $autoselect = null;
            if ($lasttime["show_$field"])
                $autoselect[$lasttime["show_$field"]] = 'selected';
            else
                $autoselect['show'] = 'selected';

            # Show/hide menu
            if ($veil) {
                $layout[$section]['html'] .=
                    "\n$ctd" .
                    "\n<select name='show_$field'>";

                foreach ($selections as $selection) {
                    $layout[$section]['html'] .=
                        "\n<option id='$selection' " .
                                  "name='$selection' " .
                                  "value='$selection' " . 
                                  $autoselect[$selection] . ">" . 
                              label($selection);
                }
                $layout[$section]['html'] .= "\n</select>";
            }
        }
        $layout[$section]['html'] .= '</table>';
    }

    # AFTERWARDS ...

    # Put the logo in the far left
    $script = 'http://'.$_SERVER['SERVER_NAME'].$_SERVER['SCRIPT_NAME'];
    $top    = dirname($script);
    $logo   = "$top/images/reporter_logo.gif";
    list($width, $height, $type, $attr) = getimagesize($logo);

    # Put phase selection at the top ...

    $layout['top']['html'] =
        "\n$tbl" .
        "\n<tr><td bgcolor='$lgray'>";

    foreach ($layout['top']['fields'] as $phase) {

        # Bring over phase-independent selections, and
        # combine them with phase-dependent defaults on the
        # phase-selector radio-button click
        $defaults = setup_defaults($phase);
        $selections = form_carryover($defaults);
        $selections['phase'] = $phase;
        $qstring = arr2qstring($selections);

        $layout['top']['html'] .=
            "\n<input type='radio' " .
                     "name='phase' " .
                     "value='$phase' " .
                     "onClick='javascript:self.open(\"$script?$qstring\", \"_self\");' " .
                     # Carried over from last invocation
                     checked($lasttime['phase'], $phase) . "> " . label($phase);
    }
    $layout['top']['html'] .=
        "\n</table>";

    $layout['farleft']['html'] =
        "\n<a href='$script'>" .
        "\n<img width='$width' " .
               "height='$height' " .
               "border='0' " .
               "src='$logo'></a>";

    # Put buttons at the bottom of the panel
    $layout['bottom']['html'] =
        $tbl .
        "\n<tr>$ctd " .
        join('&nbsp;', form_buttons($_GET)) .
        "\n</table>";

    return $layout;
}

# Return list of buttons for bottom of query panel
function form_buttons($params) {

    # Declare button types
    $types = array(
        "Summary",
        "Detail",
    );

    # Disable 'Detail' button if we are in multi-phase mode
    $phases = process_phase_field($params);

    if (sizeof($phases) > 1)
        $disable['Detail'] = 'disabled';

    $buttons[] =
        "\n<input type='Reset' value='Reset'>";

    $format = "\n<input type='Submit' " .
                  "name='go' " .
                  "value='%s' %s>";

    foreach ($types as $type)
       $buttons[] = sprintf($format, $type, $disable[$type]);

    return $buttons;
}

# Return an array of selection menu popups
function selection_popups($defaults, $entries) {

    global $lgray, $llgray;

    # For small menus in popup windows
    $tbl = "\n<table align='center' border='1' cellspacing='1' cellpadding='5'>";
    $td  = "<td align='center' bgcolor='$llgray'>";
    $td2 = "<td align='center' bgcolor='$llgray' colspan='2'>";
    $th2 = "<th align='center' bgcolor='$lgray' colspan='2'>";

    # Generate a popup window containing one or
    # more menus, for every textfield displayed in
    # the main window
    foreach (array_keys($defaults) as $field) {

        # Disallow multiple selection for date range
        if (! preg_match("/timestamp/i", $field))
            $multiple = 'multiple';

        $i = 0;

        $menu = "\n<div align='center'>" .
                "\n$tbl" .
                "\n<tr>$th2 " . label($field) . "<tr>";

        # Do not link to an empty menu(s)
        $linkto = false;

        # Each column keys to an array of arrays (one array of which is
        # normally the available entries in the database) 
        foreach (array_keys($entries[$field]) as $k) {

            $linkto = true;

            $menu .= "\n$td" .
                     "\n<select name='_".$i++."' $multiple size='10'>";

            foreach ($entries[$field][$k] as $entry) {
                $menu .= 
                    sprintf("\n<option style='width: 300px;' " .
                                       "name='%s' value='%s'>%s", 
                                       $entry, $entry, $entry);
            }
            $menu .= "\n</select>";
        }

        $menu .=
            "\n<tr>$td2" .
            "\n<input type='submit' " .
                      "name='insert' " .
                      "onclick='javascript:exportVars();' " .
                      "value='Insert'>&nbsp;" .
            "\n<input type='submit' " .
                      "name='cancel' " .
                      "onclick='javascript:window.close();' " .
                       "value='Cancel'>" .
            "\n</table>" .
            "\n<br><i>Select one or more menu items.</i>" .
            "\n</div>";

        # Widen popup according to the number of menus
        $num_menus = sizeof($entries[$field]);

        # Yippee, selection popup
        if ($linkto) {
            $link =
                "\n<a class='black_ln' href='javascript:popup(" .
                    # Width
                    "\n\"" . (400 * $num_menus) . "\"," .
                    # Height
                    "\n\"400\"," .
                    # Title
                    "\n\"Select " . label($field) . "\"," .
                    # <script>
                    "\n\"" . htmlentities(jscript_export($entries[$field], $field), ENT_QUOTES) . "\"," .
                    # <body>
                    "\n\"" . htmlentities($menu, ENT_QUOTES) . "\"," .
                    # <body style>
                    "\n\"font-family:Courier,monospace\"" . 
                ")'>" .
                "\n" . label($field) .  
                "</a>";
        }
        # Rats, no selection popup
        else
            $link = "\n" . label($field);

        $links[$field] = $link;
    }
    return $links;
}

# Carry over input params (that are not submitted via form
# controls) between invocations of the script. Note:
# this string must be printed between the <form> tags
function hidden_carryover($params) {

    foreach (array_keys($params) as $k) {
        if (preg_match('/^go$|^phase$|^more_|^show_|^text_/', $k))
            continue;
        $str .= "\n<input type='hidden' name='$k' value='$params[$k]'>";
    }
    return $str;
}

# Load up some CSS and Javascript
function html_head() {

    $javascript = <<<EOT

    function popup(width,height,title,script,content,style) {

        newwindow2=window.open('','name','height=' + height + ',width=' + width + ',scrollbars=yes');
        var tmp = newwindow2.document;
        tmp.write('<html><head>' + script + '<title>' + title + '</title></head>');
        tmp.write('<body ' + style + '><form id=adv name=adv>' + content + '</form></body></html>');
        tmp.close();
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
    th {font-size: 80%; }
EOT;

    # Print html head
    return "\n<head>" .
           "\n<title>Open MPI Test Reporter</title>" .
           "\n<script language='javascript' type='text/javascript'>" .
           "\n$javascript" .
           "\n</script>" .
           "\n<style type='text/css'>" .
           "\n$style" .
           "\n</style>" .
           "\n</head>";
}

?>
