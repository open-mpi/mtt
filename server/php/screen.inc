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

# Print user dash-board 
function dump_query_screen($nogo) {

    $phases   = process_phase_field($_GET);
    $defaults = setup_defaults($phases);
    $layout   = setup_layout($phases);

    # Fill-in form using last invocation's input
    $lasttime = form_carryover($defaults);

    # Fill menus with universe first-time only
    if ($nogo)
        $entries = get_menus_info($defaults);
    else
        $entries = get_menus_info2($_GET);

    # Generate advanced popup menus
    $links = selection_popups($defaults, $entries);

    # Generate each of the screen's HTML components
    $layout = setup_layout_html($layout, $lasttime, $links);

    $self = "http://" . $_SERVER['SERVER_NAME'] . $_SERVER['PHP_SELF'];
    $phase_specific = $layout['farright']['html'] ? true : false;

    # Table cell tags
    $tds2 = "<td rowspan='2' bgcolor='" . DGRAY . "' width='1%'>";
    $tds3 = "<td rowspan='3' bgcolor='" . DGRAY . "' width='1%'>";
    $td1  = "<td rowspan='1' bgcolor='" . DGRAY . "'>";
    $td2  = "<td rowspan='2' bgcolor='" . DGRAY . "'>";
    $td3  = "<td rowspan='3' bgcolor='" . DGRAY . "'>";

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

    $tdb = "\n<td align='center' bgcolor='" . DGRAY . "' colspan='$colspan'>";
    $tdt = "\n<td align='center' bgcolor='" . DGRAY . "' colspan='" . ($colspan - 1) . "'>";

    # Print the screen
    print "<html>" . 
          html_head("Open MPI Test Reporter") .
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
          "\n </table>" .
          "\n </div>";
}

#########################################
#                                       
#  ttable Processing
#                                     
#########################################

# For cherry-picking, we select values by row number from a
# pseudo-temporary table.
#
# * No ttable_id
#     Create a new table (using setup_ttable)
# * ttable_id, but no cherry
#     Drop ttable_id table
#     Create a new table (using setup_ttable)
# * ttable_id + cherry
#     Use _GET[ttable_id], and update ttable.accessed
#
# This function always returns a 'ttable_id' for compose_sql
# whether it is new or recycled
#
# X: RENAME "ttable" TO "session"?
function handle_ttable_id($params) {

    # Setup a temporary TABLE/SEQUENCE 
    # NOTE: the above so-called temporary SQL relations are
    # NOT truly temporary, it is just that we intend to DROP
    # them after the user's session expires
    $ttable_id = $params['ttable_id'];

    $use_ttable = use_ttable($params);

    # Do not use last session's ttable
    if (! $use_ttable) {

        # Out with the old ...
        if ($ttable_id) {
            do_pg_query("DELETE FROM ttable WHERE tname = 'mtttemp_${ttable_id}_table';", SILENT);
            do_pg_query("DROP TABLE mtttemp_${ttable_id}_table;", SILENT);
            do_pg_query("DROP SEQUENCE mtttemp_${ttable_id}_seq;", SILENT);
        }

        # ... in with the new
        list($ttable_id) = setup_ttable();
    }
    # Use last session's ttable (update access time)
    else {

        $ttable = "mtttemp_${ttable_id}_table";

        $cmd = "SELECT 't' " .
               "FROM information_schema.tables " .
               "WHERE table_name = '$ttable';";

        $bool = select_scalar($cmd);

        # If the table is there, use it
        if ($bool) {
            do_pg_query("UPDATE ttable SET accessed = now() " . 
                            "WHERE tname = '$ttable';", SILENT);

        # Otherwise, we need to rebuild the ttable
        } else {

        }
    }

    return $ttable_id;
}

# Return true if we should use the ttable.
# Return false if:
#   - Cherry picked report
#   - Slice report
#   - Up/down arrow click report
#   - Drilldown
#
# * We can use the ttable for all of the above because we
# know they can only filter down on a parameter already in
# the table
function use_ttable($params) {

    # 'go' can be any of:
    #   * summary(_cherry)
    #   * performance(_cherry)
    #   * detail
    $lastgo = strtolower($params['lastgo']);
    $go     = strtolower($params['go']);

    $orderby_up   = $params['orderby_up'];
    $orderby_down = $params['orderby_down'];
    $offset       = $params['offset'];
    $drilldown    = $params['drill'];
    $slice        = $params['slice'];

    if ((preg_match("/cherry/i", $go) or
        $orderby_up or
        $orderby_down or
        ! is_null($offset) or
        $drilldown or
        $slice)
            and
        ((base_type($lastgo) == base_type($go)) or 
          ! $lastgo))
        $ret = true;
    else
        $ret = false;

    return $ret;
}

# Create an ID for the ''temporary'' TABLE and SEQUENCE
function setup_ttable($ttable_id_arg) {

    if ($ttable_id_arg)
        $ttable_id = $ttable_id_arg;
    else
        $ttable_id = get_ttable_id();

    $tformat = "mtttemp_%s_table";
    $sformat = "mtttemp_%s_seq";

    $ttable = sprintf($tformat, $ttable_id);
    $tseq   = sprintf($sformat, $ttable_id);

    do_pg_query("INSERT INTO ttable (tname) VALUES ('$ttable');");
    do_pg_query("CREATE SEQUENCE $tseq;");

    return array($ttable_id, $ttable, $tseq);
}

# Get a UNIQUE ttable id
function get_ttable_id() {
    return select_scalar("SELECT nextval('ttable_id');");
}

# Remove report type suffix
function base_type($str) {
    return preg_replace('/_cherry|_slice/', '', $str);
}

#########################################

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

# Populate menus with entries in ttable
function get_menus_info2($params) {

    $ttable_id = $params['ttable_id'];

    $table = "mtttemp_${ttable_id}_table";

    # Gather all available entries for the above columns
    $cmd = "SELECT * FROM $table;";

    $resource = do_pg_query($cmd);

    $hash = pg_fetch_all($resource);

    foreach (array_keys($hash) as $i)
        foreach (array_keys($hash[$i]) as $k)
            $arr[$k][] = $hash[$i][$k];

    foreach (array_keys($arr) as $k)
        $entries[$k][] = array_unique($arr[$k]);

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
        'platform_name',
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

    # Set up some table attributes
    $i    = 0;
    $cols = 1;
    $ctd  = "<td bgcolor='" . LGRAY . "' align='center'>";
    $td33 = "<td bgcolor='" . LGRAY . "' width='33%'>";

    # For the bottom buttons
    $rtd1b = "<td bgcolor='" . LGRAY . "' valign='bottom' align='right' rowspan='1' width='41%'>";
    $rtd1t = "<td bgcolor='" . LGRAY . "' valign='top'    align='right' rowspan='1' width='41%'>";
    $ctd2  = "<td bgcolor='" . LGRAY . "' align='left'                  rowspan='2' width='59%'>";

    $tbl  = "\n\n<table width='100%' cellspacing='1' cellpadding='5'>";
    $tbl2 = "\n\n<table width='100%' cellspacing='0' cellpadding='0'>";

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

            $td = "<td bgcolor='" . LGRAY . "'>";
            $veil = true;
            if (preg_match("/" . join('|', $veilless_cols) . "/i", $field)) {
                $veil = false;
                $td = "<td bgcolor='" . LGRAY . "' colspan='2'>";
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
        "\n<tr><td bgcolor='" . LGRAY . "'>";

    foreach ($layout['top']['fields'] as $phase) {

        # Bring over phase-independent selections, and
        # combine them with phase-dependent defaults on the
        # phase-selector radio-button click
        $defaults = setup_defaults($phase);
        $selections = form_carryover($defaults, $phase);
        $selections['phase'] = strtolower($phase);

        # Performance is enabled for test_run phase
        $go = strtolower($selections['go']);
        if ($go == 'performance' and $phase != 'test_run')
            $selections['go'] = 'Summary';

        # Bring this ttable_id over so we know to DROP it
        # next invocation
        $ttable_id = $_GET['ttable_id'];
        if (! is_null($ttable_id))
            $selections['ttable_id'] = $ttable_id;

        # They may not have yet pressed a Summary|Detail|Perf
        # button
        if (is_null($_GET['go']))
            unset($selections['go']);

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

    $buttons = form_buttons($_GET);
    $reset = array_shift($buttons);
    $clear = array_shift($buttons);

    # Put buttons at the bottom of the panel
    $layout['bottom']['html'] =
            "$reset&nbsp;" .
            "$clear&nbsp;" .
            join('&nbsp;', $buttons) .
        "\n</table>";

    return $layout;
}

# Return list of buttons for bottom of query panel
function form_buttons($params) {

    # Declare button types
    $types = array(
        "Summary",
        "Detail",
        "Performance",
    );

    $phases = process_phase_field($params);

    # Disable 'Detail' and 'Performance' buttons if we are
    # in multi-phase mode
    if (sizeof($phases) > 1) {
        $disable['Detail'] = 'disabled';
        $disable['Performance'] = 'disabled';
    }
    # Allow 'Performance' reports only in test_run mode
    elseif (! (array_search('test_run', $phases) !== false))
        $disable['Performance'] = 'disabled';

    $script = 'http://'.$_SERVER['SERVER_NAME'].$_SERVER['SCRIPT_NAME'];

    # Reset and Clear 'buttons' are small links
    $buttons[] =
        "\n<a href='javascript:document.report.reset();' " .
             "class='lgray_ln'>[Reset]</a>";
    $buttons[] =
        "\n<a href='$script' " .
             "class='lgray_ln'>[Clear]</a>";

    $format = "\n<input type='Submit' " .
                  "name='go' " .
                  "onClick='%s' " .
                  "value='%s' " .
                  "%s>";

    # Setup printf formats
    $self = 'http://'.$_SERVER['SERVER_NAME'].$_SERVER['SCRIPT_NAME'];
    $javascript = "javascript:self.open(\"$self?%s\", \"_self\");";

    # A button click means default sorting
    unset($params['orderby_up']);
    unset($params['orderby_down']);
    unset($params['offset']);
    unset($params['drill']);
    unset($params['slice']);

    foreach ($types as $type) {
        $params['go'] = $type;
        $qstring = arr2qstring($params);
        $buttons[] = 
            sprintf($format,
                         sprintf($javascript, $qstring),
                         $type,
                         $disable[$type]);
    }

    return $buttons;
}

# Return an array of selection menu popups
function selection_popups($defaults, $entries) {

    # For small menus in popup windows
    $tbl = "\n<table align='center' border='1' cellspacing='1' cellpadding='5'>";
    $td  = "<td align='center' bgcolor='" . LLGRAY . "'>";
    $td2 = "<td align='center' bgcolor='" . LLGRAY . "' colspan='2'>";
    $th2 = "<th align='center' bgcolor='" . LGRAY . "' colspan='2'>";

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
                "\n<a class='black_ln' href='javascript:popup_html(" .
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

    $lastgo = $params['go'];

    foreach (array_keys($params) as $k) {
        if (preg_match('/^go$|^phase$|^more_|^show_|^text_|^orderby|^cherry/', $k))
            continue;
        $str .= "\n<input type='hidden' name='$k' value='$params[$k]'>";
    }

    $str .= "\n<input type='hidden' name='lastgo' value='$lastgo'>";

    return $str;
}

# Load up some CSS and Javascript
function html_head($title) {

    $javascript = <<<EOT

    function popup_html(width,height,title,script,content,style) {

        newwindow2=window.open('','name','height=' + height + ',width=' + width + ',scrollbars=yes');
        var tmp = newwindow2.document;
        tmp.write('<html><head>' + script + '<title>' + title + '</title></head>');
        tmp.write('<body ' + style + '><form id=adv name=adv>' + content + '</form></body></html>');
        tmp.close();
    }

    function popup_text(width,height,content) {

        newwindow2=window.open('','name','height=' + height + ',width=' + width + ',scrollbars=yes');
        var tmp = newwindow2.document;
        tmp.write(content);
        tmp.close();
    }

    function littleWindow(link) {
        open(link, 'Tiny link', 'resizable=yes, toolbar=no, location=no, directories=no, status=no, menubar=no, scrollbars=no, width=50, height=30');
    }

EOT;

    $style = <<<EOT

    a.black_ln:link    { color: #000000 } /* for unvisited links */
    a.black_ln:visited { color: #555555 } /* for visited links */
    a.black_ln:active  { color: #FFFFFF } /* when link is clicked */
    a.black_ln:hover   { color: #FFFF40 } /* when mouse is over link */

    a.lgray_ln:link    { color: #F8F8F8; font-size: 105%; text-decoration:none; }
    a.lgray_ln:visited { color: #F8F8F8; font-size: 105%; text-decoration:none; }
    a.lgray_ln:active  { color: #FFFFFF; font-size: 105%; text-decoration:none; }
    a.lgray_ln:hover   { color: #FFFF40; font-size: 105%; text-decoration:none; }

    td { font-size: 75%; } 
    th { font-size: 80%; } 
    th#result { font-size: 55%; } 
    img#result { width: 55%; height: 55%; } 

EOT;

    # Print html head
    return "\n<head>" .
           "\n<title>$title</title>" .
           "\n<script language='javascript' type='text/javascript'>" .
           "\n$javascript" .
           "\n</script>" .
           "\n<style type='text/css'>" .
           "\n$style" .
           "\n</style>" .
           "\n</head>";
}

?>
