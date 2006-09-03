<!--

 Copyright (c) 2006 Sun Microsystems, Inc.
                         All rights reserved.
 $COPYRIGHT$

 Additional copyrights may follow

 $HEADER$

-->

<?php

#
#
# The query screen generator
#
#

$topdir = ".";
include_once("$topdir/reporter.inc");
include_once("$topdir/database.inc");
include_once("$topdir/http.inc");
include_once("$topdir/html.inc");

$tables = array(
    "once",
    "general_a",
    "general_b",
);

$Filters = "Filters";

$textfield_tables = array(
    "general_a" => array( "label" => null,
                          "phases" => array( "runs","builds","installs" ),
                   ),
    "runs"      => array( "label" => "Test Run $Filters",
                          "phases" => array( "runs" ),
                   ),
    "general_b" => array( "label" => "MPI Install/Test Build $Filters",
                          "phases" => array( "builds","installs" ),
                   ),
);

$once_tables = array(
    "once",
);

$columns = array();

$string_filter_types = array("contains","does not contain", "begins with", "ends with");
$numeric_filter_types = array("equals","less than","greater than");

# We'll define these fields instead of fetch from information_schema
# so that we can order them how we want
#
# Q: What's with general_a and general_b?
# A: The db tables are factored down such that if a column needs to be altered
#    it can be done to a single column, not a column in multiple tables
$columns["general_a"] = array(
    "stderr"                   => $string_filter_types,
    "stdout"                   => $string_filter_types,
    "environment"              => $string_filter_types,
    "configure_arguments"      => $string_filter_types,
    "result_message"           => $string_filter_types,
    "mpi_get_section_name"     => $string_filter_types,
    "mpi_install_section_name" => $string_filter_types,
    #"vpath_mode"              => $string_filter_types,
    #"start_test_timestamp"    => $string_filter_types,
    #"submit_test_timestamp"   => $string_filter_types,
    #"test_duration_interval"  => $string_filter_types,
    #"merge_stdout_stderr"     => $string_filter_types,
    #"mpi_details"             => $string_filter_types,
);
$columns["general_b"] = array(
    "compiler_name"    => $string_filter_types,
    "compiler_version" => $string_filter_types,
);

$columns["advanced"] = array(
    "mpi_details"               => $string_filter_types,
    "merge_stdout_stderr"       => $string_filter_types,
    "vpath_mode"                => $string_filter_types,
    "start_test_timestamp"      => $string_filter_types,
    "submit_test_timestamp"     => $string_filter_types,
    "test_duration_interval"    => $string_filter_types,
    #"result_message"           => $string_filter_types,
    #"environment"              => $string_filter_types,
    #"configure_arguments"      => $string_filter_types,
    #"mpi_get_section_name"     => $string_filter_types,
    #"mpi_install_section_name" => $string_filter_types,
);

$columns['once'] = array(
    "platform_hardware" => $string_filter_types,
    "os_name"           => $string_filter_types,
    "os_version"        => $string_filter_types,
    "mpi_name"          => $string_filter_types,
    "mpi_version"       => $string_filter_types,

    "$cluster_field"    => $string_filter_types,

    #"hostname"         => $string_filter_types,
    #"platform_type"    => $string_filter_types,
    #"platform_id"      => $string_filter_types,
);

$columns["runs"] = array(
    "test_name"               => $string_filter_types,
    "test_command"            => $string_filter_types,
    "test_np"                 => $numeric_filter_types,
    "test_build_section_name" => $string_filter_types,
    "test_run_section_name"   => $string_filter_types,
);

$columns["installs"] = 
    $columns["general_b"];
$columns["builds"] = array_merge(
    array("test_build_section_name" => $string_filter_types),
    array($columns["general_b"])
);

# Gather selectable menu items

# Global timestamp
# X: To avoid conflicting with a 'by_run' query, we use _test_timestamp
#    and not run_timestamp. We may want to allow for either.
$timestamp = 'start_test_timestamp';
$main_menu[$timestamp]["options"] = array(
    "*Today",
    "Since Yesterday",
);

$i = 0;
foreach (array_keys($words_to_numerals) as $n) {
    if ($i++ > 5)
        break;
    array_push($main_menu[$timestamp]["options"], "Past $n Days");
}
$i = 0;
foreach (array_keys($words_to_numerals) as $n) {
    if ($i++ > 5)
        break;
    array_push($main_menu[$timestamp]["options"], "Past $n Weeks");
}
$i = 0;
foreach (array_keys($words_to_numerals) as $n) {
    if ($i++ > 4)
        break;
    array_push($main_menu[$timestamp]["options"], "Past $n Months");
}
array_push($main_menu[$timestamp]["options"], $All);

# Timestamp is an oddball field, in that it has more than one
# way to aggregate
# X: Add week-by-week, month-by-month
$agg_timestamp_selects = array(
    "*-"               => null,
    "Month-by-Month"   => "substring($timestamp from 0 for 8) as $timestamp",
    "Day-by-Day"       => "substring($timestamp from 0 for 11) as $timestamp",
    "Hour-by-Hour"     => "substring($timestamp from 0 for 14) || ':00' as $timestamp",
    "Minute-by-Minute" => "substring($timestamp from 0 for 17) as $timestamp",
    "Second-by-Second" => $timestamp,
);

$main_menu["agg_timestamp"]["options"] = array_keys($agg_timestamp_selects);

# Note: 'phase' is a special key in that it is not a field in the db
$main_menu["phase"]["options"] = array(
    $All,
    "installs",
    "builds",
    "runs",
);

# X: This javascript is *broken* due to undefined tf_0 and ft_0 fields
# X: Loop through elems in HTML 'name' attribute, instead of this absurd
#    get_phase_specific_fields function
#
# Add some javascript actions for this menu (gray out appropriate
# phase-specific fields)
$main_menu["phase"]["javascript"] = array(
    # $All
    "enable(" . join(",", get_phase_specific_fields(array("installs","builds","runs"))) . ");",
    # installs
    "disable(" . join(",", get_phase_specific_fields(array("runs"))) . ");" .
    "enable(" . join(",", get_phase_specific_fields(array("installs"))) . ");",
    # builds
    "disable(" . join(",", get_phase_specific_fields(array("runs"))) . ");" .
    "enable(" . join(",", get_phase_specific_fields(array("builds"))) . ");",
    # runs
    "disable(" . join(",", get_phase_specific_fields(array("installs","builds"))) . ");" .
    "enable(" . join(",", get_phase_specific_fields(array("runs"))) . ");",
);

$main_menu["success"]["options"] = array(
    $All,
    "Pass",
    "Fail",
);

if (! ($conn = pg_connect("host=localhost port=5432 dbname=$dbname user=$user password=$pass")))
    exit_("<br><b><i>Could not connect to database server.</i></b>");

$menu = array();
$menu = populate_menu(array_keys($columns["once"]), "once");

pg_close();

# This field is absurd, and only so summary.php can use it
# X: Put this in an advanced window someday
$hidden_menu = array(
    "test_build_section_name",
    "test_run_section_name",
);

$by_atoms = array(
    "*by_test_case" => "By test case",
    "by_test_run" => "By test run",
);

$domain  = "http://www.open-mpi.org";

$client = "MTT";

# HTML input elements
$main_pulldowns = ""; 
$pulldowns      = ""; 
$hiddens        = ""; 
$advanced       = ""; 
$filters        = ""; 

$cols = 1;

# Because the CGI array will not be 2D, we have to do a makeshift 2D array by prefixing
# CGI names with things like "field_" or "mainfield_"

# Generate Main Menu

$main_pulldowns .= "\n\n<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";
$main_pulldowns .= "\n<tr bgcolor=$gray>";
$main_pulldowns .= "\n<th colspan=2>Main Menu <tr>";
$main_pulldowns .= repeat("\n<th bgcolor='$gray'>Field <th bgcolor='$gray'>Menu", $cols);

$i = 0;
foreach (array_keys($main_menu) as $field) {

    $main_pulldowns .= "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
        "\n<td bgcolor=$lgray><font>$field_labels[$field]:" .
        "\n<td><select name='" . $cgi_abbrevs['mainfield'] . "$field'>";

    $j = 0;
    $starred = false;
    foreach ($main_menu[$field]["options"] as $item) {
        $starred = (preg_match('/^\*/',$item) ? true : false);
        $item = preg_replace("/^\*/i",'',$item);
        $main_pulldowns .= "\n<option " .
                        ($starred ? " selected " : "") .
                        "style='width: $menu_width;' value='$item' " .
                        (isset($main_menu[$field]["javascript"][$j]) ?
                            "onclick='javascript:" . $main_menu[$field]["javascript"][$j] . "'" :
                            "") .
                        ">" .

                        # Note: phases is the only labeled mainfield
                        ($phase_labels[$item] ? $phase_labels[$item] : $item);

        $j++;

    }

    $main_pulldowns .= "\n</select>";
}
$main_pulldowns .= "\n</table>";

# Generate pulldowns table

$pulldowns .= "\n\n<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";
$pulldowns .= "\n<tr bgcolor=$gray>";
$pulldowns .= "\n<th colspan=3>Selections <tr>";
$pulldowns .= repeat("\n<th bgcolor='$gray'>Field <th bgcolor='$gray'>Menu <th bgcolor='$gray'>" .
                # "<a href=' " .
                #     "\njavascript:toggle_checkboxes" .
                #         "( " . join(",", lsprintf_('"%s"', prefix("agg_", array_keys($menu)))) . ")' " .
                # "class='lgray_ln'>" .
                "Aggregate" .
                # "</a>" .
                "",
              $cols);

$i = 0;
foreach (array_keys($menu) as $field) {

    $pulldowns .= "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
        "\n<td bgcolor=$lgray><font>$field_labels[$field]:" .
        "\n<td><select name='" . $cgi_abbrevs['menufield'] . "$field'>";

    $starred = false;
    foreach (array_merge(array($All), $menu[$field]) as $item) {

        # X: functionalize the whole 'default selection' thing
        $starred = (preg_match('/^\*/',$item) ? true : false);
        $item = preg_replace("/^\*/i",'',$item);
        $pulldowns .= "\n<option " .
                        ($starred ? "selected" : "") .
                        " style='width: $menu_width;' value='$item'>$item";
    }
    $pulldowns .= "\n</select>";

    # check the first three by default
    $pulldowns .= "\n<td><input type='checkbox' name='agg_$field' id='agg_$field' " .
                    (($i > 3) ? "checked" : " ") . ">";
}
$pulldowns .= "\n</table>";

$i = 0;
# Some hidden menus, to be used by summary.php
foreach ($hidden_menu as $field) {

    # X: hidden is only a 1d array, make it 2d using populate_menu
    foreach (array_merge(array($All), $hidden_menu[$field]) as $item) {
        $hiddens .= "\n<input type='hidden' name='" . $cgi_abbrevs['hidden_menufield'] . $field .  "' " .
        "value=''>";     # only a knowledgeable script can supply this param with a value
    }
    $hiddens .= "\n<input type='hidden' name='agg_$field' value='off'>";
}

# X: Merge the following two foreach loops

# Generate advanced textfield filters (this should be thought of as a
# logical extension of the $filters panel)

$advanced .= "\n\n<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";
$advanced .= "\n<tr bgcolor=$gray>";
$advanced .= "\n<th colspan=3>Advanced <tr>";
$advanced .= repeat("\n<th bgcolor='$gray'>Field <th bgcolor='$gray'>Text <th bgcolor='$gray'>", $cols);

$i = 0;
foreach (array("advanced") as $t) {
    foreach (array_keys($columns[$t]) as $textfield) {

        $advanced .= "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
                    "\n<td bgcolor=$lgray><font>".
                    ($field_labels[$textfield] ? $field_labels[$textfield] : $textfield) . ":" .
                    "\n<td><input type='textfield' name='" . $cgi_abbrevs['textfield'] . "$textfield'>" .
                    "\n<td><select name='" . $cgi_abbrevs['filter_types'] . "$textfield'>";

        foreach ($columns[$t][$textfield] as $filter_type) {
            $advanced .= sprintf("\n<option>%s</option>", $filter_type);
        }
        $advanced .= "\n</select>";
    }
}

$advanced .= "\n<tr>";
$advanced .= "\n<td bgcolor=$gray align=center colspan=3><input type='submit' value='Save'>";
$advanced .= "\n</table>";

# Generate textfield filters

$filters .= "\n\n<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";
$filters .= "\n<tr bgcolor=$gray>";
$filters .= "\n<th colspan=3>$Filters ";

# X: Need to create javascript import/export functions to get this working
# $filters .= "\n<a href='javascript:popup(\"900\",\"750\",\"Advanced $Filters\",\"" .
#              strip_quotes($advanced) .
#              "\",\"\")' class='lgray_ln'>[+]</a>";

$filters .= "\n<tr>";
$filters .= repeat("\n<th bgcolor='$gray'>Field <th bgcolor='$gray'>Text <th bgcolor='$gray'>", $cols);

$i = 0;
foreach (array_keys($textfield_tables) as $t) {

    $divider = $textfield_tables[$t]["label"];
    $filters .= $divider ? "\n<tr><th colspan=3 bgcolor=$gray align='center'>$divider" : "";

    foreach (array_keys($columns[$t]) as $textfield) {
        $filters .= "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
                    "\n<td bgcolor=$lgray><font>" .
                    ($field_labels[$textfield] ? $field_labels[$textfield] : $textfield) . ":" .
                    "\n<td><input type='textfield' name='" . $cgi_abbrevs['textfield'] . "$textfield'>" .
                    "\n<td><select name='" . $cgi_abbrevs['filter_types'] . "$textfield'>";

        foreach ($columns[$t][$textfield] as $filter_type) {
            $filters .= sprintf("\n<option " .
                        "style='width: $ft_menu_width;' " .
                        ">%s</option>", $filter_type);
        }
        $filters .= "\n</select>" .  "";
    }
}
$filters .= "\n</table>";

# Other settings

$other .= "\n<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";
$other .= "\n<tr bgcolor=$gray>";
$other .= "\n<th colspan=3>Settings ";
$other .= "\n<tr><td bgcolor=$lgray>Count";

$starred = false;
foreach (array_keys($by_atoms) as $by_atom) {

    $starred = (preg_match('/^\*/', $by_atom) ? true : false);

    $other .= "\n<td><input type='radio' name='by_atom' value='" . $by_atom . "' " .
               ($starred ? " checked " : "") .  ">" .
              "<font>$by_atoms[$by_atom]" .
              "";
}
$other .= "\n<tr><td bgcolor=$lgray>Display";
$other .= "\n<td colspan=2><input type='checkbox' name='sql'>SQL$sp";
$other .= "\n<input type='checkbox' name='cgi'>CGI$sp";
# $other .= "\n<input type='checkbox' " .
#           #"\nchecked " .
#           "\nname='1-page'>1-page$sp";
$other .= "\n</table>";

# --- Print it all

# html body
$query_screen .= "\n";
$query_screen .= "\n<body>";

# 1-page option is initially spawning a new page, but shouldn't
$query_screen .= "\n<form name=$form_id target=" . (($_GET['1-page'] == 'on') ? "_self" : "_report") . ">";

$query_screen .= carryover_cgi_params($_GET);

$query_screen .= "\n<table align=center border=1 cellspacing=1 cellpadding=5 width=100%>";
$query_screen .= "\n<th align=center rowspan=4 bgcolor=$dgray><font size=24pt color=$lllgray>" .
                     "<a href='$domain' class='lgray_ln'>" .
                         "<img width=55 height=55 src='$topdir/images/open-mpi-logo.png'>" .
                     "</a><br>" .
                     "<img width=55 height=525 src='$topdir/images/reporter_logo.gif'>";
#$query_screen .= "\n<th align=center colspan=2 rowspan=1 bgcolor=$dgray><font size=24pt color=$lllgray>" .
#                 "\nOpen MPI $br Test $br Reporter";
$query_screen .= "\n<tr><td bgcolor=$lllgray valign=top>";
$query_screen .= "\n$main_pulldowns";
$query_screen .= "\n<td bgcolor=$lllgray rowspan=3 valign=top>";
$query_screen .= "\n$filters";
$query_screen .= "\n<tr><td bgcolor=$lllgray>";
$query_screen .= "\n$pulldowns";
$query_screen .= "\n$hiddens";
$query_screen .= "\n<tr><td bgcolor=$lllgray>";
$query_screen .= "\n$other";
$query_screen .= "\n<tr bgcolor=$gray>";
$query_screen .= "\n<td bgcolor=$gray colspan=3>";
$query_screen .= "\n<table align=center border=1 cellspacing=1 cellpadding=5>";
$query_screen .= "\n<tr>";
$query_screen .= "\n<td bgcolor=$lllgray valign=center><input type='submit' name='go' value='Table'>";
$query_screen .= "\n<td bgcolor=$lllgray valign=center><input type='reset' value='Reset'>";
$query_screen .= "\n<td bgcolor=$lgray valign=center>";
$query_screen .= "\n<a href='$topdir/html/reporter_help.html' class='lgray_ln' target=_blank>[Help]</a>";
#$query_screen .= "\n<td bgcolor=$lllgray valign=center><input type='submit' value='Graph'>";
$query_screen .= "\n</form>";
$query_screen .= "\n</table>";
$query_screen .= "\n</table>";
$query_screen .= "\n<br><br><br>";

function dump_query_screen() {
    global $query_screen;
    return $query_screen;
}

function populate_menu($list, $table) {

    global $conn;

    foreach ($list as $field) {

        if (preg_match("/timestamp/i", $field)) {
            $clause = "substring($field from 0 for 11) as $field";
        } else {
            $clause = $field;
        }

        if (isset($_GET['sql']))
            if ($_GET['sql'] == 'on')
                print("\n<br>SQL: <pre>" . html_to_txt($cmd) . "</pre>");

        $alias = get_as_alias($field);

        $cmd = "SELECT $clause FROM $table " .
            "GROUP BY $alias " .
            "ORDER BY $alias ;";

        $rows = array_map('html_to_txt2', pg_query_simple($cmd, $conn));

        $menu[$alias] = array();
        $menu[$alias] = $rows;
    }
    return $menu;
}

# prefix a list of strings with $str, and return the list
function prefix($prefix, $list) {

    $arr = array();

    foreach ($list as $elem) {
        array_push($arr, $prefix . $elem);
    }
    return $arr;
}


# Carry input params over between invocations of the script
function carryover_cgi_params($params) {

    foreach (array_keys($params) as $k) {
        if (! $params[$k])
            $str .= "\n<input type='hidden' name='$k' value='$params[$k]'>";
    }
    return $str;
}

?>
