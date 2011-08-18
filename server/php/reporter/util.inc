<?php

#
# Copyright (c) 2006-2007 Sun Microsystems, Inc.
#                         All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

function html_comment($str) {
    return "<!-- $str -->\n";
}

function form_setup($method, $id, $name, $action) {
    return "<form method='$method' id='$id' name='$name' action='$action'>";
}

function form_get_input_type($type, $name, $value, $id, $extra) {
    $rtn = "  <input type='$type' name='$name'";
    if(isset($value) && 0 < strlen($value) ) {
        $rtn .= " value='$value'";
    }
    if(isset($id) && 0 < strlen($id) ) {
        $rtn .= " id='$id'";
    }
    if(isset($extra) && 0 < strlen($extra) ) {
        $rtn .= " $extra";
    }
    $rtn .= ">";
    return $rtn;
}

#########################################
#                                       #
#  Developer & User Help Functions      #
#                                       #
#########################################

#
# Abort with an error message
#
function abort($str) {
    print("ERROR: " . $str);
    exit;
}

#
# Display debug string if asked
#
function debug($str) {
    if ((isset($_GET['debug']) and $_GET['debug'] == 'on') or 
        (isset($_GET['verbose']) and $_GET['verbose'] == 'on')) {
        print("\n<pre>$str</pre>");
    }
}

function stats($str) {
    if (isset($_GET['stats']) == 'on') {
        print("\n<pre>$str</pre>");
    }
}

#
# Actually see the nice identation var_dump provides
#
function var_dump_html($desc, $var) {
    if ($_GET['debug'] == 'on' or
        $_GET['dev'] == 'on') {
        var_dump("\n<br>" .
                    "<div align='left'>" .
                    "<pre>$desc",$var,"</div>");
    }
}

#
# Print SQL if they want it
#
function debug_sql($cmd, $level) {
    $trace = $_GET['sql'];
    if ($trace >= $level) {
        print("\n<pre>SQL: $cmd</pre>");
    }
}

#
# Prints an HTML table of _GET and _POST vars
#
function debug_cgi($params, $title) {
    if ($_GET['cgi'] == 'on') {
        $cols = 3;
        print "\n\n<table width='80%' border='1'>";
        print "\n\n<tr><th bgcolor='" . DGRAY . "' colspan=" . $cols * 2 . ">$title";

        $i = 0;
        foreach (array_keys($params) as $k) {
            print "\n" . ((($i++ % $cols) == 0) ? "\n<tr>" : "") .
                "<td bgcolor='" . LGRAY . "'>" . $k . "<td>$params[$k]";
        }
        print "\n\n</table>";
    }
}

# Show help text
function help($str) {
    if (! ($_GET['no_help'] == 'on')) {
        return $str;
    } else {
        return null;
    }
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
