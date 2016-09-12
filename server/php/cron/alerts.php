#! /usr/bin/php


<?php

#
# Copyright (c) 2006-2007 Sun Microsystems, Inc.
#                          All rights reserved.
# Copyright (c) 2011      Oak Ridge National Laboratory. All rights reserved.
# 
# Email reporter -
#   (Set this script up as a cron job)
#
# To Run:
#  ./alerts.php -f evening.ini

#
# Parse command line options
#
$options = getopt("f:dv");

$GLOBALS['verbose'] = isset($options['v']) ? true : false;
$GLOBALS['debug']   = isset($options['d']) ? true : false;

#
# Sanity Check: Must supply -f option
#
if( !$options['f'] ) {
    print "Error: Must supply an ini file after the -f option\n";
    exit;
}

# Set php trace levels
if ($GLOBALS['verbose']) {
    error_reporting(E_ALL);
} else {
    error_reporting(E_ERROR | E_WARNING | E_PARSE);
}

#
# Includes
#
$topdir = "/l/osl/www/mtt.open-mpi.org/mtt/server/php";
include_once("$topdir/curl_get.inc");
include_once("$topdir/ini.inc");
include_once("$topdir/reporter/reporter.inc");

date_default_timezone_set('America/New_York');

#
# Parse with sections
#
$ini_file = $options['f'];

$ini      = parse_ini_file($ini_file, true);

print "\nCreating reports specified in $ini_file.";

# Reference:
#   http://www.zend.com/zend/trick/html-email.php

$headers  = "From: mtt-results@lists.open-mpi.org\r\n";
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
    foreach ($urls as $url) {
        $html .= do_curl_get($url);
    }

    print "\nGenerating report for [$section].";

    # If the HTML content returned is "1", then
    # something bad has happened
    if (1 == $html) {
        print "\ncurl error for [$section], possibly due to a PHP memory size overload.";
    }
    # Look for the "no data available" message,
    # if we can not find it - send the email
    elseif (! contains_null_result_msg($html)) {
        $report = chunk_split(base64_encode($html));
        mail($email, $section, '', $headers . $report);
    }
    # Do not email a blank report
    else {
        print "\nNull report for [$section], not mailing.";
    }

    if ($report) {
        $ini[$section]['last_alerted'] = time();
    }
}

#write_ini_file($ini_file, $ini);

print "\n";

exit;

function contains_null_result_msg($str) {
    return preg_match("/no data available for the specified query/i", $str);
}

?>
