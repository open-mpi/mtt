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
include_once("$topdir/database.inc");

# In case we're using this script from the command-line
if ($argv)
    $_GET = getoptions($argv);

# Create or redirect to a permalink
$do_redir = $_GET['do_redir'];
$make_redir = $_GET['make_redir'];
if (! is_null($do_redir))
    do_redir($do_redir);
elseif (! is_null($make_redir))
    make_redir($_GET);

dump_query_screen();

if (isset($_GET['go']))
    print dump_report();

exit;

# Create a tiny URL permalink (using the current URL), and exit
function make_redir($params) {

    unset($params["make_redir"]);
    unset($params["do_redir"]);

    $qstring = arr2qstring($params);

    $domain = $_SERVER['SERVER_NAME'];
    $script = $_SERVER['SCRIPT_NAME'];
    $url    = "http://$domain$script?$qstring";

    # Create tiny URLs for the permalinks
    $query = "SELECT permalink_id FROM permalinks WHERE permalink = '$url'";
    $id = select_scalar($query);

    if (is_null($id)) {
        $query = "SELECT nextval('permalinks_permalink_id_seq')";
        $id = select_scalar($query);
        $insert = 
            "INSERT INTO " .
                "permalinks (permalink_id, permalink) " . 
                "VALUES ('$id', '$url');";
        do_pg_query($insert);
    }

    # Print tiny link in a tiny window
    print "<html>" . 
          html_head("Tiny link") .
          "<body>" .
          "<table><tr><td>" .
          "<a class='black_ln' href='http://$domain$script?do_redir=$id'>Tiny link</a>" .
          "</table>" .
          "</body>" .
          "</html>";
    exit;
}

# Redirect the browser to the permalink shortcut
function do_redir($id) {
    $query = "SELECT permalink FROM permalinks WHERE permalink_id = '$id'";
    $url = select_scalar($query);
    header("Location: $url");
    exit;
}

?>
