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
# Email reporter -
#   (Set this script up as a cron job)
#

$topdir = ".";
include_once("$topdir/curl_get.inc");
include_once("$topdir/ini.inc");
include_once("$topdir/reporter.inc");
include_once("$topdir/html.inc");

# In case we are using this script from the command-line
if ($argv)
    $_GET = getoptions($argv);

$GLOBALS['verbose'] = isset($_GET['verbose']) ? $_GET['verbose'] : 0;
$GLOBALS['debug']   = isset($_GET['debug'])   ? $_GET['debug']   : 0;

# Parse with sections
$alerts_file = "alerts.ini";
$ini         = parse_ini_file($alerts_file, true);

debug($ini);

# Reference:
#   http://www.zend.com/zend/trick/html-email.php

$headers  = "From: mtt-results\r\n";
$headers .= "MIME-Version: 1.0\r\n";
$boundary = uniqid("MTTREPORT");
$headers .= "Content-Type: multipart/alternative" .
            "; boundary = $boundary\r\n\r\n";
$headers .= "This is a MIME encoded message.\r\n\r\n";
$headers .= "--$boundary\r\n" .
            "Content-Type: text/plain; charset=ISO-8859-1\r\n" .
            "Content-Transfer-Encoding: base64\r\n\r\n";
$headers .= chunk_split(base64_encode(
            "A plain text version of the Nightly MTT Test Results " .
            "is not yet available. Sorry."));
$headers .= "--$boundary\r\n" .
            "Content-Type: text/html; charset=ISO-8859-1\r\n" .
            "Content-Transfer-Encoding: base64\r\n\r\n";

foreach (array_keys($ini) as $section) {

    $url          = $ini[$section]['url'];
    $email        = $ini[$section]['email'];
    $frequency    = $ini[$section]['frequency'];
    $last_alerted = $ini[$section]['last_alerted'];
    $report       = chunk_split(base64_encode(do_curl_get($url)));

    mail($email, $section, '', $headers . $report);

    if ($report)
        $ini[$section]['last_alerted'] = time();
}

write_ini_file($alerts_file, $ini);

exit;

?>
