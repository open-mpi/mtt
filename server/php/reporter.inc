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

# Grab phase field
function process_phase_field($params) {
    if (isset($params['phase'])) {
        if ($params['phase'] == 'all')
            return array("mpi_install", "test_build", "test_run");
        else
            return tokenize($params['phase']);
    }
    else
        return array("mpi_install", "test_build", "test_run");
}

# Reference: http://www.php.net/strtok
function tokenize($string) {
    $tokens = array();

    $c = "/\s*;\s*/";
    if (preg_match($c, $string))
        return preg_split($c, $string);

    for ($next_token = strtok($string, ' ');
         $next_token !== false;
         $next_token = strtok(' ')) {

        if ($next_token{0} == '"')
            $next_token =
                $next_token{strlen($next_token) - 1} == '"' ?
                     substr($next_token, 1, -1) :
                     substr($next_token, 1) . ' ' . strtok('"');
        $tokens[] = $next_token;
    }

    return $tokens;
}

# Convert an associative array to an HTTP-ready query string
function arr2qstring($arr) {
    foreach (array_keys($arr) as $key)
        $str .= "&$key=$arr[$key]";
    return $str;
}

# Provide logical labels for form controls
function label($str) {

    $labels = array(
        'start_timestamp' => "date_range",
        'submit_timestamp' => "date_range",
    );
    $label = $labels[$str];

    if ($label)
        return $label;
    else 
        return $str;
}

#########################################
#                                       #
#  Developer & User Help Functions      #
#                                       #
#########################################

function debug($str) {
    if ($GLOBALS['debug'] or $GLOBALS['verbose'])
        print("\n<pre>$str</pre>");
}

function var_dump_($desc, $a) {
    if ($GLOBALS['verbose'])
        var_dump("\n$desc",$a);
}

function var_dump_debug($function, $line, $var_name, $var) {

    $dir  = dirname(getcwd());
    $file = $dir . "/submit/" . basename($_SERVER['PHP_SELF']) . ".out";
    $fh   = fopen($file, 'a+');

    if ($GLOBALS['verbose'] or $GLOBALS['debug']) {
        $output = "\ndebug: $function:$line, $var_name = " . var_export($var, 1);
        print($output);
        if ($fh)
            fwrite($fh, $output); # *BROKEN*
    }
}

# Actually see the nice identation var_dump provides
function var_dump_html($desc,$var) {
    if ($GLOBALS['verbose'])
        var_dump("\n<br><pre>$desc",$var,"</pre>");
}

# Print SQL if they want it
function debug_sql($cmd) {
    if (isset($_GET['sql']))
        if ($_GET['sql'] == 'on')
            print("\n<br>SQL: <pre>" . html_to_txt($cmd) . "</pre>");
}

# Prints an HTML table of _GET and _POST vars
function debug_cgi($params, $title) {

    global $lgray, $dgray;

    $cols = 3;

    print "\n\n<table width='80%' border='1'>";
    print "\n\n<tr><th bgcolor='$dgray' colspan=" . $cols * 2 . ">$title";

    $i = 0;
    foreach (array_keys($params) as $k) {
        print "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
            "<td bgcolor='$lgray'>" . $k . "<td>$params[$k]";
    }
    print "\n\n</table>";
}

# Show help text
function help($str) {
    if (! isset($_GET['no_help']))
        return $str;
    else
        return null;
}

# Command-line options to CGI options
function getoptions($argv) {
    for ($i=1; $i<count($argv); $i++) {
       $it = split("=",$argv[$i]);
       $_GET[$it[0]] = $it[1];
    }
    return $_GET;
}

?>
