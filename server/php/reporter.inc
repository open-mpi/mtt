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
# Catch-all include file for Reporting Tools
#
#

#########################################
#                                       #
#  String Processing Functions          #
#                                       #
#########################################


function strtonumeral($str) {

    $words_to_numerals = array(
        "one"   => 1,
        "two"   => 2,
        "three" => 3,
        "four"  => 4,
        "five"  => 5,
        "six"   => 6,
        "seven" => 7,
        "eight" => 8,
        "nine"  => 9,
        "ten"   => 10,
    );

    $converted = $words_to_numerals[strtolower($str)];

    if ($converted)
        return $converted;
    else
        return $str;
}

# Return string concatenated to itself x times
function repeat($str, $x) {

    $orig = $str;
    for ($i = 0; $i < $x-1; $i++){
        $orig .= $str;
    }
    return $orig;
}

# sprintf for arrays. Return the entire array sent through
# sprintf, concatenated
# This really seems like an array_map sort of thing, but
# php has a different concept of map than perl
#
# Returns a string
function sprintf_($format, $arr) {
    $str = "";
    foreach ($arr as $s) {
        $str .= sprintf($format,$s);
    }
    return $str;
}

# sprintf for arrays. Return the entire array sent through
# sprintf
# This really seems like an array_map sort of thing, but
# php has a different concept of map than perl
#
# Returns an array()
function lsprintf_($format, $arr) {
    $arr2 = array();
    foreach ($arr as $s) {
        array_push($arr2, sprintf($format,$s));
    }
    return $arr2;
}

# Convert some txt chars to html codes
function txt_to_html($str) {
    $str = preg_replace('/\n\r|\n|\r/','<br>',$str);
    #$str = preg_replace('/\s+/','&nbsp;',$str);
    return $str;
}

# Convert some html codes to txt chars
function html_to_txt($str) {
    $str = preg_replace('/<\w+>/','*tag*',$str);
    return $str;
}

# Convert some html codes to txt chars
function html_to_txt2($str) {
    $str = preg_replace('/<br>/',' - ',$str);
    $str = preg_replace('/<\w+>/','',$str);
    return $str;
}

# ' = 047 x27
# " = 042 x22
# Strip quotes from html.
# Needed for sending 'content' argument to a javascript popup function
function strip_quotes($str) {
    return preg_replace('/\x27/','',$str);
}

# Useful for preventing browser text-wrapping
function ascii_sp_to_html_sp($str) {
    $str = preg_replace('/\s+/','&nbsp;',$str);
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

# Print a message and exit
function exit_($str) {
    print $str;
    exit;
}

?>
