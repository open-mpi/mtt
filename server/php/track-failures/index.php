<?php

#
# Copyright (c) 2007 Sun Microsystems, Inc.
#                    All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

#
#
# Web-based Tool for MTT failures
#
#

# CHANGE THIS LINE TO THE LIVE DB BEFORE COMMITING!
$_GET['db'] = 'mtt3_1';

# Includes
include_once("../reporter.inc");
include_once("../screen.inc");
include_once("../database.inc");

# Deny mirrors access to MTT results
deny_mirror();

# 'debug' is an aggregate trace
if (isset($_GET['debug'])) {
    $_GET['verbose'] = 'on';
    $_GET['dev']     = 'on';
    $_GET['cgi']     = 'on';
}

# 'stats' and 'explain' would not make sense without 'sql'
if (isset($_GET['stats']) or 
    isset($_GET['explain']) or 
    isset($_GET['analyze'])) {
    $_GET['sql'] = '2';
}

# Set PHP trace levels
if (isset($_GET['verbose']))
    error_reporting(E_ALL);
else
    error_reporting(E_ERROR | E_PARSE);

# In case we're using this script from the command-line
if ($argv)
    $_GET = getoptions($argv);

# Keep track of time
$start = time();

# Keep track of row count
$old_count = get_row_count();

# Show failure DB
$screen = $_GET['screen'];

# THIS BLOCK IS IN TWO FUNCTIONS!
print "\n<html>" . 
      "\n" . html_head("MTT Failure Database") .
      "\n<body>" .
      "\n<form method='get' id='track_failures' name='track_failures'>" .
      "\n<div align='center'>";

if (! isset($_GET['go'])) {
    if ($screen == 'Delete') {
        delete_screen();
    } else if ($screen == 'Insert') {
        insert_screen();
    } else {
        insert_screen();
    }
} else if ($_GET['go'] == 'Insert') {
    insert_failure();
    insert_screen();
} else if ($_GET['go'] == 'Delete') {
    delete_failures();
    delete_screen();
} else {
    insert_screen();
} 

$new_count = get_row_count();

# Report whether the INSERT worked
if ($new_count > $old_count) {
    print("\n<p>INSERT was successful. " . 
          "\nThere are now <b>$new_count</b> rows " .
          "\nin the failure database.</p>");
}
# Report whether the DELETE worked
else if ($new_count < $old_count) {
    print("\n<p>DELETE was successful. " . 
          "\nThere are now <b>$new_count</b> rows " .
          "\nin the failure database.</p>");
}

# Report on script's execution time
$finish = time();
$elapsed = $finish - $start;
debug("\n<p>Total script execution time: " . $elapsed . " second(s)</p>");

# Display input parameters
debug_cgi($_GET, "GET " . __LINE__);

# Display cookie parameters
debug_cgi($_COOKIE, "COOKIE " . __LINE__);

print "\n" . hidden_carryover2() .
      "\n</div>" .
      "\n</form>" .
      "\n</body>" .
      "\n</html>";

exit;

# FETCH THIS ARRAY USING AN SQL QUERY
function setup_db_columns() {

    static $ret;
    if ($ret)
        return $ret;

    $ret = array(
        "compute_cluster" =>
            array(
                "platform_name",
                "platform_hardware",
                "platform_type",
                "os_name",
                "os_version",
            ),
        "submit" =>
            array(
                "mtt_client_version",
                "hostname",
                "local_username",
                "http_username",
            ),
        "mpi_get" => 
            array(
                "mpi_name",
                "mpi_version",
            ),
        "compiler" => 
            array(
                "compiler_name",
                "compiler_version",
            ),
        "mpi_install" => 
            array(
                "configure_arguments",
                "vpath_mode",
                "bitness",
                "endian",
            ),
        "test_build" => 
            array(
                "suite_name",
            ),
        "test_run" => 
            array(
                #"variant",
                "test_name",
                "command",
                "np",
            ),
        "results" => 
            array(
                #"phase",
                #"duration",
                "environment",
                "merge_stdout_stderr",
                "result_stdout",
                "result_stderr",
                "result_message",
                "exit_value",
                "exit_signal",
                "test_result",
            ),
    );

    return $ret;
}

# MAKE THIS MORE DYNAMIC. E.G., A LITTLE '+'
# BUTTON TO ADD ITEMS TO THE FAILURE SPEC.
# (RIGHT NOW WE JUST DUMP OUT "ENOUGH" ROWS (10) FOR THE
# INSERT SCREEN.)
function insert_screen() {

    $arr = setup_db_columns();

    # Compose the sprintf format for the universal SELECT menu.
    # Each of the identical menus is numbered (see the 'sel_%d' below)
    $select = "\n\t<select name='sel_%d'>";
    $select .= "\n\t<option selected label='None' name='none' value=''>None</option>";

    foreach (array_keys($arr) as $table) {
        $select .= "\n\t<optgroup label='$table'>";

        foreach ($arr[$table] as $v) {
            $select .= "\n\t\t<option label='$v' name='opt_$v' value='$v'>$v</option>";
        }
        $select .= "\n\t</optgroup>";
    }
    $select .= "\n\t</select>";

    $bg1 = GRAY;
    $bg2 = LGRAY;

    # Compose HTML table that will render the query screen
    $table = "\n<table width='40%' align='center' border='1' cellspacing='1'>" .
             "\n<th colspan='2' bgcolor='$bg1'>MTT Failure Tracking";

    $sp = '&nbsp;';
    $rows = 10;
    for ($i = 0; $i < $rows; $i++) {
        $table .= "\n\t<tr>" .
                  "\n\t<td bgcolor='$bg2'>" .
                    "\n\t${sp}Field:" . sprintf($select, $i) .
                  "\n\t<td bgcolor='$bg2'>" .
                    "\n\t${sp}Value: <input type='text' name='text_$i' value=''>";
    }

    $href = link_to_screen("Delete");

    # Add submit button
    $table .= "\n<tr><th colspan='2' bgcolor='$bg1'>" .
              "\n<input type='submit' id='go' name='go' value='Insert'>" .
              "\n$href" .
              "\n</table>";

    $help .= "\n<p>Specify the parameter/value pairs of the failure for insertion.</p>";

    print "\n $table" .
          "\n $help";
}

function insert_failure() {

    $params = array();
    $values = array();

    foreach (array_keys($_GET) as $k) {

        if (preg_match("/^sel_(\d+)$/i", $k, $m)) {
            $i = $m[1];

            if ($_GET[$k]) {
                $param = $_GET["sel_$i"];
                $value = $_GET["text_$i"];

                array_push($params, $param);
                array_push($values, $value);
            }
        }
    }

    $inserts[0] = "'{" . join(',', $params) . "}'";
    $inserts[1] = "'{" . join(',', $values) . "}'";

    $columns = array(
        "_params",
        "_values",
    );
    
    # Compose the SQL INSERT query
    $query = "\n\t INSERT INTO failure " .
             "\n\t   (" . join(",", $columns) . ")" .
             "\n\t   VALUES " . 
             "\n\t   (" . join(",", $inserts) . ")" .
             "\n\t   ;";

    do_pg_query($query);
}

function get_row_count() {

    # Compose the SQL INSERT query
    $query = "SELECT COUNT(*) FROM failure;";
    $count = select_scalar($query);
    return $count;
}

# Just like insert_screen, but this is used in a popup window
#
# SHOULD THIS OPEN IN A POPUP WINDOW?
function delete_screen() {

    $query = "SELECT * FROM failure;";
    $failures = select($query);

    var_dump_html(__FUNCTION__ . ":" . __LINE__ . " " . '$failures = ',$failures);

    $bg1 = GRAY;
    $bg2 = LGRAY;
    $sp = '&nbsp;';

    $columns = array(
        '_params',
        '_values',
        # 'first_occurence', # WHY ISN'T THIS SHOWING UP IN THE TABLE?
    );

    $tables .= "\n\t<table width='40%' align='center' " .
                      "border='1' cellspacing='1'>" .
               "\n<th colspan='2' bgcolor='$bg1'>MTT Failure Tracking";

    foreach (array_keys($failures) as $i) {
        $id = $failures[$i]['failure_id'];

            $tables .=
                 "\n\t<tr>" .
                 "\n\t<th colspan='2' bgcolor='$bg1' align='left'>" .
                     "\n\t<input type='checkbox' name='del_$id'>${sp}$id";

        foreach ($columns as $col) {
            $value = $failures[$i][$col];

            $tables .= "\n\t<tr>" .
                       "\n\t<td bgcolor='$bg2' width='33%'>" .
                       "\n\t${sp}<b>" . label($col) . "</b>" .
                       "\n\t<td bgcolor='$bg2' width='67%'>" .
                       "\n\t${sp}$value";
        }
    }

    $href = link_to_screen("Insert");

    $tables .= "\n<tr><th colspan='2' bgcolor='$bg1'>" .
               "\n<input type='submit' " .
                        "id='go' " .
                        "name='go' " .
                        "value='Delete'>" .
               "\n$sp" .
               # "\n<input type='submit' " .
               #          "name='cancel' " .
               #          "onclick='javascript:window.close();' " .
               #          "value='Cancel'>" .
               "\n$sp" .
               "\n$href" .
               "\n</table>";

    $help .= "\n<p>Checkbox the failures you would like to delete.</p>";

    # Print tiny link in a tiny window
    # THIS BLOCK IS IN TWO FUNCTIONS!
    print "\n" . $tables .
          "\n" . $help;
}

function delete_failures() {

    $deletes = array();

    foreach (array_keys($_GET) as $k) {

        if (preg_match("/^del_(\d+)$/i", $k, $m)) {
            $i = $m[1];

            if ($_GET[$k] == 'on') {
                array_push($deletes, "failure_id = '$i'");
            }
        }
    }

    # Compose the SQL DELETE query
    $query = "\n\t DELETE FROM failure " .
             "\n\t   WHERE " . 
             "\n\t   " . join(" OR \n\t\t", $deletes) .
             "\n\t   ;";

    do_pg_query($query);
}

function hidden_carryover2() {
    $hiddens = setup_developer_params();

    foreach (array_keys($hiddens) as $k) {
        if (isset($_GET[$k])) {
            $v = $_GET[$k];
            $str .= "\n\t<input type='hidden' name='$k' value='$v'>";
        }
    }
    return $str;
}

function link_to_screen($type) {
    $self = 'http://' . $_SERVER['SERVER_NAME'] . $_SERVER['SCRIPT_NAME'];
    $params = $_GET;
    $params['screen'] = $type;

    unset($params['go']);
    $qstring = arr2qstring($params);

    $ret = "<a href='$self?$qstring' class='lgray_ln'>[$type Mode]</a>";

    return $ret; 
}

?>
