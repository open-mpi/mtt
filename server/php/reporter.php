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
# Web-based Open MPI Tests Querying Tool
#
#

# Deny mirrors access to MTT results
deny_mirror();

# 'debug' is an aggregate trace
if (isset($_GET['debug'])) {
    $_GET['verbose'] = 'on';
    $_GET['dev']     = 'on';
    $_GET['cgi']     = 'on';
}

# 'stats' and 'explain' would not make sense without 'sql'
if (isset($_GET['stats']) or 
    isset($_GET['explain']) or 
    isset($_GET['analyze'])) {
    $_GET['sql'] = '2';
}

# Set PHP trace levels
if (isset($_GET['verbose']))
    error_reporting(E_ALL);
else
    error_reporting(E_ERROR | E_PARSE);

# Includes
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

# Keep track of time
$start = time();

# Display a query screen and report
dump_report();

# Report on script's execution time
$finish = time();
$elapsed = $finish - $start;
print("\nTotal script execution time: " . $elapsed . " second(s)");

# Display input parameters
debug_cgi($_GET, "GET " . __LINE__);

# Display cookie parameters
debug_cgi($_COOKIE, "COOKIE " . __LINE__);

print hidden_carryover($_GET) .
      "\n<hr></form></body></html>";

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

    $tinyurl = "http://$domain$script?do_redir=$id";

    # Print tiny link in a tiny window
    print "<html>" . 
          html_head("Tiny link") .
          "<body>" .
          "<table><tr><td>" .
          "The original permalink was " . strlen($url) . " chars long. " .
          "Here's a <a class='black_ln' href='$tinyurl'>tiny link</a> " .
              "that is only " . strlen($tinyurl) . " chars long." .
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

# Deny mirrors access to MTT results
function deny_mirror() {

    $mother_site = "www.open-mpi.org";
    $server_dir = "/";

    # Are we the "mother site" or a mirror?
    if ($_SERVER["SERVER_NAME"] == $mother_site)
        $is_mirror = false;
    else
        $is_mirror = true;

    if ($is_mirror) {
        $equiv_dir = ereg_replace("^$server_dir", '', $_SERVER["REQUEST_URI"]);
        print "Sorry, this page is not mirrored.  " .
               "Please see the <a href=\"http://$mother_site/$equiv_dir\">" .
               "original version of this page</a> " .
               "on the main Open MPI web site.\n";
        exit();
    }
}

?>
