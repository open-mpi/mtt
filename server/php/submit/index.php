<?php

$dbname = isset($_GET['db']) ? $_GET['db'] : "mtt";
$user   = "mtt";
$pass   = "3o4m5p6i";

$GLOBALS['conn'] = pg_connect("host=localhost port=5432 dbname=$dbname user=$user password=$pass");

# TODO: Take these in from _POST
$GLOBALS['debug'] = 0;
$GLOBALS['verbose'] = 0;
$GLOBALS['nosql'] = 0;

$once['col'] = array();
$mult['col'] = array();
$once['val'] = array();
$mult['val'] = array();

# if the PING field is set, then this was just a test.  Exit successfully.

if (isset($_POST['PING'])) {
    print "Ping successful.\n";
    exit(0);
}

# PBINPUT - big variable, of data for perfbase to parse.
# MTTVERSION_MAJOR - Major revision of MTT, must match server version
# MTTVERSION_MINOR - Minor revision of MTT

if (isset($_POST['PBINPUT'])) {
    $lines = @explode("\n", $_POST['PBINPUT']);
}
else {
    mtt_error("", "\nNo PBINPUT specified.");
    exit(1);
}

# The following lists should be grabbed from the database

$multiple_params = array(
    "compiler_name",
    "compiler_version",
    "configure_arguments",
    "environment",
    "merge_stdout_stderr",
    "mpi_details",
    "mpi_get_section_name",
    "mpi_install_section_name",
    "result_message",
    "stderr",
    "stdout",
    "\\w+_timestamp",
    "\\w+_interval",
    "success",
    "test_build_section_name",
    "test_command",
    "test_message",
    "test_name",
    "test_np",
    "test_pass",
    "test_run_section_name",
    "vpath_mode",
    #'\w+',       # wildcard unknown multiple param
);

$once_params = array(
    "mtt_version_major",
    "mtt_version_minor",
    "platform_hardware",
    "platform_type",
    "platform_id",
    "os_name",
    "os_version",
    "hostname",
    "mpi_name",
    "mpi_version",
);

$i = 0;

# Parse the input from the MTT client
while ($lines[$i]) {

    $l = $lines[$i];

    if (@preg_match("/^(phase): (.*)$/", $l, $m)) {

        $phase = $m[2];

        # Add checks for the existence of these tables
        if (@preg_match("/test.*run/i", $phase, $m))
            $table = "runs";
        elseif (@preg_match("/test.*build/i", $phase, $m))
            $table = "builds";
        elseif (@preg_match("/mpi.*install/i", $phase, $m))
            $table = "installs";

        $once_table = "once";
    }
    elseif (@preg_match("/^(perfbase_xml):\s+(.*)$/", $l, $m)) {
    
        # ignore these param(s) for now
    }
    elseif (@preg_match("/^(timed_out):\s+(.*)$/", $l, $m)) {
    
        # ignore these param(s) for now
    }
    elseif (@preg_match("/^(skipped):\s+(.*)$/", $l, $m)) {
    
        # ignore these param(s) for now
    }
    # Take in once params
    elseif (@preg_match("/^(" . join('|',$once_params) . "):\s*(.*)$/", $l, $m)) {

        array_push($once['col'], $m[1]);
        array_push($once['val'], $m[2]);
    }

    # Any multi-line data of the form _BEGIN/_END
    elseif (@preg_match("/^.*(" . join('|',$multiple_params) . ")_BEGIN$/i", $l, $m)) {
        
        array_push($mult['col'], strtolower($m[1]));
        $inp = array();

        while (! @preg_match('/_END$/', $lines[$i++])) {
            array_push($inp, $lines[$i]);
        }
        array_pop($inp);
        array_push($mult['val'], join("\n", $inp));
        $i--;   # in case the next field is a multi-line
    }

    # Anything else must be a single-line multiple-param
    elseif (@preg_match("/^(\S+):\s*(.*)$/", $l, $m)) {
        
        $m1 = $m[1];
        $m2 = $m[2];

        if (@preg_match("/timestamp/", $l))
            $m2 = unix2sql_time($m2);
            
        array_push($mult['col'], $m1);
        array_push($mult['val'], $m2);
    }
    else {
        print "\nNot adding '$lines[$i]' to the $dbname database.";
    }
    $i++;
}

#var_dump("mult = ",$mult);
#var_dump("once = ",$once);

if (! $table)
    mtt_error("\nNo phase given, so I don't know which table to direct this data to.");

# Check to see if this config is in the db
$i = 0;
$found_match = null;
$sql_cmd = "SELECT run_index FROM $once_table WHERE ";
foreach ($once['col'] as $col) {
    $sql_cmd .= "$col = '" . $once['val'][$i++] . "' AND ";
}

$sql_cmd = @preg_replace('/\s*AND\s*$/',';',$sql_cmd);
$idx = simple_select($sql_cmd);

# If there is no matching config in the db - grab the latest run_index,
# increment it, and assign it to this config
if ($idx == null) {

    $sql_cmd = "SELECT (run_index + 1) FROM $once_table ORDER BY run_index DESC LIMIT 1;";
    $idx = simple_select($sql_cmd);
}
else {
    $found_match = 1;
}

# this is the first config to be inserted
if (! $idx)
    $idx = 0;

# Insert the new config
array_push($once['col'], "run_index");
array_push($once['val'], $idx);
array_push($mult['col'], "run_index");
array_push($mult['val'], $idx);

if (! $found_match) {
    $sql_cmd = "INSERT INTO $once_table (" . join(",", $once['col']) .
               ") VALUES (" . join(",", array_map("quote", $once['val'])) . ");";
    pg_query_($sql_cmd);
}

# Insert the data row for this test case
$sql_cmd = "INSERT INTO $table (" . join(",", $mult['col']) . 
           ") VALUES (" . join(",", array_map("quote", $mult['val'])) . ");";
pg_query_($sql_cmd);

print "\n\n";

@pg_close();
exit;

# ---

# select a field in the db and return it
function simple_select($cmd) {

    $fetched = null;

    debug("\nSQL: $cmd");
    if (! ($db_res = pg_query($cmd))) {
        debug("\npostgres: " . pg_last_error() . "\n" . pg_result_error());
    }
    $fetched = array_shift(pg_fetch_row($db_res));
    return $fetched;
}

function pg_query_($cmd) {

    debug("\nSQL: $cmd");
    if (! ($db_res = pg_query($cmd))) {
        debug("\npostgres: " . pg_last_error() . "\n" . pg_result_error());
    }
}

# TODO: Make this more robust (or does postgres understand most Unix timestamps?)
function unix2sql_time($str) {
    return @preg_replace('/(Mon|Tue|Wed|Thu|Fri|Sat|Sun) /','',$str);
}

function quote($str) {
    return "'" . $str . "'";
}

# Function to reporting errors back to the client
function mtt_error($status, $str) {
    if (!headers_sent()) {
        header("HTTP/1.0 $status");
    } else {
        print("ERROR: (Tried to send HTTP error) $status\n");
    }
    print("ERROR: $str\n");
    exit(0);
}

function debug($arg) {
    if (! $GLOBALS['verbose'] and ! $GLOBALS['debug'] and 
        (!isset($_GET['debug']) or ! $_GET['debug']))
        return;

    if (is_string($arg))
        print("\n$arg");
    else
        var_dump("\n$arg");
}
