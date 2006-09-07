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
# Catch-all include file for Reporting Tools
#
#

$GLOBALS['verbose'] = $_GET['verbose'] ? $_GET['verbose'] : 0;
$GLOBALS['debug']   = $_GET['debug']   ? $_GET['debug']   : 0;
$GLOBALS['res']     = 0;

$form_id = "report";

$words_to_numerals = array(
    #"One"   => 1,
    "Two"   => 2,
    "Three" => 3,
    "Four"  => 4,
    "Five"  => 5,
    "Six"   => 6,
    "Seven" => 7,
    "Eight" => 8,
    "Nine"  => 9,
    "Ten"   => 10,
);

# db field name => html column header This could be done using the SQL 'as'
# construct (?), but that's a lot of regexp-ing
#
# Or use pg_fetch_all which returns a hash, not a numerically indexed array
# (we're okay as long as php can preserve the array creation order)
$sp = "&nbsp;";
$field_labels = array(

    # not an actual db field
    "phase"                    => "Phase",

    # phase-independent fields
    "platform_hardware"        => "Hardware",
    "platform_type"            => "Os",
    "platform_id"              => "Cluster",
    "cluster"                  => "Cluster",
    "os_name"                  => "Os",
    "os_version"               => "Os".$sp."ver",
    "mpi_name"                 => "Mpi",
    "mpi_version"              => "Mpi".$sp."rev",
    "hostname"                 => "Host",

    # timestamp related
    "start_test_timestamp"     => "Timestamp" .$sp."(GMT)",
    "start_run_timestamp"      => "Timestamp" .$sp."(GMT)",
    "submit_test_timestamp"    => "Submit".$sp."time",
    "test_duration_interval"   => "Test".$sp."duration",
    "agg_timestamp"            => "Timestamp".$sp."aggregation",

    "mpi_get_section_name"     => "Section".$sp."(MPI Get)",
    "mpi_install_section_name" => "Section".$sp."(MPI Install)",
    "mpi_details"              => "MPI Details",
    "test_build_section_name"  => "Suite".$sp."(Build)",
    "test_run_section_name"    => "Suite".$sp."(Run)",
    "section"                  => "Section",
    "merge_stdout_stderr"      => "Merge".$sp."outputs",
    "stderr"                   => "Stderr",
    "stdout"                   => "Stdout",
    "environment"              => "Env",
    "mtt_version_major"        => "Mtt".$sp."ver".$sp."maj",
    "mtt_version_minor"        => "Mtt".$sp."ver".$sp."min",
    "compiler_name"            => "Compiler",
    "compiler"                 => "Compiler",
    "compiler_version"         => "Compiler".$sp."ver",
    "configure_arguments"      => "Config".$sp."args",
    "vpath_mode"               => "Vpath",
    "result_message"           => "Result".$sp."msg",
    "test_name"                => "Test".$sp."name",
    "name"                     => "Test name",
    "section_name"             => "Test name",
    "test_command"             => "Mpirun".$sp."cmd",
    "test_np"                  => "Np",
    "result_message"           => "Test".$sp."msg",
    "test_message"             => "Test".$sp."msg",
    "test_pass"                => "Result",
    "success"                  => "Result",
    "count"                    => "Count",
    "date"                     => "Date",
    "time"                     => "Time",
);
$menu_labels = array(
    "all" => "All",
);
$All = "All";

# Encode cgi param name prefixes as a means to slim down the query string
# X: Encode cgi param field names
$cgi_abbrevs = array(
    'hidden_menufield' => 'hmef_',
    'menufield'        => 'mef_',
    'mainfield'        => 'maf_',
    'textfield'        => 'tf_',
    'filter_types'     => 'ft_',
);

#########################################
#                                       #
#  String Processing Functions          #
#                                       #
#########################################

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
    return preg_replace('/\x22|\x27/','',$str);
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
        print("\n$str");
}

function var_dump_($desc, $a) {
    if ($GLOBALS['verbose'])
        var_dump("\n$desc",$a);
}

# Actually see the nice identation var_dump provides
function var_dump_html($desc,$var) {
    if ($GLOBALS['verbose'])
        var_dump("\n<br><pre>$desc",$var,"</pre>");
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
