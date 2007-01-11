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

#########################################
#                                       #
#  Definitions                          #
#                                       #
#########################################

# Constant to mute SQL errors (set true to mute)
define('SILENT', true);

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
define('DRED',     "#E0C0C0");
define('LGREEN',   "#C0FFC0");
define('DGREEN',   "#C0E0C0");
define('LYELLOW',  "#FFFFC0");
define('DYELLOW',  "#E0E0C0");
define('LBLUE',    "#C0C0FF");
define('DBLUE',    "#C0C0E0");
define('WHITE',    "#FFFFFF");
define('THCOLOR',  LLGRAY);

# Mask the trial column using HTML comments
define('TRIAL_TRUE',  't');
define('TRIAL_FALSE', 'f');

# Define paths
define('DOCROOT', dirname('http://'.$_SERVER['SERVER_NAME'].$_SERVER['SCRIPT_NAME']));
define('PATH',    dirname($_SERVER['SCRIPT_NAME']));

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

# Return a list of preferences to hand off to prefs_popup
function setup_prefs() {

    static $prefs;

    if (! $prefs)
        $prefs = array(
            'general'  => array(
                'limit'    => array(array('10', '50', '*100', '200')),
                'wrap'     => array(100),
                'timezone' => array(array('*GMT', 'EST', 'CST', 'MST', 'PST')),
                'trial'    => array(false),
            ),
            'graphing' => array(
                'yaxis_scale'      => array(array('Logarithmic', '*Linear')),
                'xaxis_scale'      => array(array('Logarithmic', '*Linear')),
                'hide_subtitle'    => array(false),
                #'graph_size'       => array(array('Small', '*Medium', 'Large')),
                #'legend_placement' => array(array('*Bottom', 'In plotting area')),
                #'graph_type'       => array(array('*Line', 'Bar', 'Points')),
            ),
        );

    return $prefs;
}

# Return a list of columns to show/hide
function setup_advanced($params) {

    $phases = process_phase_field($params);

    static $menu;

    if (! $menu) {

        # Put hide first so it defaults as the shown menu item
        $control = array('hide', 'show');

        $menu = array(
            'compute_cluster' => array(
                'os_version'          => array('', $control),
                'platform_type'       => array('', $control),
               #'platform_hardware'   => array('', $control),
               #'platform_name'       => array('', $control),
               #'os_name'             => array('', $control),
            ),
            'submit' => array(
                'hostname'            => array('', $control),
               #'local_username'      => array('', $control),
               #'http_username'       => array('', $control),
            ),
            'mpi_install' => array(
                'compiler_name'       => array('', $control),
                'compiler_version'    => array('', $control),
                'vpath_mode'          => array('', $control),
                'endian'              => array('', $control),
                'bitness'             => array('', $control),
               #'mpi_name'            => array('', $control),
               #'mpi_version'         => array('', $control),
               #'configure_arguments' => array('', $control),
            ),
            'results' => array(
                'exit_value'          => array('', $control),
                'exit_signal'         => array('', $control),
                'duration'            => array('', $control),
                'client_serial'       => array('', $control),
                'result_message'      => array(''),
                'result_stdout'       => array(''),
                'result_stderr'       => array(''),
                'environment'         => array(''),
            ),
        );

        if (sizeof($phases) == 1) {

            if (array_search('test_build', $phases) !== false or
                array_search('test_run', $phases) !== false) {
                $menu =
                    array_merge(
                        $menu,
                        array('test_build' => array(
                            'suite_name' => array('', $control)
                        ))
                    );
            }
            if (array_search('test_run', $phases) !== false) {
                $menu =
                    array_merge(
                        $menu,
                        array('test_run' => 
                            array(
                                'variant'   => array('', $control),
                                #'test_name' => array('', $control),
                                #'np'        => array('', $control),
                                #'command'   => array('', $control),
                            ))
                    );
            }
        }
    }

    return $menu;
}

# Display more human-readable labels
function label($str) {
    
    static $labels;

    if (! $labels) {
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
            "exit_value"          => "Exit value",
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
            "platform_name"       => "Platform name",
            "platform_type"       => "Platform type",
            "result_message"      => "Result message",
            "result_stderr"       => "Stderr",
            "result_stdout"       => "Stdout",
            "exit_signal"         => "Signal",
            "start_timestamp"     => "Date range",
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

            # Other schema tables
            'compute_cluster'   => 'Cluster',
            'submit'            => 'Submit',
            'results'           => 'Results',

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
            "show"                  => "Show",
            "hide"                  => "Hide",

            # General preferences
            'general'              => 'General',

            'limit'                => 'Max rows per page',
            'timezone'             => 'Time zone',
            'wrap'                 => 'Text wrap <i>(in Detail)</i>',

            # Two labels: one for the UI, one for the column header
            'trial'                => 'Trial',
            'Trial'                => 'Show trial runs',

            # Graphing preferences
            'graphing'             => 'Graphing',

            'graph_size'           => 'Graph size',
            'legend_placement'     => 'Legend placement',
            'yaxis_scale'          => 'Y-axis scale',
            'xaxis_scale'          => 'X-axis scale',
            'graph_type'           => 'Graph type',
            'hide_subtitle'        => 'Hide subtitle',

            # Row number
            "n" => "#",
        );
    }

    if (isset($labels[$str]))
        return $labels[$str];
    elseif (isset($labels[strip_prefix($str)]))
        return $labels[strip_prefix($str)];
    else 
        return $str;
}

# Remove the prefix part of the parameter,
# which will leave only a database column name
function strip_prefix($str) {
    return preg_replace('/^more_|^show_|^text_/', '', $str);
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

    # In Detail view, they likely want to see test name
    $go = get_go_or_click($_GET);

    if (preg_match("/summary/i", $go) or is_null($go))
        $ret['show']['test_name'] = 'hide';

    # Phase
    $ret['phase'] = 'all_phases';

    # Developer params
    $ret['dev'] = developer_params();

    return $ret;
}

# Grab the report type from either a button click or a drilldown's "go"
function get_go_or_click($params) {
    return isset($params['click']) ? $params['click'] : $params['go'];
}

# Some helpful params for validating reporter.php
function developer_params() {
    static $params;
    if (! $params)
        $params = array(
            'dev'        => null,
            'sql'        => null,
            'cgi'        => null,
            'debug'      => null,
            'stats'      => null,
            'no_cache'   => null,
            'no_cookies' => null,
        );
    return $params;
}

# Take a 'defaults' array (output from setup_defaults) Carry
# over textfields, show/hide menus, and radios from the last
# invocation (Returns an arr2qstring-ready list)
#
# Dual-purpose function:
# (1). Used for filling in form controls from "last time"
# (2). Used (in tandem with setup_defaults) for creating
#      drilldown links, for transitions between phase
#      changes
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

    $clicks = array('go', 'click');

    # Press 'Summary' for them if they traverse from a
    # detailed report into multi-phase mode
    foreach ($clicks as $click) {
        if (! is_null($_GET[$click])) {
            if (preg_match("/^all/i", $phase))
                $params[$click] = 'summary';
            else
                $params[$click] = $_GET[$click];
        }
    }

    # Carryover last ttable_id, so we know what to DELETE
    $params['ttable_id'] = $_GET['ttable_id'];

    # Carryover phase
    $phase = $_GET['phase'];
    if ($phase)
        $params['phase'] = $phase;
    else
        $params['phase'] = $defaults['phase'];

    # Carryover trial field
    $text_trial = $_GET['text_trial'];
    if ($text_trial)
        $params['text_trial'] = $text_trial;
    else
        $params['text_trial'] = $defaults['text_trial'];

    # Carryover developer params
    foreach (array_keys($defaults['dev']) as $k)
        if (isset($_GET[$k]))
            $params[$k] = $_GET[$k];

    # It would be nonsensical to carry these onward
    # (this is only done in the case of clicking a
    # ''slices_index'' link)
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
