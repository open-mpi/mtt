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

#########################################
#                                       #
#  Global arrays                        #
#                                       #
#########################################

# Some special enumerated types
function enums_table() {

    return array(
        'bitness' => array(
            1 => 32,
            2 => 64,
            3 => '32/64',
        ),
        'endian' => array(
            1 => 'little',
            2 => 'big',
        ),
        'vpath_mode' => array(
            1 => 'no vpath',
            2 => 'relative',
            3 => 'absolute',
        ),
    );
}

# Return a listing of which results go with which phase
function phase_results_table() {

    # THESE RESULT STRINGS MUST MATCH THE IDENTIFIERS USED
    # IN [source:/trunk/server/sql/views.sql]
    return array(
        'mpi_install' => array('pass', 'fail'),
        'test_build'  => array('pass', 'fail'),
        'test_run'    => array('pass', 'fail', 'skipped', 'timed_out'),
    );
}

# Display more human-readable labels
function label($str) {

    $labels = array(

        # Database column names
        "bandwidth_avg"       => "Bandwidth avg.",
        "bandwidth_max"       => "Bandwidth max.",
        "bandwidth_min"       => "Bandwidth min.",
        "bitness"             => "Bitness",
        "client_serial"       => "Client serial",
        "command"             => "Command",
        "compiler_name"       => "Compiler name",
        "compiler_version"    => "Compiler version",
        "configure_arguments" => "Configure arguments",
        "description"         => "Description",
        "duration"            => "Duration",
        "email_address"       => "Email address",
        "enabled"             => "Enabled",
        "endian"              => "Endian",
        "environment"         => "Environment",
        "exit_status"         => "Exit status",
        "field"               => "Field",
        "first_occurrence"    => "First occurrence",
        "gecos"               => "Gecos",
        "hostname"            => "Hostname",
        "http_username"       => "HTTP username",
        "last_occurrence"     => "Last occurrence",
        "latency_avg"         => "Latency avg.",
        "latency_max"         => "Latency max.",
        "latency_min"         => "Latency min.",
        "local_username"      => "Local username",
        "merge_stdout_stderr" => "Merge stdout stderr",
        "message_size"        => "Message size",
        "mpi_name"            => "MPI name",
        "mpi_version"         => "MPI version",
        "mtt_version_major"   => "MTT version major",
        "mtt_version_minor"   => "MTT version minor",
        "np"                  => "np",
        "os_name"             => "OS name",
        "os_version"          => "OS version",
        "phase"               => "Phase",
        "platform_hardware"   => "Platform hardware",
        "platform_name"       => "Platform name",
        "platform_type"       => "Platform type",
        "result_message"      => "Result message",
        "result_stderr"       => "Result stderr",
        "result_stdout"       => "Result stdout",
        "signal"              => "Signal",
        "start_timestamp"     => "Date range",
        "stop_timestamp"      => "Date range",
        "subject"             => "Subject",
        "submit_timestamp"    => "Date range",
        "suite_name"          => "Suite name",
        "test_name"           => "Test name",
        "test_result"         => "Test result",
        "url"                 => "Url",
        "username"            => "Username",
        "value"               => "Value",
        "variant"             => "Variant",
        "vpath_mode"          => "Vpath mode",

        # MTT phase names
        "all_phases"        => "All phases",
        "mpi_install"       => "MPI install",
        "test_build"        => "Test build",
        "test_run"          => "Test run",
        "latency_bandwidth" => "Latency bandwidth",

        # Result types
        "pass"      => "Pass",
        "fail"      => "Fail",
        "skip"      => "Skip",
        "timed"     => "Timed",
        "skipped"   => "Skip",
        "timed_out" => "Timed",

        # Selection/unselection
        "show"  => "Show",
        "hide"  => "Hide",
    );

    if (isset($labels[$str]))
        return $labels[$str];
    else 
        return $str;
}

#########################################
#                                       #
#  Common screen/report functions       #
#                                       #
#########################################

# Grab phase field
function process_phase_field($params) {
    if (isset($params['phase'])) {
        if (preg_match('/^all/', $params['phase']))
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

# Return an English-formatted list
function en_join($list) {

    $size = sizeof($list);

    if ($size == 0)
        return null;
    elseif ($size == 1)
        return $list[0];
    elseif ($size == 2)
        return $list[0] . " and " . $list[1];
    elseif ($size > 2)
        return join(", ", array_slice($list, 0, -1)) .
                ", and " . $list[$size-1];
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
        print("\n<br><pre>SQL:\n$cmd</pre>");
}

# Prints an HTML table of _GET and _POST vars
function debug_cgi($params, $title) {

    global $lgray, $dgray;

    if (isset($_GET['cgi'])) {

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
