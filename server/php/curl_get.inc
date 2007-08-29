<?php

include_once("$topdir/config.inc");

function do_curl_get($url) {

    global $mtt_http_username, $mtt_http_password;

    $method = "GET";

    # Use curl to proxy a request to subversion to get the current NEWS
    # file.  PHP has everything!
    $ch = curl_init();

    # Set the URL to GET from
    curl_setopt($ch, CURLOPT_USERPWD, "$mtt_http_username:$mtt_http_password");
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_HTTPGET, 1);

    # Setting CURLOPT_RETURNTRANSFER variable to 1 will force curl not to
    # print out the results of its query.  Instead, it will return the
    # results as a string return value from curl_exec() instead of the
    # usual true/false.
    curl_setopt ($ch, CURLOPT_RETURNTRANSFER, 1);

    # Execute the request and get the output
    $output = curl_exec ($ch);

    # Check to see if we got success
    if (curl_errno($ch)) {
        curl_close($ch);
        return "<p>Sorry, something went wrong while trying to obtain the URL \"$url\".  Please try again later.\n\n";
    }

    curl_close($ch);
    return $output;
}
