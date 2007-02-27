<?php
# Copyright (c) 2006 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2006 Sun Microsystems, Inc.  All rights reserved.

#
#
# submit/index.php - 
#
# Parse results submitted by the MTT client.  MTT
# client submits results, one ini section at a time.
#
#

$topdir = '..';
$ompi_home = '/l/osl/www/doc/www.open-mpi.org';
include_once("$ompi_home/dbpassword.inc");
include_once("$topdir/reporter.inc");

$GLOBALS['debug']   = isset($_POST['debug'])   ? $_POST['debug']   : 1;
$GLOBALS['verbose'] = isset($_POST['verbose']) ? $_POST['verbose'] : 1;
$dbname             = isset($_GET['db'])       ? $_GET['db']       : "mtt3";
$pgsql_conn;

# Set php trace levels
if ($GLOBALS['verbose'])
    error_reporting(E_ALL);
else
    error_reporting(E_ERROR | E_WARNING | E_PARSE);

# Notify of fields that do not exist in the database
report_non_existent_fields();

# If the PING field is set, then this was just a
# test.  Exit successfully.
if (isset($_POST['PING'])) {
    print "Ping successful.\n";
    exit(0);
}

$marker = "===";

# If the SERIAL field is set, then the client just
# needs a serial.  Exit successfully.
if (isset($_POST['SERIAL'])) {
    print "\n$marker client_serial = " .  stringify(get_serial()) . " $marker\n";
    exit(0);
}

# If these are not set, then exit.
if ((! isset($_POST['mtt_version_major']) or
     ! isset($_POST['mtt_version_minor'])) and
     ! isset($_POST['mtt_client_version'])) {
    mtt_abort(400, "\nMTT client version not specified.");
    exit(1);
}

# Who is submitting?  Note: PHP_AUTH_USER index is
# not set if .htaccess file is absent
$_POST['http_username'] =
        isset($_SERVER['PHP_AUTH_USER']) ?
        $_SERVER['PHP_AUTH_USER'] : "";

# Declare some global MTT database semantics
$id = "_id";
$speedy_pfx = "speedy_";
$archive_pfx = "";

# Process performance data, if there is any
$table = 'latency_bandwidth';
if (($_POST['test_type'] == $table) or 
    ($_POST['test_type_1'] == $table)) {
    $idxs_hash["$table$id"] = set_data($table, NULL, true, NULL);
}

# What phase are we doing?
$phase      = strtolower($_POST['phase']);
$phase_name = preg_replace('/^\s+|\s+$/', '', $phase);
$phase_name = preg_replace('/\s+/', '_', $phase);

$phase_smallints = array(
    "mpi_install" => 1,
    "test_build" => 2,
    "test_run" => 3,
);

print "\nMTT submission for $phase\n";

if (0 == strcasecmp($phase, "test run")) {

    $idx = process_phase($phase_name, $idxs_hash);

} else if (0 == strcasecmp($phase, "test build")) {

    $idx = process_phase($phase_name, NULL);

} else if (0 == strcasecmp($phase, "mpi install")) {

    $idx = process_phase($phase_name, NULL);

} else {
    print "ERROR: Unknown phase! ($phase)<br>\n";
    mtt_abort(400, "\nNo phase given, so I don't know which table to direct this data to.");
    exit(1);
}

# Return index(es) to MTT client
print "\n$marker $phase_name$id" . " = " . stringify($idx) . " $marker\n";

# All done
pg_close();
exit(0);

######################################################################

function process_phase($phase, $idxs_hash) {

    global $id;
    global $phase_smallints;

    $idx_override      = NULL;
    $phase_indexes     = array();
    $results_idxs_hash = array();
    $fully_qualified   = false;

    # Grab the indexes that don't link to children tables
    #
    # X: it would be nice to have the following block be a recursive
    # routine that recursively traverses the tree of tables and fills
    # in the fields (using $_POST).
    # Since the tree of tables is relatively simple at the moment
    # we should be able to get away without the above routine.
    $phase_indexes =
        array_filter(
            array_map('get_idx_root',
                       get_table_indexes($phase, $fully_qualified)
            ),
            'contains_no_table_key');

    # It's impossible to submit with two different submit identities
    # so grab the one and only submit_id
    # IF DISCONNECTED SCENARIOS COMES TO PASS, THIS WILL NEED 
    # TO BE CHANGED
    #
    # NOTE: BELOW THE TABLE'S ROOT NAME IS USED WHICH DOES
    # NOT INCLUDE THE SPEEDY_ OR ARCHIVE_ PREFIX!
    $always_new = false;
    $table = "submit";
    $results_idxs_hash[$table . $id] =
        get_scalar(set_data($table, NULL, $always_new, $idx_override), 0);

    # Plug in the _id integer fields in the
    # table (e.g., mpi_get, compiler, and cluster for MPI Install)
    foreach ($phase_indexes as $table) {
        $phase_idxs_hash[$table . $id] =
            set_data($table, NULL, $always_new, $idx_override);
    }

    # Insert the MPI Install, Test Build, or Test Run
    $idx = set_data($phase, $phase_idxs_hash, $always_new, $idx_override);
    $results_idxs_hash["phase$id"] = $idx;
    $results_idxs_hash["phase"] = $phase_smallints[$phase];

    # Plug in more data to the results if there is any (right now that will be
    # only latency_bandwidth data)
    $results_idxs_hash = array_merge($results_idxs_hash, $idxs_hash);

    # Finally, INSERT the results
    $always_new = true;
    $table = "results";
    $phase_idxs_hash[$table . $id] =
        set_data($table, $results_idxs_hash, $always_new, $idx_override);

    return $idx;
}

# 1. Fetch new, existing, or overriding index
# 2. Insert row (merged with $indexes hash) into $table using that index
# 3. Return index used for insertion
function set_data($table, $indexes, $always_new, $idx_override) {

    global $id, $speedy_pfx, $archive_pfx;

    # MAKE SURE TABLE'S SERIAL-INTEGER PAIR
    # FOLLOWS THE table_id NAMING SCHEME
    $table_id = $table . $id;

    $n = $_POST['number_of_results'];

    # Get existing fields from table
    $params = get_table_fields($table);
    $column_names = array_values($params['column_name']);

    # Match up fetched column names with data in the HTTP POST
    $wheres      = array();
    $new_indexes = array();
    $wheres      = get_post_values($column_names);
    $numbered    = are_numbered($column_names);

    $wheres = array_merge($wheres, $indexes);

    $found_match = false;

    # Skip the following "if" statement if this is a new
    # row for each submit, e.g., results
    if (! $always_new) {
        $idx = check_existence($wheres, $params, $table, $numbered);
    }

    $seq_name = $table . "_" . "$table_id" . "_seq";
    $col_name = $table . "." . "$table_id";

    # If we need to manually override the default
    # index, override with idx_override
    if (! is_null($idx_override)) {
        $idx = $idx_override;
    }
    # If there is no matching row in the db,
    # auto-increment the serial value using nextval
    elseif (is_null_($idx)) {

        $ret = fetch_nextvals($idx, $seq_name, $numbered);

        $idx = $ret['idx'];
        $new_indexes = $ret['new_indexes'];

    } else {
        $found_match = true;

        # If the row is in the "archive", then mirror it in
        # the "speedy", otherwise it will get INSERTed below
        mirror_archived_in_speedy($idx, $table);
    }
    $wheres[$table_id] = $idx;

    $inserts = $wheres;

    # If it was not already in the table, insert it
    if (! $found_match or $always_new) {
        for ($i = 0; $i < $n; $i++) {

            # If the row is already in the table, do not 
            # attempt the INSERT
            if (! $new_indexes[$i])
                continue;

            # Prepare a printf format string for the INSERT
            $insert_into1 = "\n\t INSERT INTO %s ";
            $insert_into2 = "\n\t (" . join(",\n\t", array_keys($inserts)) . ") " .
                            "\n\t VALUES ";

            $items = array();
            foreach (array_keys($inserts) as $k) {
                $items[] = quote_(pg_escape_string(get_scalar($inserts[$k], $i))); 
            }
            $insert_into2 .= "\n\t (" . join(",\n\t", $items) . ") \n\t";

            # INSERT the row into both the "speedy" and "archive" tables
            do_pg_query(sprintf($insert_into1, $speedy_pfx . $table) . $insert_into2);
            do_pg_query(sprintf($insert_into1, $archive_pfx . $table) . $insert_into2);

            if (! $numbered)
                break;
        }
    }

    # Return the new or existing index
    return $idx;
}

# array_unique that does not error out when given a scalar
function _array_unique($var) {

    if (is_array($var))
        return array_unique($var);
    elseif (is_scalar($var))
        return array($var);
}

# array_unique that does not error out when given a scalar
function _array_values($var) {

    if (is_array($var))
        return array_values($var);
    elseif (is_scalar($var))
        return array($var);
}

# Return the index(es) of the existing rows that match
# $wheres, otherwise return null
function check_existence($wheres, $params, $table, $numbered) {

    global $id;

    $n = $_POST['number_of_results'];

    # MAKE SURE TABLE'S SERIAL-INTEGER PAIR
    # FOLLOWS THE table_id NAMING SCHEME
    $table_id = $table . $id;

    for ($i = 0; $i < $n; $i++) {

        $select_qry = "\n   SELECT $table_id FROM $table " .
                      "\n\t WHERE \n\t";

        $j = 0;
        $items = array();
        # Seems odd that we iterate over both string and numeric keys here
        foreach (array_keys($wheres) as $k) {
            $items[] = sql_compare($k,
                                    pg_escape_string(get_scalar($wheres[$k], $i)),
                                    $params['data_type'][$j],
                                    $params['column_default'][$j]);
            $j++;
        }

        $select_qry .= join("\n\t AND ", $items);
        $select_qry .= "\n\t ORDER BY $table_id ASC ";
        $select_qry .= "LIMIT 1 ";

        $idx_value = select_scalar($select_qry);

        if (! $numbered) {
            $idx = $idx_value;
            break;
        }
        else
            $idx[$i] = $idx_value;
    }

    return $idx;
}

# Copy archive TABLE rows (keyed by $idx) over to 
# speedy TABLEs
#
# Note: it's possible we could get away with being slobs here,
# and just copy over the small TABLEs wholesale. But we're trying
# to make these speedy TABLEs as efficient as possible, right?
function mirror_archived_in_speedy($indexes, $table) {

    $silent = 1;

    ####################################################
    #
    # Part 1 - Clean sweep of POST
    #
    ####################################################

    # Do a clean sweep of all the POST params and make sure
    # we copy them over to the speedy TABLEs. (This is a
    # safeguard, but is needed at least for the initial
    # INSERTs into the speedy_ TABLEs to avoid FOREIGN KEY
    # constraint errors, since the speedy tables are
    # initially empty!)
    static $prevented_foreign_key_errors = false;

    # Only do the clean sweep *once*
    if (! $prevented_foreign_key_errors) {
        $prevented_foreign_key_errors = true;

        $n = $_POST['number_of_results'];

        # Array of serial values that the client
        # handshakes with
        $tables = array("mpi_install", "test_build");

        foreach ($tables as $t) {
            $wheres = array();

            # WE'RE NOT MIRRORING OVER DEPENDENCIES FROM THE PAST (SO
            # A TEST_BUILD THAT POINTS TO AN OLD OLD MPI INSTALL WILL
            # FAIL ON A FOREIGN KEY CONSTRAINT ERROR, SINCE THE OLD
            # OLD MPI INSTALL NEVER GOT COPIED OVER).  SOMEDAY,
            # PERHAPS, WE SHOULD COVER THIS USE CASE (E.G., FOR
            # --RESUBMIT AND THE LIKE?)
            #
            # $idx_names = get_table_indexes($t);

            # Get column name of the serial  
            $serial = $t . $id;

            # mpi_install_id and test_build_id are
            # NEVER numbered, but *just* in case
            for ($i = 0; $i < $n; $i++) {
                $sfx = ($i == 0) ? null : '_' . $i;

                $value = $_POST[$serial . $sfx];

                if (! is_null($value))
                    $wheres[] = "$serial = $value";
            }

            # Copy over dependent rows that the copied
            # $hash =
            #     associative_select("\n\t SELECT " . join(",", $idx_names) .
            #                   "\n\t   FROM $t " .
            #                   "\n\t   WHERE " . join(" OR \n\t", $wheres) . ";");

            if (sizeof($wheres) > 0) {
                $insert_qry = sprintf($format, $t, $t, join(" OR \n\t", $wheres));
                do_pg_query($insert_qry, $silent);
            }
        }
    }

    ####################################################
    #
    # Part 2 - Copy over a single row
    #
    ####################################################

    global $id, $speedy_pfx, $archive_pfx;

    $wheres = array();

    # MAKE SURE TABLE'S SERIAL-INTEGER PAIR
    # FOLLOWS THE table_id NAMING SCHEME
    $table_id = $table . $id;

    $indexes = _array_unique(_array_values($indexes));

    # Construct an INSERT INTO ... SELECT to copy over
    # archive rows into the speedy table
    $format = "\n   INSERT INTO $speedy_pfx%s " .
              "\n\t   SELECT * FROM $archive_pfx%s WHERE %s;";

    foreach ($indexes as $i) {
        $wheres[] = "$table_id = $i";
    }
    $insert_qry = sprintf($format, $table, $table, join(" OR \n\t", $wheres));

    # We expect many duplicate "errors" to occur here, because
    # we are using the UNIQUE column constraint to prevent
    # duplicates entries (instead of checking with SELCECT,
    # as we do for the archive TABLEs)

    do_pg_query($insert_qry, $silent);
}

function fetch_nextvals($idx, $seq_name, $numbered) {

    $n = $_POST['number_of_results'];

    for ($i = 0; $i < $n; $i++) {
        if (is_null($idx[$i])) {
            $ret['idx'][$i] = select_scalar("SELECT nextval('$seq_name') LIMIT 1;");
            $ret['new_indexes'][$i] = true;
        } else {
            $ret['new_indexes'][$i] = false;
        }
            
        if (! $numbered)
            break;
    }

    return $ret;
}

# Return true if the table contains an integer
# index into another table
function contains_table_key($table_name) {

    $t = array();
    $t = get_table_indexes($table_name, false);
    return (count($t) > 0);
}

function contains_no_table_key($table_name) {
    return ! contains_table_key($table_name);
}

# Recursively gather all indexes linked to $parent. The prune_list is
# used to avoid descending into a part of the schema
function gather_indexes($parent, $child, $idxs, $prune_list) {

    global $id;

    $new_idxs = get_table_indexes($parent, true);

    if (! is_null($child))
        $self = array(
                    $parent . $id => array(
                        'integer' => $child,
                        'serial' => $parent,
                    )
                );
    else
        $self = NULL;

    $prune = false;
    foreach ($prune_list as $pattern)
        if (strstr($parent, $pattern))
            $prune = true;


    if ((count($new_idxs) > 0) and ! $prune) {

        foreach ($new_idxs as $idx) {
            $t = array();
            $t = gather_indexes(get_idx_root($idx), $parent, $idxs, $prune_list);

            $idxs = array_merge(
                                $self,
                                $t,
                                $idxs
                    );
        }
    }
    else {
        return $self;
    }

    return $idxs;
}

function sql_join($table_name) {
    global $id;
    return "JOIN $table_name USING (" . $table_name . $id . ")";
}

# X: maybe a misnomer, since this function doesn't involve database
# indexes, but rather the pointers to other tables set up for this schema
function get_table_indexes($table_name, $qualified) {

    global $id;
    global $dbname;

    # Crude way to tell whether a field is an index
    $is_index_clause = "\n\t (data_type = 'integer' AND " .
                       "\n\t column_name ~ '$id$' AND " .
                       "\n\t column_default !~ 'nextval' AND " .
                       "\n\t table_catalog = '$dbname')";

    $select = "column_name";

    $sql_cmd = "\n   SELECT $select as index " .
               "\n\t FROM information_schema.columns WHERE " .
               "\n\t table_name = '$table_name' AND " . $is_index_clause . ';';

    do_pg_connect();
    return simple_select($sql_cmd);
}

# Function used to determine which _POST fields
# to INSERT. Prevent non-existent fields from being
# INSERTed
function get_table_fields($table_name) {

    global $dbname;
    global $id;

    # These indexes are special in that they link phases
    # together and hence, can and do show up in _POST
    if ($table_name == "test_build")
        $special_indexes = array("mpi_install$id");
    elseif ($table_name == "test_run")
        $special_indexes = array("test_build$id");

    # Crude way to tell whether a field is an index
    $is_not_index_clause =
           "\n\t (table_name = '$table_name' AND NOT " .
           "\n\t (data_type = 'integer' AND " .
           "\n\t column_name ~ '_id$' AND " .
           "\n\t table_catalog = '$dbname'))";

    $is_special_index_clause = 
           "\n\t (table_name = '$table_name' AND " .
           "\n\t (column_name = '$special_indexes[0]'))";

    $is_index_columns = array(
            "column_name",
            "data_type",
            "column_default");

    $sql_cmd = "\n   SELECT " . join(",",$is_index_columns) .
               "\n\t FROM information_schema.columns WHERE " .
               "\n\t " . 
                     $is_not_index_clause . " OR " .
                     $is_special_index_clause . ';';

    do_pg_connect();

    # This table will be easier to manage if it's
    # keyed by column, instead of index
    $tmp = array();
    $arr = array();
    $arr = select($sql_cmd);

    foreach ($is_index_columns as $col) {
        $tmp[$col] = array();
        for ($i = 0; $i < sizeof($arr); $i++) {
            $tmp[$col][] = $arr[$i][$col];
        }
    }
    return $tmp;
}

# Check fields in the POST that are not in the DB
function report_non_existent_fields() {

    global $dbname;

    $sql_cmd = "\n   SELECT column_name " .
               "\n\t FROM information_schema.columns " . 
               "\n\t WHERE table_schema = 'public'";

    do_pg_connect();

    $arr = array();
    $arr = simple_select($sql_cmd);
    $arr = array_flip($arr);

    # Iterate through POST, and report names that are not 
    # columns in the database
    foreach (array_keys($_POST) as $k) {

        # We only need to check the first numbered field
        if (preg_match("/_(\d+)$/", $k, $m)) {
            $n = $m[1];
            if ($n > 1)
                continue;
        }
        $name = preg_replace('/_\d+$/', '', $k);
        if (! $arr[$name])
            mtt_notice("$name is not in $dbname database.");
    }
}

# Take an array or scalar
function get_scalar($var , $i) {

    if (is_array($var))
        return $var[$i];
    else
        return $var;
}

######################################################################

# Return either var, or [elem1, elem2, ... elemn]
function stringify($var) {
    if (is_array($var))
        if (is_numeric_($var))
            return join(",",$var);
        else
            return $var;
    else
        return $var;
}

# Check for numeric array
function is_numeric_($ar) {
    $keys = array_keys($ar);
    natsort($keys); # String keys will be last
    return is_int(array_pop($keys));
}

# Return true if it's a NULL or an array containing a single NULL
function is_null_($var) {

    if (is_null($var))
        $ret = true;
    elseif (is_array($var))
        foreach ($var as $v)
            if (is_null($v)) {
                $ret = true;
                break;
            }
    else
        $ret = false;

    return $ret;
}

######################################################################

function do_pg_connect() {

    global $dbname;
    global $user;
    global $pass;
    global $pgsql_conn;
    static $connected = false;

    if (!$connected) {
        $pgsql_conn =
            pg_connect("host=localhost port=5432 dbname=$dbname user=$user password=$pass");

        # Exit if we cannot connect
        if (!$pgsql_conn)
            mtt_abort("\nCould not connect to the $dbname database; " .
                      "submit this run later.");
        else
            $connected = true;

        # pg_set_error_verbosity($pgsql_conn, PGSQL_ERRORS_VERBOSE); # PHP 5 needed
        # pg_trace($_ENV['HOME'] . "/pgsql.trace", 'w', $pgsql_conn);
        # debug("\npg_options: " . var_export(pg_options($pgsql_conn)));
    }
}

function do_pg_query($cmd, $silent) {

    do_pg_connect();

    debug("\nSQL: $cmd\n");
    if (! ($db_res = pg_query($cmd))) {
        $out = "\nSQL QUERY: " . $cmd .
               "\nSQL ERROR: " . pg_last_error() .
               "\nSQL ERROR: " . pg_result_error();

        # Some errors are unsurprising, allow for silence in
        # such cases
        if (! $silent) {
            mtt_error($out);
            mtt_send_mail($out);
        }
    }
    debug("\nDatabase rows affected: " . pg_affected_rows($db_res) . "\n");
}

# Fetch scalar value
function select_scalar($cmd) {

    $set = array();
    $set = simple_select($cmd);
    return array_shift($set);
}

# Fetch 1D array
function simple_select($cmd) {

    do_pg_connect();

    $rows = null;

    debug("\nSQL: $cmd\n");
    if (! ($result = pg_query($cmd))) {
        $out = "\nSQL QUERY: " . $cmd .
               "\nSQL ERROR: " . pg_last_error() .
               "\nSQL ERROR: " . pg_result_error();
        mtt_error($out);
        mtt_send_mail($out);
    }
    $max = pg_num_rows($result);
    for ($i = 0; $i < $max; ++$i) {
        $row = pg_fetch_array($result, $i, PGSQL_NUM);
        $rows[] = $row[0];
    }
    return $rows;
}

# Fetch an associative hash (column name => value)
function associative_select($cmd) {

    do_pg_connect();

    debug("\nSQL: $cmd\n");
    if (! ($result = pg_query($cmd))) {
        $out = "\nSQL QUERY: " . $cmd .
               "\nSQL ERROR: " . pg_last_error() .
               "\nSQL ERROR: " . pg_result_error();
        mtt_error($out);
        mtt_send_mail($out);
    }
    return pg_fetch_array($result);
}

# Fetch 2D array
function select($cmd) {
    do_pg_connect();

    debug("\nSQL: $cmd\n");
    if (! ($result = pg_query($cmd))) {
        $out = "\nSQL QUERY: " . $cmd .
               "\nSQL ERROR: " . pg_last_error() .
               "\nSQL ERROR: " . pg_result_error();
        mtt_error($out);
        mtt_send_mail($out);
    }
    return pg_fetch_all($result);
}

######################################################################

# Function for reporting errors back to the client
function mtt_abort($status, $str) {
    if (!headers_sent()) {
        header("HTTP/1.0 $status");
    } else {
        print("MTTDatabase abort: (Tried to send HTTP error) $status\n");
    }
    print("MTTDatabase abort: $str\n");
    exit(0);
}

# Function for reporting errors back to the client
function mtt_error($str) {
    print("MTTDatabase server error: $str\n");
}

# Function for reporting notices back to the client
function mtt_notice($str) {
    print("MTTDatabase server notice: $str\n");
}

function mtt_send_mail($str) {

    # Send only one email per phase to avoid a hurricane of
    # SQL error emails (generally in this case, when it
    # rains it pours here)
    static $sent_mail = false;

    if ($sent_mail)
        return;

    $php_auth_user = $_SERVER['PHP_AUTH_USER'];

    # Initialize To: addresses
    $user    = $_POST['email'];
    $admin   = 'ethan.mallove@sun.com';
    $headers = "From: $admin\r\n" .
               "Reply-To: $admin\r\n";

    # Email the MTT database administrator
    mail($admin, "MTT server error (user: $php_auth_user)", $str, $headers);

    # Email the user of the offending MTT client
    if ($user)
        mail($user, "MTT server error", $str, $headers);

    $sent_mail = true;
}

######################################################################

# Quote non-sql-key-words
function quote_($str) {
    if (! is_sql_key_word($str))
        return "'" . $str . "'";
    else
        return "$str";
}

# Return true if this is an sql keyword (that should not be quoted)
function is_sql_key_word($str) {

    $key_words = array(
        "DEFAULT",
        "NULL",
    );

    if (preg_match("/^\s*(" . join("|", $key_words) . ")\s*$/i", $str))
        return true;
    else
        return false;
}

# Take param value
# Return param = 'value'
function sql_compare($param, $value, $type, $default) {

    $default = preg_replace('/::.*$/', '', $default);

    if (preg_match("/'([^']*)'/", $default, $m))
        $default = $m[1];

    # X: Replace this block to use some sort of
    # is_default(x) postgres stored procedure
    if (strstr($type, "timestamp"))
        $clause = 'true';           # This allows us to recycle a row
    elseif (strstr($type, "serial"))
        $clause = 'true';           # This allows us to recycle a row

    # When doing comparisons in a SELECT statement we cannot
    # use the DEFAULT key word, we have to provide the
    # actual value of the DEFAULT
    elseif (strstr($value, "DEFAULT"))
        $clause = "$param = '$default'";
    else
        $clause = "$param = " . quote_($value);

    return $clause;
}

# Take foo_id, return foo
function get_idx_root($str) {
    return preg_replace('/_id$/', '', $str);
}

# Args: parameters to fetch from _POST
# Return: associateive array of field=value pairs

# Three types of POST params:
# 
# 1 Once set (not numbered)
# 2 Always set (each and every param, 1-num_of_results are set)
# 3 Sometimes set (some names are set)

# A "some_set" field is a field that may be present in
# only several tests in a given submission (e.g., latency_min)
# Only a numbered field can be a some_set
#
# 1. Determine the some_sets
# 2. Fill in the name/value pairs, and use DEFAULT if 
#    it is a some_set

function get_post_values($params) {

    $n = $_POST['number_of_results'];

    $hash = array();
    $some_set = array();

    # Determine some_sets
    foreach ($params as $field) {
        for ($i = 1; $i <= $n; $i++) {
            $name = $field . (($i == 0) ? "" : "_" . $i);
            if (isset($_POST[$name])) {
                $some_set[$field] = true;
            }
        }
    }

    foreach ($params as $field) {

        $found_value = false;
        $numbered = false;

        for ($i = 0; $i <= $n; $i++) {

            $name = $field . (($i == 0) ? "" : "_" . $i);
            $numbered = (($i == 0) ? false : true);

            if (isset($_POST[$name])) {

                $value       = $_POST[$name];
                $found_value = true;

                if ($numbered) {
                    $hash[$field][] = $value;
                }
                else {
                    $hash[$field] = $value;
                    break;
                } 
            }
            elseif (isset($some_set[$field]) and $numbered) {
                $hash[$field][] = "DEFAULT";
            }
        }
        # We could leave this out and the field would insert to DEFAULT,
        # let's explicitly INSERT DEFAULT for now
        if (! $found_value) {
            $hash[$field] = "DEFAULT";
        }
    }
    return $hash;
}

# Args: params (which presumably map to a single db table)
# Return: true if it contains a numbered field in HTTP input
function are_numbered($params) {

    $n = $_POST['number_of_results'];

    foreach ($params as $field) {
        for ($i = 1; $i <= $n; $i++) {
            $name = $field . "_" . $i;
            if (isset($_POST[$name])) {
                $ret = true;
                break 2;
            }
        }
    }
    return $ret;
}

# For returning to the client (so we can keep
# track of MTT client invocations)
function get_serial() {

    # Works in psql cli, *BROKEN* in php
    # $cmd =  "\n   SELECT relname FROM pg_class WHERE " .
    #         "\n\t relkind = 'S' AND " .
    #         "\n\t relnamespace IN ( " .
    #         "\n\t SELECT oid FROM pg_namespace WHERE " .
    #         "\n\t nspname NOT LIKE 'pg_%' AND " .
    #         "\n\t nspname != 'information_schema') " .
    #         "\n\t AND relname NOT LIKE '%id_seq';";
    #
    # $serial_name = select_scalar($cmd);

    $serial_name = 'client_serial';
    $serial      = select_scalar("SELECT nextval('$serial_name');");

    return $serial;
}

# Special debug routine to audit INSERT statements
function var_dump_debug_inserts($function, $line, $var_name, $arr) {

    if ($GLOBALS['verbose'] or $GLOBALS['debug']) {
        $output = "\ndebug: $function:$line, $var_name = ";
        foreach (array_keys($arr) as $k) {
            $output .= "\n\t '$k' => '" . 
                    (is_array($arr[$k]) ?
                        join(",", $arr[$k]) :
                        $arr[$k])
                    . "'";
        }
        print($output);
    }
}
