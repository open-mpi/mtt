<?php

#
# Copyright (c) 2006-2007 Sun Microsystems, Inc.
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
    $defaults = setup_mainwin_fields($phases);
    $layout   = setup_layout($phases);

    # Fill-in form using last invocation's input
    $lasttime = form_carryover($defaults);

    # Fill menus with universe first-time only
    if ($nogo)
        $entries = get_form_universe($defaults);
    else
        list($entries, $disable) = get_form_universe2($_GET);

    # Generate advanced popup menus
    $links = selection_popups($defaults, $entries);

    # Generate each of the screen's HTML components
    $layout = setup_layout_html($layout, $lasttime, $links, $disable);

    $self = "http://" . $_SERVER['SERVER_NAME'] . $_SERVER['PHP_SELF'];
    $phase_specific = $layout['farright']['html'] ? true : false;

    # Table cell tags
    $tds3 = "<td rowspan='3' bgcolor='" . DGRAY . "' width='1%'>";
    $td1  = "<td rowspan='1' bgcolor='" . DGRAY . "'>";
    $td2  = "<td rowspan='2' bgcolor='" . DGRAY . "'>";

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

    # Need to define the Preferences in the opener form
    # so they will have properties when exported from the
    # Preferences popup
    $prefs = hidden_prefs($_GET);

    # Print the screen
    print "<html>" . 
          html_head("Open MPI Test Reporter") .
          "\n" .
          "\n<body>" .
          "\n<form method='get' id='report' name='report' action='$self'>" .
          "\n$prefs" .
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
    #   * summary(_cherry|_click)
    #   * performance(_cherry|_click)
    #   * detail(_click)
    $lastgo = $params['lastgo'];
    $go     = $params['go'];
    $click  = $params['click'];

    $orderby_up   = $params['orderby_up'];
    $orderby_down = $params['orderby_down'];
    $offset       = $params['offset'];
    $drilldown    = $params['drill'];
    $slice        = $params['slice'];

    if (! is_null($click))
        return false;
    elseif ((preg_match("/cherry/i", $go) or
        $orderby_up or
        $orderby_down or
        ! is_null($offset) or
        $drilldown or
        $slice)
            and
        ((base_type($lastgo) == 
          base_type($go)) or 
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
    return strtolower(preg_replace('/_cherry|_slice/i', '', $str));
}

#########################################

# Populate menus with entries (listed in columns_arg) from database
function get_form_universe($columns_arg) {

    $phases = process_phase_field($_GET);
    if (sizeof($phases) == 1)
        $phase = $phases[0];

    $tables = array(
        'compute_cluster',
        'submit',
        'mpi_get',
        'compiler',
    );

    if ($phase == 'test_build')
        $phase_tables = 
            array('mpi_install', 'test_build');
    elseif ($phase == 'test_run')
        $phase_tables = 
            array('mpi_install', 'test_build', 'test_run');

    $tables = array_merge($tables, $phase_tables);

    # Do *not* provide menus for these fields
    # $big_columns = array(
    #     'command'             => 1,
    #     'configure_arguments' => 1,
    #     'bitness'             => 1,
    #     'endian'              => 1,
    # );

    # COMMENT THIS OUT FOR NOW, IT'S NOT REALLY HELPING THE
    # TOOL AND IT SLOWS DOWN BRING-UP TIME TO MAKE IT MORE
    # EFFICIENT, THE ENTIRE DB UNIVERSE SHOULD BE CACHED
    # EVERY ''N'' MINUTES TO AVOID THE LARGE TABLE SCANS ON
    # BRING-UP, AND THE COLUMN DATA SHOULD BE GATHERED FROM THERE

    # Gather database columns
    # $columns = array();
    # $entries = array();
    # $tmp = array();
    # foreach ($tables as $table) {
    #     $tmp = get_table_fields($table);

    #     $size = sizeof($tmp['column_name']);
    #     for ($i = 0; $i < $size; $i++) {
    #         $column = $tmp['column_name'][$i];
    #         $default = $tmp['column_default'][$i];
    #         $default = preg_replace("/::.*$/i", '', $default);
    #         $columns[$table][$column] = $default;
    #     }
    # }

    # Gather all available entries for the above columns
    # foreach ($tables as $table) {
    #     foreach (array_keys($columns[$table]) as $column) {
    #         if ($big_columns[$column] or
    #             ! isset($columns_arg[$column]))
    #             continue;

    #         # Put most recent 'r' numbers at the top of the menu
    #         $ordering = "ASC";
    #         if (preg_match("/mpi_version/i", $column))
    #             $ordering = "DESC";

    #         $cmd = "SELECT $column FROM $table " .
    #                "WHERE $column != " . $columns[$table][$column] . " " .
    #                "GROUP BY $column ORDER BY $column $ordering;";
    #         $entries[$column][] = array_merge(
    #                                 array("all"),
    #                                 simple_select($cmd)
    #                               );
    #     }
    # }

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

# Populate menus with entries in ttable,
# and 'Performance' button ''disable'' value
function get_form_universe2($params) {

    $ttable_id = $params['ttable_id'];

    $table = "mtttemp_${ttable_id}_table";

    # Gather all available entries for the already
    # created report
    $cmd = "SELECT * FROM $table;";

    $resource = do_pg_query($cmd);

    $hash = pg_fetch_all($resource);

    foreach (array_keys($hash) as $i)
        foreach (array_keys($hash[$i]) as $k)
            $arr[$k][] = $hash[$i][$k];

    foreach (array_keys($arr) as $k)
        # Do not collect timestamp entries from the ttable
        if (! preg_match("/timestamp/", $k))
            $entries[$k][] = array_unique($arr[$k]);

    # Disable the 'Performance' button if there
    # is no performance data
    
    $perf_code = '_rl';
    if ($arr[$perf_code]) {
        # disabled
        if (max(array_values($arr[$perf_code])) < 1)
            $disable['Performance'] = 'disabled';
        # enabled
        else
            $disable['Performance'] = '';
    }

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

    return array($entries, $disable);
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

    # THERE SHOULD BE NO NEED TO CREATE MORE THAN ONE FOR LOOP HERE
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

# Return javascript code to bring Preferences popup
# selections back into the main window's textfields
function jscript_export_form($elements, $save_to_cookie) {

    $path = PATH;

    $go = $_GET['go'];
    $click = $_GET['click'];

    if ($save_to_cookie) {
        $cookie_ize_expression = <<<EOT
            window.opener.document.report.do_cookies.value = 1;
EOT;
    }

    if (! $go)
        $go = $click;

	$script .= <<<EOT

    <script language='javascript'>

        function SaveAndSubmit() {
            exportVars();
            window.opener.document.report.remote_go.value = '$go';

            $cookie_ize_expression

            window.opener.document.report.submit();
            window.close();
        }

        function exportVars() {

            var str = '';
            var items = new Array();

EOT;

    # CAREFUL - IS ''x'' GUARANTEED TO BE DEFINED?  BEWARE
    # OF undefined (OR null?) VARS WHICH CAUSE "NO
    # PROPERTIES" JAVASSCRIPT ERRORS. (WE NEED TO HAVE
    # 'HIDDEN' FORM PARAMETERS TO PREVENT SUCH ERRORS)
    $text = <<<EOT

            var x = document.adv.%s;
            var old = window.opener.document.report.%s;
            old.value = x.value;

EOT;

    # CAREFUL - IS ''x'' GUARANTEED TO BE DEFINED?  BEWARE
    # OF undefined (OR null?) VARS WHICH CAUSE "NO
    # PROPERTIES" JAVASSCRIPT ERRORS. (WE NEED TO HAVE
    # 'HIDDEN' FORM PARAMETERS TO PREVENT SUCH ERRORS)
    $checkbox = <<<EOT
            var x = document.adv.%s;
            var old = window.opener.document.report.%s;
            var newValue = 'off';

            if (x.checked) {
                newValue = 'on';
            }
            old.value = newValue;

EOT;

    $select = <<<EOT

            var x = document.adv.%s;
            var old = window.opener.document.report.%s;

            for (i = 0; i < x.length; i++) {
                if (x.options[i].selected) {
                    str = x.options[i].text;
                }
            }
            old.value = str;

EOT;

    # X: THERE SHOULD BE NO NEED TO CREATE MORE THAN ONE FOR
    # LOOP HERE. IN OTHER WORDS, DO THE LOOPING IN
    # JAVASCRIPT INSTEAD OF PRINTING OUT ''N'' JAVASCRIPT
    # STATEMENTS
    foreach (array_keys($elements) as $pref) {
        if (is_array($elements[$pref]))
            $script .= sprintf($select, $pref, $pref, $pref);
        elseif (is_bool($elements[$pref]))
            $script .= sprintf($checkbox, $pref, $pref, $pref);
        else
            $script .= sprintf($text, $pref, $pref, $pref);
    }

    # Generate a debug string to print using e.g., alert()
	$script .= <<<EOT

            var str = '';
            var x = window.opener.document.report;
            for (var i = 0; i < x.length; i++) {
                str += x.elements[i].name + ' = ' + x.elements[i].value + ';';
            }
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
function setup_layout_html($layout, $lasttime, $links, $disable) {

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

    $disableds = disabled_showhides($_GET);

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

            $selection_labels = array('show', 'hide');
            $selection_values = array('show', 'hide');

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
                    "\n<select name='show_$field' " . $disableds[$field] . ">";

                foreach (array_keys($selection_labels) as $i) {
                    $layout[$section]['html'] .=
                        "\n<option id='$selection_labels[$i]' " .
                                  "name='$selection_labels[$i]' " .
                                  "value='$selection_values[$i]' " . 
                                  $autoselect[$selection_labels[$i]] . ">" . 
                              label($selection_labels[$i]);
                }
                $layout[$section]['html'] .= "\n</select>";
            }
        }
        $layout[$section]['html'] .= '</table>';
    }

    # AFTERWARDS ...

    $top = DOCROOT;

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
        $defaults = setup_mainwin_fields($phase);
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

    $buttons = form_buttons($_GET, $disable);
    $reset = array_shift($buttons);
    $clear = array_shift($buttons);
    $showhide = array_pop($buttons);
    $prefs = array_pop($buttons);

    # Put buttons at the bottom of the panel
    $layout['bottom']['html'] =
            "$reset&nbsp;" .
            "$clear&nbsp;" .
            join('&nbsp;', $buttons) . "&nbsp;" .
            "$prefs&nbsp;" .
            "$showhide" .
        "\n</table>";

    return $layout;
}

# Disable show/hide menu for certain fields
function disabled_showhides($params) {
    $go = get_go_or_click($params);
    if (preg_match("/detail/i", $go))
        $disableds['test_name'] = 'disabled';

    return $disableds;
}

# Return list of buttons for bottom of query panel
function form_buttons($params, $disable_arg) {

    # Declare button types
    $types = array(
        "Summary",
        "Detail",
        "Performance",
    );

    $phases = process_phase_field($params);

    # Disable 'Performance' button if we are
    # in there are no perf results to report on
    if (! is_null($disable_arg))
        $disable = $disable_arg;
    else
        $disable['Performance'] = 'disabled';

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
             "class='lgray_ln'>[Reset form]</a>";
    $buttons[] =
        "\n<a href='javascript:StartOver();' " .
             "class='lgray_ln'>[Start over]</a>";

    $format = "\n<input type='submit' id='click' name='click' value='%s' type='submit' %s>";

    # A button click means default sorting
    unset($params['orderby_up']);
    unset($params['orderby_down']);
    unset($params['offset']);
    unset($params['drill']);
    unset($params['slice']);

    foreach ($types as $type) {
        $params['go'] = $type;

        $qstring = arr2qstring($params);
        $buttons[] = sprintf($format, $type, $disable[$type]);
    }

    # Generate Preferences popup
    $specs['title']          = 'Preferences';
    $specs['width']          = 500;
    $specs['height']         = 500;
    $specs['dropdown_width'] = 200;
    $specs['onclick']        = 'SaveAndSubmit()';
    $specs['button']         = 'Save';
    $specs['save_to_cookie'] = 'true';
    $specs['are_columns']    = false;

    $buttons[] = form_popup(setup_prefs(), $_GET, $specs);

    # Generate Advanced popup
    $specs['title']          = 'Advanced';
    $specs['width']          = 500;
    $specs['height']         = 800;
    $specs['dropdown_width'] = 50;
    $specs['onclick']        = 'SaveAndSubmit()';
    $specs['button']         = 'Submit';
    $specs['save_to_cookie'] = 'false';
    $specs['are_columns']    = true;

    $buttons[] = form_popup(setup_advanced($_GET), $_GET, $specs);

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

    # Enable/disable performance button
    $links['Performance'] = $entries['performance'];

    return $links;
}

#########################################
#                                       
#  Preferences Processing
#                                     
#########################################

# A string to define the hidden preferences
function hidden_prefs($params) {
    $prefs = setup_prefs();

    foreach (array_keys($prefs) as $cat) {
        foreach (array_keys($prefs[$cat]) as $field) {
            $value = $params[$field];

            $ret .= "\n<input type='hidden' " . 
                             "name='" . $field . "' " .
                             "value='" . $value . "'>";
        }
    }

    # Prepare remote_go flag
    if (is_null($params['remote_go']))
        $ret .= "\n<input type='hidden' name='remote_go'>";

    # Prepare do_cookies flag
    if (! isset($params['do_cookies']))
        $ret .= "\n<input type='hidden' name='do_cookies'>";

    return $ret;
}

# Return a link to a JavaScript popup that contains an
# HTML form (with checkboxes, menus, and/or textfields)
# (quite similar to selection_popups).
# Enter the string 'true' or 'false' for $save_to_cookie.

# This function is used for the [Preferences] and [Advanced]
# popups. This is perhaps a stretch.
function form_popup($elements, $params, $specs) {

    # Specifications for the popup

    # title          = popup window title
    # width          = popup window width
    # height         = popup window height
    # dropdown_width = dropdown menu width
    # onclick        = javascript onclick event name
    # button         = button name in popup
    # save_to_cookie = save to cookie boolean
    # are_columns    = each element maps to a DB column

    $title          = $specs['title'];
    $width          = $specs['width'];
    $height         = $specs['height'];
    $dropdown_width = $specs['dropdown_width'];
    $onclick        = $specs['onclick'];
    $button         = $specs['button'];
    $save_to_cookie = $specs['save_to_cookie'];
    $are_columns    = $specs['are_columns'];

    # Determine the colspan
    $max = 0;
    foreach (array_keys($elements) as $category) {
        foreach (array_keys($elements[$category]) as $field) {
            $size = sizeof($elements[$category][$field]);
            if ($size > $max)
                $max = $size;
        }
    }
    $colspan = $max;

    # For small menus in popup windows
    $tbl = "\n<table align='center' border='1' cellspacing='1' cellpadding='5'>";
    $tr  = "\n<tr>";
    $td  = "\n<td align='left' bgcolor='" . LLGRAY . "'>";
    $td2 = "\n<td align='left' bgcolor='" . LLGRAY . "' colspan='%d'>";
    $th2 = "\n<th align='center' bgcolor='" . LGRAY . "' colspan='%d'>";

    $menu = "\n<div align='center'>" .
            "\n$tbl";

    # Indicate that the fields in this popup are database columns,
    # because database columns are always handled by having them be
    # two input params, one prepends the name with 'text_', the other
    # with 'show_'
    if ($are_columns) {
        $text_ = 'text_';
        $show_ = 'show_';

        # Export the vars in JavaScript and prepend these
        $col_types = array($text_, $show_);
    }

    # Categories are: General and Graphing
    foreach (array_keys($elements) as $category) {

        # +1 colspan for the label
        $menu .= $tr . sprintf($th2, $colspan + 1) . label($category);

        # Create an HTML form element for each element based
        # on the element's data type:
        #
        #   1. Bool: checkbox 
        #   2. Scalar: text 
        #   3. Array: select (dropdown menu)
        #
        foreach (array_keys($elements[$category]) as $field) {
            $array = $elements[$category][$field];

            $menu .= $tr . $td . label(label($field));

            # Set the colspan based on the number of
            # elements in the array since that will equal
            # the number of table cells
            if (sizeof($array) == $colspan) 
                $td_colspan = 1;
            else
                $td_colspan = $colspan;

            foreach (array_keys($array) as $i) {

                $entries = $array[$i];

                # Compile list of elements for jscript_export_form
                if ($are_columns) {
                    $type = $col_types[$i];
                    $arr["$type$field"] = $entries;

                    # Fill-in field for default or last selection
                    $value = auto_fill($entries, $params["$type$field"]);
                }
                else {
                    $arr[$field] = $entries;

                    # Fill-in field for default or last selection
                    $value = auto_fill($entries, $params[$field], $_COOKIE["mtt_$field"]);
                }

                $menu .= sprintf($td2, $td_colspan);

                if (is_bool($entries))
                    $menu .= "\n<input type='checkbox' name='$field' value='on' $value>";

                elseif (is_scalar($entries))
                    $menu .= "\n<input type='text' name='$text_$field' value='" . $value . "'>";

                elseif (is_array($entries)) {

                    $menu .= "\n<select name='$show_$field'>";

                    $i = 0;
                    foreach ($entries as $v) {
                        $v = strip_star($v);
                        $menu .= sprintf("\n<option " .
                                                "style='width: ${dropdown_width}px;' " .
                                                "name='%s' " .
                                                "value='%s' %s>%s",
                                                $v, $v, $value[$i++], $v);
                    }
                    $menu .= "\n</select>";
                }
            }
        }
    }

    $menu .=
        $tr . sprintf($th2, $colspan + 1) .
        "\n<input type='submit' " .
                  "name='$button' " .
                  "onclick='javascript:$onclick;' " .
                  "value='$button'>&nbsp;" .
        "\n<input type='submit' " .
                  "name='cancel' " .
                  "onclick='javascript:window.close();' " .
                   "value='Cancel'>" .
        "\n</table>" .
        "\n<br><i>Make one or more selections from the [$title] menu.</i>" .
        "\n</div>";

    $link =
        "\n<a class='lgray_ln' href='javascript:popup_html(" .
            # Width
            "\n\"$width\"," .
            # Height
            "\n\"$height\"," .
            # Title
            "\n\"Select $title\"," .
            # <script>
            "\n\"" . htmlentities(jscript_export_form($arr, $save_to_cookie), ENT_QUOTES) . "\"," .
            # <body>
            "\n\"" . htmlentities($menu, ENT_QUOTES) . "\"," .
            # <body style>
            "\n\"font-family:Courier,monospace\"" . 
        ")'>" .
        "\n[$title]" .
        "</a>";

    return $link;
}

# Return either:
#   - the index|value of the _COOKIE value,
#   - the index|value of the _GET value
#   - or lastly, the "starred" default value
#
# Argument could be a bool, scalar, or array
function auto_fill($entries, $lastval, $cookieval) {

    # Checkbox
    if (is_bool($entries)) {
        if ($cookieval == 'on')
            $ret = 'checked';
        elseif ($lastval == 'on')
            $ret = 'checked';
        else
            $ret = null;

    # Text
    } elseif (is_scalar($entries)) {
        if ($cookieval)
            $ret = $cookieval;
        elseif ($lastval)
            $ret = $lastval;
        else
            $ret = $entries;

    # Dropdown menu
    } elseif (is_array($entries)) {

        if ($cookieval)
            $match = "^.?$cookieval$";
        elseif ($lastval)
            $match = "^.?$lastval$";
        else
            $match = '^\*';

        $i = 0;
        foreach ($entries as $v) {
            if (preg_match("/$match/", $v))
                $ret = array($i => 'selected');
            $i++;
        }
    }

    return $ret;
}

function strip_star($str) {
    return preg_replace('/^\*/', '', $str);
}

#########################################

# Carry over input params (that are not submitted via form
# controls) between invocations of the script. Note:
# this string must be printed between the <form> tags
function hidden_carryover($params) {

    $lastgo = $params['go'];

    # Non-form fields that need to persist
    $fields = array_merge(
                array_keys(developer_params()),
                array(
                    'ttable_id',
                    'test_result',
                    'phase',
                )
    );

    # printf format for 'hidden' tags
    $format = "\n<input type='hidden' name='%s' value='%s'>";

    foreach (array_keys($params) as $k) {
        if (preg_match('/' . join('|', $fields) . '/', $k))
            $str .= sprintf($format, $k, $params[$k]);
    }

    static $advanced_fields;
    if (! $advanced_fields) {
        $col_types = array('text_', 'show_');

        $setup_advanced = setup_advanced($_GET);
        foreach (array_keys($setup_advanced) as $table) {
            foreach (array_keys($setup_advanced[$table]) as $field) {
                $arr = $setup_advanced[$table][$field];

                foreach (array_keys($arr) as $i) {
                    $type = $col_types[$i];
                    $advanced_fields[] = "$type$field";
                }
            }
        }
    }

    # Define the fields in the Show/Hide columns popup
    # so they will be defined for the javascript export
    foreach ($advanced_fields as $k) {
        $str .= sprintf($format, $k, $params[$k]);
    }

    if (TRIAL)
        $str .= 
            "\n<input " . 
                    "type='hidden' " . 
                    "name='text_trial' " . 
                    "value='" . $params['text_trial'] . "'>";

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
        tmp.write('<body ' + style + '><form id=adv name=adv method=get>' + content + '</form></body></html>');
        tmp.close();
    }

    function popup_text(width,height,content) {

        newwindow2=window.open('','name','height=' + height + ',width=' + width + ',scrollbars=yes');
        var tmp = newwindow2.document;
        tmp.write(content);
        tmp.close();
    }

    function littleWindow(link) {
        open(link, 'Tiny link', 'resizable=yes, toolbar=no, location=no, directories=no, status=no, menubar=no, scrollbars=no, width=180, height=70');
    }

EOT;

    # Create a JavaScript function to set all the
    # main window form fields to their defaults
    $phases = process_phase_field($_GET);
    $main_window = setup_mainwin_fields($phases);

    $javascript .= <<<EOT
    function StartOver() {
EOT;

    foreach (array_keys($main_window) as $field) {
        $value = $main_window[$field];

        $javascript .= <<<EOT
        document.report.text_$field.value = '$value';
EOT;
    }

    $javascript .= <<<EOT
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
