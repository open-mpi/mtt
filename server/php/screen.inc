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

# HTML input elements
$main_pulldowns = ""; 
$pulldowns      = ""; 
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
