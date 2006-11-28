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

    global $dgray;

    $phases   = process_phase_field($_GET);
    $defaults = setup_defaults($phases);
    $layout   = setup_layout($phases);

    # Fill-in form using last invocation's input
    $main_menu = form_carryover($defaults);

    # Generate advanced popup menus
    $entries = get_menus_info(array_keys($main_menu['text']));

    # Generate advanced popup menus
    $links = selection_popups($defaults, $entries);

    # Generate each of the screen's HTML components
    $layout = setup_layout_html($layout, $main_menu, $links);

    $self = "http://" . $_SERVER['SERVER_NAME'] . $_SERVER['PHP_SELF'];
    $phase_specific = $layout['farright']['html'] ? true : false;

    # Table cell tags
    $tds2  = "<td rowspan='2' bgcolor='$dgray' width='1%'>";
    $tds3  = "<td rowspan='3' bgcolor='$dgray' width='1%'>";
    $td1   = "<td rowspan='1' bgcolor='$dgray'>";
    $td2   = "<td rowspan='2' bgcolor='$dgray'>";
    $td3   = "<td rowspan='3' bgcolor='$dgray'>";

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

    $columns_arg = array_flip($columns_arg);

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
            if ($big_columns[$column] or ! isset($columns_arg[$column]))
                continue;

            # Put most recent 'r' numbers at the top of the menu
            $ordering = "ASC";
            if (preg_match("/mpi_version/i", $column))
                $ordering = "DESC";

            $cmd = "SELECT $column FROM $table " .
                   "WHERE $column != " . $columns[$table][$column] . " " .
                   "GROUP BY $column ORDER BY $column $ordering;";
            $entries[$column][] = simple_select($cmd);
        }
    }


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

    foreach (array_keys($enums) as $enum)
        $entries[$enum][] = array_merge(
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
        'by month',
        'by year',
    );
    return $entries;
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
function setup_defaults($phases) {

    $_phases = array_flip($phases);
    $single_phase = (sizeof($phases) == 1) ? true : false;

    # ompi does not submit results
    $http_username = $_SERVER['PHP_AUTH_USER'];
    if (! $http_username or preg_match("/ompi/i", $http_username))
        $http_username = 'all';

    $defaults = array(
        # phase
        'phase'             => 'all',

        # results
        'start_timestamp'   => 'past 24 hours',

        # submit
        'http_username'     => $http_username,
        'local_username'    => 'all',
        'hostname'          => 'all',

        # mpi_install
        'platform_hardware' => 'all',
        'os_name'           => 'all',
        'mpi_name'          => 'all',
        'mpi_version'       => 'all',
    );

    # phase-specific
    if ($single_phase) {
        if (isset($_phases['mpi_install']))
            $specific = array(
                'configure_arguments' => '',
                'compiler_name'       => 'all',
                'bitness'             => 'all',
                'endian'              => 'all',
            );
        elseif (isset($_phases['test_build']))
            $specific = array(
                'suite_name'       => 'all',
                'compiler_name'    => 'all',
                'compiler_version' => 'all',
                'bitness'          => 'all',
            );
        elseif (isset($_phases['test_run']))
            $specific = array(
                'suite_name' => 'all',
                'test_name'  => 'all',
                'np'         => 'all',
                'command'    => 'all',
            );
    }

    return array_merge(
        $defaults,
        $specific
    );
}

# Return an array to represent the
# screen's layout
function setup_layout($phases) {

    $_phases = array_flip($phases);
    $single_phase = (sizeof($phases) == 1) ? true : false;

    # phase
    $layout['top']['fields'] = array(
        'all',
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
        if (isset($_phases['mpi_install']))
            $layout['farright']['fields'] = array(
                'configure_arguments',
                'compiler_name',
                'bitness',
                'endian',
            );
        elseif (isset($_phases['test_build']))
            $layout['farright']['fields'] = array(
                'suite_name',
                'compiler_name',
                'compiler_version',
                'bitness',
            );
        elseif (isset($_phases['test_run']))
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
function setup_layout_html($layout, $menu, $links) {

    global $lgray, $llgray;

    # Generate Menu
    $i    = 0;
    $cols = 1;
    $ctd  = "<td bgcolor='$lgray' align='center'>";
    $ctd2 = "<td bgcolor='$lgray' align='center' colspan='2'>";
    $td33 = "<td bgcolor='$lgray' width='33%'>";
    $tbl  = "\n\n<table width='100%' align='center' cellspacing='1' cellpadding='5'>";

    # IMPORTANT: SET SECTIONS CONTAINING TEXT FIELDS FIRST, 
    # WE'LL OVERWRITE THE OTHER SECTIONS AFTERWARDS (see below)
    foreach (array_keys($layout) as $section) {
        $layout[$section]['html'] = "\n$tbl";

        # Display textfields and checkboxes
        foreach ($layout[$section]['fields'] as $field) {

            # No checkbox for some fields since they would widen the
            # summary table by several screen widths. Timestamp column
            # is added using, e.g. "by hours".
            $td = "<td bgcolor='$lgray'>";
            $checkbox = true;
            if (preg_match("/timestamp$|^command$|^configure_arguments$/i", $field)) {
                $checkbox = false;
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
                    "value='" . $menu['text'][$field] . "'>";


            # Checkbox
            if ($checkbox) {
                $layout[$section]['html'] .=
                    "\n$ctd" .
                    "\n<input type='checkbox' " .
                        "name='show_$field' " .
                        "id='show_$field' " . $menu['show'][$field] . ">";
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

    # Bring over phase-independent selections
    # on the phase-selector radio-button click
    $selections = partial_form_carryover(setup_defaults());
    $appendage = arr2qstring($selections);

    $layout['top']['html'] =
        "\n$tbl" .
        "\n<tr><td bgcolor='$lgray'>";
    foreach ($layout['top']['fields'] as $field) {
        $layout['top']['html'] .=
            "\n$field <input type='radio' " .
                     "name='phase' " .
                     "value='$field' " .
                     "onClick='javascript:self.open(\"$script?phase=$field$appendage\", \"_self\");' " .
                     $menu['radio'][$field] . '>';
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
        "\n<input type='Reset' value='Reset'>&nbsp;" .
        "\n<input type='Submit' name='go' value='Report'>" .
        "\n</table>";

    return $layout;
}

# Return an array of selection menu popups
function selection_popups($defaults, $entries) {

    global $lgray, $llgray;

    # For small menus in popup windows
    $tbl = "\n\n<table align='center' border='1' cellspacing='1' cellpadding='5'>";
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

        $menu = "\n" .
                "\n$tbl" .
                "\n<tr>$th2 $field<tr>";

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
            "\n<input type='submit' name='insert' onclick='javascript:exportVars();' value='Insert'>" .
            "\n</table>";

        # Widen popup according to the number of menus
        $num_menus = sizeof($entries[$field]);

        if ($linkto) {
            $link =
                "\n<a class='black_ln' href='javascript:popup(" .
                    # Width
                    "\n\"" . (400 * $num_menus) . "\"," .
                    # Height
                    "\n\"375\"," .
                    # Title
                    "\n\"Select $field\"," .
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
        else
            $link = "\n" . label($field);

        $links[$field] = $link;
    }
    return $links;
}

# Carry over textfields, checkboxes, and radios from the last invocation
function form_carryover($defaults) {

    foreach (array_keys($defaults) as $k) {
        if (isset($_GET["text_$k"]))
            $menu['text'][$k] = $_GET["text_$k"];
        else
            $menu['text'][$k] = $defaults[$k];

        if (isset($_GET['go']))
            if (isset($_GET["show_$k"])) {
                if ($_GET["show_$k"] == "on")
                    $menu['show'][$k] = "checked";
            }
            else
                $menu['show'][$k] = '';
        else
            $menu['show'][$k] = 'checked';
    }

    $phase = $_GET['phase'];
    if ($phase)
        $menu['radio'][$phase] = 'checked';
    else
        $menu['radio'][$defaults['phase']] = 'checked';

    return $menu;
}

# Carry over the phase-independent textfields, checkboxes,
# and radios from the last invocation
# (Return a list that is arr2qstring-ready)
function partial_form_carryover($defaults) {

    # Phase independent
    unset($defaults['phase']);

    foreach (array_keys($defaults) as $k) {
        $textfield = "text_$k";
        $showfield = "show_$k";

        if (isset($_GET[$textfield]))
            $selections[$textfield] = $_GET[$textfield];
        else
            $selections[$textfield] = $defaults[$k];

        if (isset($_GET[$showfield]))
            if ($_GET[$showfield] == 'on')
                $selections[$showfield] = 'on';
    }
    return $selections;
}

# Carry over input params (that are not submitted via form
# controls) between invocations of the script. Note:
# this string must be printed between the <form> tags
function hidden_carryover($params) {

    foreach (array_keys($params) as $k) {
        if (preg_match('/^phase$|^more_|^show_|^text_/', $k))
            continue;
        $str .= "\n<input type='hidden' name='$k' value='$params[$k]'>";
    }
    return $str;
}

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
