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
include_once("$topdir/http.inc");
include_once("$topdir/html.inc");

# Start page menu

$http_username =
        isset($_SERVER['PHP_AUTH_USER']) ?
        $_SERVER['PHP_AUTH_USER'] : "";

$main_menu = array(
    "start_timestamp"   => "since yesterday",
    "http_username"     => $http_username,
    "local_username"    => "all",
    "hostname"          => "all",
    "phase"             => "all",
    "mpi_name"          => "all",
    "test_result"       => "all",
    "mpi_version"       => "all",
    "platform_hardware" => "all",
    "os_name"           => "all",
);

# HTML input elements
$main_textfields = ""; 
$pulldowns      = ""; 
$advanced       = ""; 
$filters        = ""; 


# Because the CGI array will not be 2D, we have to do a makeshift 2D array by prefixing
# CGI names with things like "field_" or "mainfield_"

# Generate Main Menu

$main_textfields .= "\n\n<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";

$i = 0;
$cols = 2;
foreach (array_keys($main_menu) as $field) {

    $main_textfields .= "\n" . ((($i++ % $cols) == 0) ? "\n<tr colspan=$cols>" : "") .
                        "\n<td bgcolor=$lgray>$field:" .
                        "\n<td bgcolor=$lgray><input type='textfield' value='$main_menu[$field]'>";
}
$main_textfields .= "\n</table>";

# Generate pulldowns table

# $pulldowns .= "\n\n<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";
# $pulldowns .= "\n<tr bgcolor=$gray>";
# $pulldowns .= "\n<th colspan=3>Selections <tr>";
# $pulldowns .= repeat("\n<th bgcolor='$gray'>Field <th bgcolor='$gray'>Menu <th bgcolor='$gray'>" .
#                 # "<a href=' " .
#                 #     "\njavascript:toggle_checkboxes" .
#                 #         "( " . join(",", lsprintf_('"%s"', prefix("agg_", array_keys($menu)))) . ")' " .
#                 # "class='lgray_ln'>" .
#                 "Aggregate" .
#                 # "</a>" .
#                 "",
#               $cols);
# 
# $i = 0;
# foreach (array_keys($menu) as $field) {
# 
#     $pulldowns .= "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
#         "\n<td bgcolor=$lgray><font>$field_labels[$field]:" .
#         "\n<td><select name='" . $cgi_abbrevs['menufield'] . "$field'>";
# 
#     $starred = false;
#     foreach (array_merge(array($All), $menu[$field]) as $item) {
# 
#         # X: functionalize the whole 'default selection' thing
#         $starred = (preg_match('/^\*/',$item) ? true : false);
#         $item = preg_replace("/^\*/i",'',$item);
#         $pulldowns .= "\n<option " .
#                         ($starred ? "selected" : "") .
#                         " style='width: $menu_width;' value='$item'>$item";
#     }
#     $pulldowns .= "\n</select>";
# 
#     # check the first three by default
#     $pulldowns .= "\n<td><input type='checkbox' name='agg_$field' id='agg_$field' " .
#                     (($i > 3) ? "checked" : " ") . ">";
# }
# $pulldowns .= "\n</table>";
# 
# # X: Merge the following two foreach loops
# 
# # Generate advanced textfield filters (this should be thought of as a
# # logical extension of the $filters panel)
# 
# $advanced .= "\n\n<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";
# $advanced .= "\n<tr bgcolor=$gray>";
# $advanced .= "\n<th colspan=3>Advanced <tr>";
# $advanced .= repeat("\n<th bgcolor='$gray'>Field <th bgcolor='$gray'>Text <th bgcolor='$gray'>", $cols);
# 
# $i = 0;
# foreach (array("advanced") as $t) {
#     foreach (array_keys($columns[$t]) as $textfield) {
# 
#         $advanced .= "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
#                     "\n<td bgcolor=$lgray><font>".
#                     ($field_labels[$textfield] ? $field_labels[$textfield] : $textfield) . ":" .
#                     "\n<td><input type='textfield' name='" . $cgi_abbrevs['textfield'] . "$textfield'>" .
#                     "\n<td><select name='" . $cgi_abbrevs['filter_types'] . "$textfield'>";
# 
#         foreach ($columns[$t][$textfield] as $filter_type) {
#             $advanced .= sprintf("\n<option>%s</option>", $filter_type);
#         }
#         $advanced .= "\n</select>";
#     }
# }
# 
# $advanced .= "\n<tr>";
# $advanced .= "\n<td bgcolor=$gray align=center colspan=3><input type='submit' value='Save'>";
# $advanced .= "\n</table>";
# 
# # Generate textfield filters
# 
# $filters .= "\n\n<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";
# $filters .= "\n<tr bgcolor=$gray>";
# $filters .= "\n<th colspan=3>$Filters ";
# 
# # X: Need to create javascript import/export functions to get this working
# # $filters .= "\n<a href='javascript:popup(\"900\",\"750\",\"Advanced $Filters\",\"" .
# #              strip_quotes($advanced) .
# #              "\",\"\")' class='lgray_ln'>[+]</a>";
# 
# $filters .= "\n<tr>";
# $filters .= repeat("\n<th bgcolor='$gray'>Field <th bgcolor='$gray'>Text <th bgcolor='$gray'>", $cols);
# 
# $i = 0;
# foreach (array_keys($textfield_tables) as $t) {
# 
#     $divider = $textfield_tables[$t]["label"];
#     $filters .= $divider ? "\n<tr><th colspan=3 bgcolor=$gray align='center'>$divider" : "";
# 
#     foreach (array_keys($columns[$t]) as $textfield) {
#         $filters .= "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
#                     "\n<td bgcolor=$lgray><font>" .
#                     ($field_labels[$textfield] ? $field_labels[$textfield] : $textfield) . ":" .
#                     "\n<td><input type='textfield' name='" . $cgi_abbrevs['textfield'] . "$textfield'>" .
#                     "\n<td><select name='" . $cgi_abbrevs['filter_types'] . "$textfield'>";
# 
#         foreach ($columns[$t][$textfield] as $filter_type) {
#             $filters .= sprintf("\n<option " .
#                         "style='width: $ft_menu_width;' " .
#                         ">%s</option>", $filter_type);
#         }
#         $filters .= "\n</select>" .  "";
#     }
# }
# $filters .= "\n</table>";

# Other settings

# $other .= "\n<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";
# $other .= "\n<tr bgcolor=$gray>";
# $other .= "\n<th colspan=3>Settings ";
# $other .= "\n<tr><td bgcolor=$lgray>Count";
# 
# $starred = false;
# foreach (array_keys($by_atoms) as $by_atom) {
# 
#     $starred = (preg_match('/^\*/', $by_atom) ? true : false);
# 
#     $other .= "\n<td><input type='radio' name='by_atom' value='" . $by_atom . "' " .
#                ($starred ? " checked " : "") .  ">" .
#               "<font>$by_atoms[$by_atom]" .
#               "";
# }
# $other .= "\n<tr><td bgcolor=$lgray>Display";
# $other .= "\n<td colspan=2><input type='checkbox' name='sql'>SQL$sp";
# $other .= "\n<input type='checkbox' name='cgi'>CGI$sp";
# # $other .= "\n<input type='checkbox' " .
# #           #"\nchecked " .
# #           "\nname='1-page'>1-page$sp";
# $other .= "\n</table>";

# --- Print it all

# html body
$query_screen .= "\n";
$query_screen .= "\n<body>";

$query_screen .= "\n <div align=left>";
$query_screen .= "\n <table width=80% align=center border=1 cellspacing=1 cellpadding=5>";
$query_screen .= "\n   <form name=$form_id target=_report>";
$query_screen .= "\n   <tr><td>";
$query_screen .= "\n   $main_textfields";
$query_screen .= "\n   <tr>";
$query_screen .= "\n   <td align=center bgcolor=$lgray><input type='submit' value='Report'>";
$query_screen .= "\n   </form>";
$query_screen .= "\n </table>";
$query_screen .= "\n </div>";

$query_screen .= carryover_cgi_params($_GET);

list($width, $height, $type, $attr) = getimagesize($mpi_logo_path);


function dump_query_screen() {
    global $query_screen;
    # $data = array();
    # $data = get_menus_info();
    # var_dump_html('$data = ', $data);

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

function get_menus_info() {

    debug("\nGetting menus info");

    $tables = array(
        "compute_cluster",
        "submit",
        "mpi_get",
        "compiler",
        "mpi_install",
        "test_build",
        "test_run",
        # "results",
        # "latency_bandwidth",
        # "alerts",
        # "users",
        # "failure",
        # "cluster_owner",
    );


    # Gather what is in the database

    $data = array();
    $tmp = array();
    foreach ($tables as $table) {
        $tmp = get_table_fields($table);
        $data[$table] = $tmp["column_name"];
    }
    var_dump_html('325 $data = ', $data);
    foreach ($tables as $table) {
        foreach ($data[$table] as $column) {
            $cmd = "SELECT $column FROM $table GROUP BY $column";
            $data[$table][$column] = simple_select($cmd);
        }
    }
    var_dump_html('332 $data = ', $data);
}

?>
