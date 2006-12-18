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
#  Definitions                          #
#                                       #
#########################################

# Constant to mute SQL errors (set true to mute)
define('SILENT', true);

# Number of rows to show per page
define('LIMIT', 100);

# Text wrapping in Detail reports
define('WRAP', 100);

# Screen dimemsion constants for graphing
define('SCREEN_WIDTH', 1200);
define('SCREEN_HEIGHT', 700);

# HTML colors
define('GRAY',     "#A0A0A0");
define('DGRAY',    "#808080");
define('LGRAY',    "#C0C0C0");
define('LLGRAY',   "#DEDEDE");
define('LLLGRAY',  "#E8E8E8");
define('LRED',     "#FFC0C0");
define('LGREEN',   "#C0FFC0");
define('LYELLOW',  "#FFFFC0");
define('LBLUE',    "#C0C0FF");
define('WHITE',    "#FFFFFF");
define('THCOLOR',  LLGRAY);

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
        'mpi_install' => 
            array('_ip', '_if'),
        'test_build'  => 
            array('_bp', '_bf'),
        'test_run'    => 
            array('_rp', '_rf', '_rs', '_rt', '_rl'),
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
        "compiler_name"       => "Compiler",
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
        "http_username"       => "Org",
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
        "os_name"             => "OS",
        "os_version"          => "OS version",
        "phase"               => "Phase",
        "platform_hardware"   => "Hardware",
        "platform_name"       => "Cluster",
        "platform_type"       => "Platform type",
        "result_message"      => "Result message",
        "result_stderr"       => "Result stderr",
        "result_stdout"       => "Result stdout",
        "signal"              => "Signal",
        "start_timestamp"     => "Date range",
        "stop_timestamp"      => "Date range",
        "subject"             => "Subject",
        "submit_timestamp"    => "Date range",
        "suite_name"          => "Suite",
        "test_name"           => "Test",
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

        # Result types

        # Result string to column name
        '_ip'               => 'pass',
        '_if'               => 'fail',
        '_bp'               => 'pass',
        '_bf'               => 'fail',
        '_rp'               => 'pass',
        '_rf'               => 'fail',
        '_rs'               => 'skipped',
        '_rt'               => 'timed_out',
        '_rl'               => 'latency_bandwidth',

        # Column name to web page label
        "pass"              => "Pass",
        "fail"              => "Fail",
        "skip"              => "Skip",
        "timed"             => "Timed",
        "skipped"           => "Skip",
        "timed_out"         => "Timed",
        "latency_bandwidth" => "Perf",
        
        # Latency/bandwidth
        "latency_avg"       => "Latency (avg)",
        "latency_min"       => "Latency (min)",
        "latency_max"       => "Latency (max)",
        "bandwidth_avg"     => "Bandwidth (avg)",
        "bandwidth_min"     => "Bandwidth (min)",
        "bandwidth_max"     => "Bandwidth (max)",

        # Selection/unselection
        "show"  => "Show",
        "hide"  => "Hide",

        # Row number
        "n" => "#",
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

# Return an array of default values for textfields
# (Feed this too form_carryover)
function setup_defaults($phases) {

    # Arrayify the argument
    if (! is_array($phases))
        $phases = array($phases);

    $single_phase = (sizeof($phases) == 1) ? true : false;

    # ompi does not submit results
    $http_username = $_SERVER['PHP_AUTH_USER'];
    if (! $http_username or preg_match("/ompi/i", $http_username))
        $http_username = 'all';

    $defaults = array(
        # results
        'start_timestamp'   => 'past 24 hours',

        # submit
        'http_username'     => $http_username,
        'local_username'    => 'all',
        'platform_name'     => 'all',

        # mpi_install
        'platform_hardware' => 'all',
        'os_name'           => 'all',
        'mpi_name'          => 'all',
        'mpi_version'       => 'all',
    );

    # Phase-specific
    if ($single_phase) {
        if (array_search('mpi_install', $phases) !== false)
            $specific = array(
                'configure_arguments' => '',
                'compiler_name'       => 'all',
                'bitness'             => 'all',
                'endian'              => 'all',
            );
        elseif (array_search('test_build', $phases) !== false)
            $specific = array(
                'suite_name'       => 'all',
                'compiler_name'    => 'all',
                'compiler_version' => 'all',
                'bitness'          => 'all',
            );
        elseif (array_search('test_run', $phases) !== false)
            $specific = array(
                'suite_name' => 'all',
                'test_name'  => 'all',
                'np'         => 'all',
                'command'    => 'all',
            );
    }

    $ret = array_merge(
        $defaults,
        $specific
    );

    # Show all columns (except local_username)
    foreach (array_keys($ret) as $k)
        $ret['show'][$k] = 'show';

    $ret['show']['local_username'] = 'hide';

    # Phase
    $ret['phase'] = 'all_phases';

    # Developer params
    $ret['dev'] = array(
        'sql'      => null,
        'cgi'      => null,
        'debug'    => null,
        'stats'    => null,
        'dev'      => null,
        'no_cache' => null,
    );

    return $ret;
}

# Take a 'defaults' array (output from setup_defaults) Carry
# over textfields, show/hide menus, and radios from the last
# invocation (Returns an arr2qstring-ready list)
#
# Dual-purpose function:
# (1). Used for filling in form controls from "last time"
# (2). Used (in tandem with setup_defaults) for creating
#      drilldown links
#
# (X: FOR CONSISTENCY, THIS FUNCTION SHOULD ONLY BE USED FOR
# (1) - AUTO-FILLING A FORM)
#
function form_carryover($defaults, $phase) {

    foreach (array_keys($defaults) as $k) {

        # Only deal with text fields
        if ($k == 'show' or 
            $k == 'phase' or
            $k == 'go' or
            $k == 'dev')
            continue;

        $textfield = "text_$k";
        $showfield = "show_$k";

        # Carryover textfields
        if (isset($_GET[$textfield]))
            $params[$textfield] = $_GET[$textfield];
        else
            $params[$textfield] = $defaults[$k];

        # Carryover show/hide menus
        if ($_GET[$showfield])
            $params[$showfield] = $_GET[$showfield];
        else
            $params[$showfield] = $defaults['show'][$k];
    }

    # Press 'Summary' for them if they traverse from a
    # detailed report into multi-phase mode
    $go = $_GET['go'];
    if (! is_null($go)) {
        if (preg_match("/^all/i", $phase))
            $params['go'] = 'summary';
        else
            $params['go'] = $go;
    }

    # Carryover last ttable_id, so we know what to DELETE
    $params['ttable_id'] = $_GET['ttable_id'];

    # Carryover phase
    $phase = $_GET['phase'];
    if ($phase)
        $params['phase'] = $phase;
    else
        $params['phase'] = $defaults['phase'];

    # Carryover developer params
    foreach (array_keys($defaults['dev']) as $k)
        if (isset($_GET[$k]))
            $params[$k] = $_GET[$k];

    # It would be nonsensical to carry these onward
    # (this is only done in the case of clicking a
    # ''next_n_rows'' link)
    unset($params['offset']);
    unset($params['rows']);
    unset($params['slice']);

    return $params;
}

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

# Capitalize the first char of a string
function capitalize($str) {
    $len = strlen($str);
    return strtoupper(substr($str, 0, 1)) . substr($str, 1, $len);
}

#########################################
#                                       #
#  Developer & User Help Functions      #
#                                       #
#########################################

function debug($str) {
    if ($_GET['debug'] == 'on' or $_GET['verbose'] == 'on')
        print("\n<pre>$str</pre>");
}

function stats($str) {
    if ($_GET['stats'] == 'on')
        print("\n<pre>$str</pre>");
}

# Actually see the nice identation var_dump provides
function var_dump_html($desc, $var) {
    if ($_GET['debug'] == 'on' or
        $_GET['dev'] == 'on')
        var_dump("\n<br>" . 
                    "<div align='left'>" .
                    "<pre>$desc",$var,"</div>");
}

# Print SQL if they want it
function debug_sql($cmd, $level) {
    $trace = $_GET['sql'];
    if ($trace == $level)
        print("\n<pre>SQL: $cmd</pre>");
}

# Prints an HTML table of _GET and _POST vars
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
    if (! ($_GET['no_help'] == 'on'))
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
