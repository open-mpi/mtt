#! /usr/bin/php


<?php

#
# Copyright (c) 2006 Sun Microsystems, Inc.
#                          All rights reserved.
# 
# Email reporter -
#   (Set this script up as a cron job)
#

$topdir = ".";
include_once("$topdir/curl_get.inc");
include_once("$topdir/ini.inc");
include_once("$topdir/reporter.inc");

$options = getopt("f:dv");

$GLOBALS['verbose'] = isset($options['v']) ? true : false;
$GLOBALS['debug']   = isset($options['d']) ? true : false;

# Set php trace levels
if ($GLOBALS['verbose'])
    error_reporting(E_ALL);
else
    error_reporting(E_ERROR | E_WARNING | E_PARSE);

# Parse with sections
$ini_file = ($options['f'] ? $options['f'] : "alerts.ini");
$ini      = parse_ini_file($ini_file, true);

print "\nCreating reports specified in $ini_file.";

# Reference:
#   http://www.zend.com/zend/trick/html-email.php

$headers  = "From: mtt-results\r\n";
$headers .= "MIME-Version: 1.0\r\n";
$boundary = uniqid("MTTREPORT");
$headers .= "Content-Type: multipart/alternative" .
            "; boundary = $boundary\r\n\r\n";
$headers .= "This is a MIME encoded message.\r\n\r\n";
# $headers .= "--$boundary\r\n" .
#             "Content-Type: text/plain; charset=ISO-8859-1\r\n" .
#             "Content-Transfer-Encoding: base64\r\n\r\n";
# $headers .= chunk_split(base64_encode(
#             "A plain text version of the Nightly MTT Test Results " .
#             "is not yet available. Sorry."));
$headers .= "--$boundary\r\n" .
            "Content-Type: text/html; charset=ISO-8859-1\r\n" .
            "Content-Transfer-Encoding: base64\r\n\r\n";

foreach (array_keys($ini) as $section) {

    $urls         = array();
    $urls         = preg_split("/\s*url=\s*/", $ini[$section]['url']);
    $email        = $ini[$section]['email'];
    #$frequency    = $ini[$section]['frequency'];
    #$last_alerted = $ini[$section]['last_alerted'];

    $html = "";
    foreach ($urls as $url)
        $html .= do_curl_get($url);


    print "\nGenerating report for [$section].";

    if (! contains_null_result_msg($html)) {
        $report = chunk_split(base64_encode($html));
        mail($email, $section, '', $headers . $report);
    }
    else
        print "\nNull report for [$section], not mailing.";

    if ($report)
        $ini[$section]['last_alerted'] = time();
}

#write_ini_file($ini_file, $ini);

print "\n";

exit;

function contains_null_result_msg($str) {
    return preg_match("/no data available for the specified query/i", $str);
}

?>
