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
# Web-based Open MPI Tests Quick Links -
#
#

$topdir = ".";
include_once("$topdir/curl_get.inc");
include_once("$topdir/http.inc");
include_once("$topdir/html.inc");
include_once("$topdir/head.inc");
include_once("$topdir/reporter.inc");

# In case we're using this script from the command-line
if ($argv)
    $_GET = getoptions($argv);

$GLOBALS['verbose'] = isset($_GET['verbose']) ? $_GET['verbose'] : 0;
$GLOBALS['debug']   = isset($_GET['debug'])   ? $_GET['debug']   : 0;

# URL template to loop over
$s = "%s";
$template = "http://www.open-mpi.org/mtt/reporter.php?" .
    "&maf_start_test_timestamp=$s" . 
    "&by_atom=*by_test_case" . 
    "&ft_platform_id=contains" . 
    "&go=Table" . 
    "&maf_agg_timestamp=-" .
    "&maf_phase=$s" . 
    "&maf_success=All" . 
    "&mef_mpi_name=All" . 
    "&mef_mpi_version=All" . 
    "&mef_os_name=All" . 
    "&mef_os_version=All" . 
    "&mef_platform_hardware=All" . 
    "&mef_platform_id=All" . 
    "&tf_platform_id=$s" .
    "&agg_platform_id=off" .
    "";

$date_ranges = array(
    "Past 24 Hours",
    "Past 12 Hours",
    "Past 6 Hours",
    "Past 2 Hours",
);

$orgs = array(
    "IU"    => "IU",
    "Cisco" => "Cisco",
    "Sun"   => "Sun",
    "HLRS"  => "HLRS",
    ""      => "All",
);

$phases = array(
    "installs" => "MPI Installs",
    "builds"   => "Test Builds",
    "runs"     => "Test Runs",
    "All"      => "All",
);

# Display webpage title
$sp = '&nbsp;';
print <<<EOT
<html>

<head>
    <title>Open MPI Test Results Summary</title>
    <style type='text/css'>
    $style
    </style>
</head>

<body>
<center>
<table width='50%' rules='rows' border=2 cellpadding=10>
    <tr>
    <td align=center>
        <a href='.'><img src='$mpi_logo_path' height=40 width=40' border=0></a>
    <td align=center>
        <font size='+3'>Open&nbsp;MPI Test&nbsp;Results</font>
    <td align=center>
        <a href='.'><img src='$mpi_logo_path' height=40 width=40' border=0></a>
</table>
<br>
EOT;

# HTML elements
$table_tag = "<table width=100% align=center border=1 cellspacing=1 cellpadding=5>";
$th = "<th bgcolor=$lgray>";
$td = "<td bgcolor=$llgray>";

$i = 0;
$cols = 2;

print "\n\n$table_tag";

foreach ($date_ranges as $date_range) {
    print ((($i % $cols) == 0) ? "\n\n<tr>" : "");
    print "\n<td>";
    print "\n\t $table_tag" .
          "\n\t <th bgcolor=$lgray colspan=" .
            (sizeof($phases) + 1) . ">$date_range";

    foreach (array_keys($orgs) as $org) {
        print "\n\t\t <tr>$td" . $orgs[$org];

        foreach (array_keys($phases) as $phase) {

            # If these are re-ordered, do not forget to
            # reorder the %s's in $template
            $url = sprintf($template,
                             respace($date_range),
                             respace($phase),
                             respace($org)
                          );

            print "\n\t\t\t $td<a href=$url target=_report>$phases[$phase]</a>";
        }
    }
    print "\n\t</table>";
    $i++;
}
print "\n</table>\n\n";

# Link to other tools
print <<<EOT
<br>
<font size='-1'>See also: 
    <a href="./reporter.php">Custom Reports</a> and
    <a href="./summary.php">Summary Reports</a>
</font>
EOT;

# Turn whitespace into URL-ready whitespace
function respace($str) {
    $str = preg_replace("/\s+/",'+',$str);
    return $str;
}

?>
</body>
</html>
