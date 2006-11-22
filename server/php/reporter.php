<html>
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
# Web-based Open MPI Tests Querying Tool -
#   This tool is for drill-downs.
#   For the one-size-fits-all report, see summary.php.
#
#

# Set debug levels
if (isset($_GET['verbose']) or isset($_GET['debug'])) {
    $GLOBALS['verbose'] = 1;
    $GLOBALS['debug']   = 1;
    $_GET['cgi']        = 'on';
    $_GET['sql']        = 'on';
} else {
    $GLOBALS['verbose'] = 0;
    $GLOBALS['debug']   = 0;
}

# Set php trace levels
if ($GLOBALS['verbose'])
    error_reporting(E_ALL);
else
    error_reporting(E_ERROR | E_WARNING | E_PARSE);

$topdir = ".";
include_once("/l/osl/www/doc/www.open-mpi.org/dbpassword.inc");
include_once("$topdir/reporter.inc");
include_once("$topdir/screen.inc");
include_once("$topdir/report.inc");

# In case we're using this script from the command-line
if ($argv)
    $_GET = getoptions($argv);

dump_query_screen();

if (isset($_GET['go']))
    print dump_report();

exit;

?>
</body>
</html>
