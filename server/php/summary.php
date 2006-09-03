<!--

 Copyright (c) 2006 Sun Microsystems, Inc.
                         All rights reserved.
 $COPYRIGHT$

 Additional copyrights may follow

 $HEADER$

-->

<html>
<head>
    <title>Open MPI Test Results Summary</title>
</head>
<body>
<center>

<?php

#
#
# Web-based Open MPI Tests Summary Reporter -
#   For the drill-down reporter, see reporter.php
#
#

$topdir = ".";
include_once("$topdir/curl_get.inc");
include_once("$topdir/http.inc");
include_once("$topdir/reporter.inc");

# In case we're using this script from the command-line
if ($argv)
    $_GET = getoptions($argv);

$GLOBALS['verbose'] = isset($_GET['verbose']) ? $_GET['verbose'] : 0;
$GLOBALS['debug']   = isset($_GET['debug'])   ? $_GET['debug']   : 0;

$domain       = 'http://www.open-mpi.org';
$default_date = 'Yesterday';

$self = $_SERVER['PHP_SELF'];
$url  = preg_replace('/summary.php/', 'reporter.php', $self);
$url  = "$domain$url";

# Note: the ordering of this query string is irrelevant,
# but be careful to not put a '&' after the opening '?'
$url_template = $url .  '?' .

    # settings
    "&cgi=off" .
    "&go=Table" .
    "&just_results" .
    "&1-page=off" .

    # by atom
    "%s" .

    # aggregates
    "%s" .

    # selections
    "%s" .

    # phase
    "%s" .

    # menufields
    "%s" .

    # hiddens
    "%s" .

    # details
    "%s" .

    # mainfields
    "&" . $cgi_abbrevs["mainfield"] . "start_test_timestamp=" .
        (($_GET['date'] == 'week') ? 'Past Seven Days' : $default_date);


#################################
#                               #
#     Configuration             #
#                               #
#################################

# X: Slurp in $config from an XML file

$client = "MTT";
$config['label'] = array(
    "$client Executive Summary",
    "$client Cluster Summary",
    "$client Test Suites Summary",
    "$client Test Case Details",
);

$config['phase'] = array(
    "&" . $cgi_abbrevs["mainfield"] . "phase=All",
    "&" . $cgi_abbrevs["mainfield"] . "phase=All",
    "&" . $cgi_abbrevs["mainfield"] . "phase=runs",
    "&" . $cgi_abbrevs["mainfield"] . "phase=runs",
);

$config['aggs'] = array(
    
    "&" . $cgi_abbrevs["mainfield"] . "agg_timestamp=-" .
    "&agg_cluster=on" . 
    "&agg_mpi_name=on" . 
    "&agg_mpi_version=on" .
    "&agg_os_version=on" .
    "",

    "&" . $cgi_abbrevs["mainfield"] . "agg_timestamp=-" .
    "&agg_mpi_name=on" . 
    "&agg_mpi_version=on" .
    "&agg_os_version=on" .
    "",

    "&" . $cgi_abbrevs["mainfield"] . "agg_timestamp=Hour-by-Hour" .
    "&agg_test_name=on" .
    "&agg_test_np=on" .
    "&agg_os_version=on" .
    "&agg_compiler_name=on" .
    "&agg_compiler_version=on" .
    "",

    "&" . $cgi_abbrevs["mainfield"] . "agg_timestamp=Second-by-Second" .
    "",
);

$menufields =
    "&" . $cgi_abbrevs["menufield"] . "cluster=All" . 
    "&" . $cgi_abbrevs["menufield"] . "mpi_name=All" .
    "&" . $cgi_abbrevs["menufield"] . "mpi_version=All" .
    "&" . $cgi_abbrevs["menufield"] . "os_name=All" . 
    "&" . $cgi_abbrevs["menufield"] . "os_version=All" . 
    "&" . $cgi_abbrevs["menufield"] . "platform_hardware=All";

$config['menufields'] = array(
    $menufields,
    $menufields,
    $menufields,
    $menufields,
);

$config['hiddens'] = array(
    "",
    "",
    "&h" . $cgi_abbrevs["menufield"] . "test_run_section_name=All",
    "",
);

$config['by_atom'] = array(
    "&by_atom=by_test_run",
    "&by_atom=by_test_run",
    "&by_atom=by_test_case",
    "&by_atom=by_test_case",
);

$config['selections'] = array(
    "&" . $cgi_abbrevs["mainfield"] . "success=All",
    "&" . $cgi_abbrevs["mainfield"] . "success=All",
    "&" . $cgi_abbrevs["mainfield"] . "success=All",
    "&" . $cgi_abbrevs["mainfield"] . "success=Fail",
);

$config['details'] = array(
    "",
    "",
    "&no_details",
    "",
);

$config['description'] = array(
    "",
    "",
    "hour-by-hour",
    "just_failures, second-by-second",
);

# Display webpage title
$sp = '&nbsp;';
print <<<EOT
<center>
<table width='1%' rules='rows' border=2 cellpadding=10>
    <tr><td width='1%'>
        <a href='$domain/mtt'><img src='$topdir/images/open-mpi-logo.png' border=0></a>
    <td width='1%'>
        <font size='+7'>Open&nbsp;MPI Test&nbsp;Results</font>
        <br>
        <font size='-1'>Time frame: $default_date - Now</font><br>
        <font size='-1'>See also: <a href="./reporter.php">Open MPI Tests Reporter</a></font><br>
</table>
EOT;

# Loop through the stages of the config and print a report for each
for ($i = 0; $i < count($config['label']); $i++) {

    $url = sprintf($url_template, 
            $config["phase"][$i],
            $config["aggs"][$i],
            $config["by_atom"][$i],
            $config["selections"][$i],
            $config["hiddens"][$i],
            $config["menufields"][$i],
            $config["details"][$i]
    );

    $url = preg_replace("/ /", '%20', $url);

    print "\n<br><font size='+3'>";
    print "\n" . $config["label"][$i];
    print "\n</font>";

    print "\n<br><font size='-1'>";
    print "\n(" . get_query_string_param_value($config["by_atom"][$i]) . ")";
    print "\n</font>";

    if ($config["description"][$i]) {
        print "\n<br><font size='-1'>";
        print "\n<i>(" . $config["description"][$i] . ")</i>";
        print "\n</font>";
    }

    debug("\n<br>url: <a href='" . $url . "'>\$url</a><br>");

    print "\n<br><br><br>" . do_curl_get($url);
}

exit;

# Take "&param=val", return "val"
function get_query_string_param_value($str) {

    if (preg_match("/\w+=(\w+)/i", $str, $m)) {
        return $m[1];
    }
    else {
        return $str;
    }
}

function get_en_filter($str) {

    if (preg_match("/(\w+)=(\w+)/i", $str, $m)) {
        return "Displaying results where $m[1] = $m[2]";
    }
    else {
        return $str;
    }
}

?>
</body>
</html>
