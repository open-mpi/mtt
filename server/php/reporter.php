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
# Web-based Open MPI Tests Querying Tool -
#   This tool is for drill-downs.
#   For the one-size-fits-all report, see summary.php.
#
#

# Set php trace levels
if (isset($GLOBALS['verbose']))
    error_reporting(E_ALL);
else
    error_reporting(E_ERROR | E_WARNING | E_PARSE);

# X: which .inc's do we really need?
$topdir = ".";
include_once("$topdir/screen.inc");
include_once("$topdir/report.inc");
include_once("$topdir/head.inc");
include_once("$topdir/http.inc");
include_once("$topdir/html.inc");
include_once("$topdir/database.inc");
include_once("$topdir/reporter.inc");

$GLOBALS['verbose'] = isset($_GET['verbose']) ? $_GET['verbose'] : 0;
$GLOBALS['debug']   = isset($_GET['debug'])   ? $_GET['debug']   : 0;

# In case we're using this script from the command-line
if ($argv)
    $_GET = getoptions($argv);

$form_id = "report";

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

print $html_head;

$_GET['1-page'] = isset($_GET['1-page']) ? $_GET['1-page'] : 'off';

# If no parameter is passed in, show the query screen
if (((! isset($_GET['go'])) and ! isset($_GET['just_results'])) or
    ($_GET['1-page'] == 'on')) {

    print dump_query_screen();
}

if (isset($_GET['just_results'])) {
    print dump_results_only();
}
elseif (isset($_GET['go'])) {
    print dump_report();
}

exit;

?>
</body>
</html>
