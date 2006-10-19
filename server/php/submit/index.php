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
$dbname             = isset($_GET['db'])       ? $_GET['db']       : "mtt2";

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
if (! isset($_POST['mtt_version_major']) ||
    ! isset($_POST['mtt_version_minor'])) {
    mtt_error(400, "\nClient version not specified.");
    exit(1);
}

# Who is submitting?  Note: PHP_AUTH_USER index is
# not set if .htaccess file is absent
$_POST['http_username'] =
        isset($_SERVER['PHP_AUTH_USER']) ?
        $_SERVER['PHP_AUTH_USER'] : "";

$id = "_id";

# This should be a condition on a _POST hash
# E.g., test_type => (correctness or latency_bandwidth)
if ($_POST['test_type'] != 'latency_bandwidth')
    $idxs_hash["latency_bandwidth$id"] = '-1';

# This index is for reporting on "new" failures,
# and will get updated by a nightly churn script (see #70)
$idxs_hash["failure$id"] = '-1';

# What phase are we doing?
$phase      = strtolower($_POST['phase']);
$phase_name = preg_replace('/^\s+|\s+$/', '', $phase);
$phase_name = preg_replace('/\s+/', '_', $phase);

$phase_smallints = array(
    "mpi_install" => 1,
    "test_build" => 2,
    "test_run" => 3,
);

if (0 == strcasecmp($phase, "test run")) {

    $idx = process_phase($phase_name, $idxs_hash);
    validate($phase_name, array("mpi_install", "test_build", "failure"));

} else if (0 == strcasecmp($phase, "test build")) {

    $idx = process_phase($phase_name, $idxs_hash);
    validate($phase_name, array("mpi_install", "failure"));

} else if (0 == strcasecmp($phase, "mpi install")) {

    $idx = process_phase($phase_name, $idxs_hash);
    validate($phase_name, array("failure"));

} else {
    print "ERROR: Unknown phase! ($phase)<br>\n";
    mtt_error(400, "\nNo phase given, so I don't know which table to direct this data to.");
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
                       get_table_indexes($phase, $fully_qualified)),
            'contains_no_table_key');

    $always_new = false;
    $table = "submit";
    $results_idxs_hash[$table . $id] =
        set_data($table, NULL, $always_new, $idx_override);

    foreach ($phase_indexes as $table) {
        $phase_idxs_hash[$table . $id] =
            set_data($table, NULL, $always_new, $idx_override);
    }

    $idx = set_data($phase, $phase_idxs_hash, $always_new, NULL);
    $results_idxs_hash["phase$id"] = $idx;
    $results_idxs_hash["phase"] = $phase_smallints[$phase];

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

    global $_POST;
    global $id;

    # MAKE SURE TABLE'S SERIAL-INTEGER PAIR
    # FOLLOWS THE table_id NAMING SCHEME
    $table_id = $table . $id;

    # Get existing fields from table
    $params = get_table_fields($table);
    $column_names = array_values($params['column_name']);

    $n = $_POST['number_of_results'];

    # Match up fetched column names with data in the HTTP POST
    $wheres   = array();
    $wheres   = get_post_values($column_names, $n);
    $numbered = are_numbered($column_names, $n);

    $wheres   = array_merge($wheres, $indexes);

    # Skip the following block if this is a new
    # row for each submit, e.g., results
    if (! $always_new) {

        $found_match = false;

        $wheres_tmp = $wheres;

        for ($i = 0; $i < $n; $i++) {

            $select_qry = "\n   SELECT $table_id FROM $table " .
                          "\n\t WHERE \n\t";

            $j = 0;
            $items = array();
            # Seems odd that we iterate over both string and numeric keys here
            foreach (array_keys($wheres_tmp) as $k) {
                $items[] = sql_compare($k,
                                        pg_escape_string(get_scalar($wheres_tmp[$k])),
                                        $params['data_type'][$j],
                                        $params['column_default'][$j]);
                $j++;
            }

            $select_qry .= join("\n\t AND ", $items);
            $select_qry .= "\n\t ORDER BY $table_id DESC;"; # Extraneous?

            $set = array();
            $set = simple_select($select_qry);

            if (! $numbered) {
                $idx = array_shift($set);
                break;
            }
            else
                $idx[] = array_shift($set);
        }
    }

    # If we need to manually override the default
    # index, override with idx_override
    if (! is_null($idx_override)) {
        $idx = $idx_override;
    }
    # If there is no matching row in the db,
    # auto-increment the serial value using nextval
    elseif (is_null_($idx)) {

        $idx_tmp = $idx;
        for ($i = 0; $i < $n; $i++) {
            if (is_null($idx[$i])) {
                $set = array();
                $set = simple_select("SELECT nextval('$table" . "_" . "$table_id" . "_seq');");
                $idx_tmp[$i] = array_shift($set);
            }
            if (! $numbered)
                break;
        }
        $idx = $idx_tmp;

    } else {
        $found_match = true;
    }
    $wheres[$table_id] = $idx;

    $inserts = $wheres;

    # If it was not already in the table, insert it
    if (! $found_match or $always_new) {
        for ($i = 0; $i < $n; $i++) {
            $insert_qry = "\n\t INSERT INTO $table " .
                          "\n\t (" . join(",\n\t", array_keys($inserts)) . ") " .
                          "\n\t VALUES ";

            $items = array();
            foreach (array_keys($inserts) as $k) {
                $items[] = quote_(pg_escape_string(get_scalar($inserts[$k]))); 
            }
            $insert_qry .= "\n\t (" . join(",\n\t", $items) . ") \n\t";

            do_pg_query($insert_qry);

            if (! $numbered)
                break;
        }
    }

    var_dump_debug(__FUNCTION__, __LINE__, "return val", stringify($idx));

    # Return the new or existing index
    return $idx;
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

# Execute a JOINing query (use table1.id = table2.id syntax)
# for an entire phase row, and dump the table
function validate($table_name, $prune_list) {

    global $id;

    $idxs = gather_indexes($table_name, NULL, NULL, $prune_list);

    $cmd .= "\n\t SELECT * FROM " .
            "\n\t " . $table_name . "," .
            "\n\t " . join(",\n\t\t", array_map('get_idx_root', array_keys($idxs))) .
            "\n\t WHERE";

    foreach (array_keys($idxs) as $idx) {
        $wheres[] = $idxs[$idx]['serial'] .'.'.$idx . ' = ' .
                    $idxs[$idx]['integer'].'.'.$idx;
    }

    $cmd .= "\n\t " . join(" AND \n\t", $wheres);
    $cmd .= "\n\t ORDER BY $table_name$id;";

    $rows = select($cmd);

    var_dump_debug(__FUNCTION__, __LINE__, "rows", $rows);
}

function sql_join($table_name) {
    global $id;
    return "JOIN $table_name USING (" . $table_name . $id . ")";
}

# X: maybe a misnomer, since this function doesn't involve database
# indexes, but rather the pointers to other tables set up for this schema
function get_table_indexes($table_name, $qualified) {

    global $id;
    global $is_index_clause;
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
           "\n\t (column_name = '$special_indexes[0]' OR " .
           "\n\t column_name = '$special_indexes[1]'))";

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

# Take an array or scalar
function get_scalar(&$var) {

    if (is_array($var))
        return array_shift($var);
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
    static $connected = false;

    if (!$connected) {
        $pgsql_conn = pg_connect("host=localhost port=5432 dbname=$dbname user=$user password=$pass");
        $connected = true;
        pg_trace('/tmp/trace.log', 'w', $pgsql_conn);
    }
}

function do_pg_query($cmd) {
    do_pg_connect();

    debug("\nSQL: $cmd\n");
    if (! ($db_res = pg_query($cmd))) {
        debug("\npostgres: " . pg_last_error() . "\n" . pg_result_error());
    }
}

# Fetch 1D array
function simple_select($cmd) {
    do_pg_connect();

    $rows = null;

    debug("\nSQL: $cmd\n");
    if (! ($result = pg_query($cmd))) {
        debug("\npostgres: " . pg_last_error() . "\n" .
                  pg_result_error());
    }
    $max = pg_num_rows($result);
    for ($i = 0; $i < $max; ++$i) {
        $row = pg_fetch_array($result, $i, PGSQL_NUM);
        $rows[] = $row[0];
    }
    return $rows;
}

# Fetch 2D array
function select($cmd) {
    do_pg_connect();

    debug("\nSQL: $cmd\n");
    if (! ($result = pg_query($cmd))) {
        debug("\npostgres: " . pg_last_error() . "\n" .
                  pg_result_error());
    }
    return pg_fetch_all($result);
}

######################################################################

# Function for reporting errors back to the client
function mtt_error($status, $str) {
    if (!headers_sent()) {
        header("HTTP/1.0 $status");
    } else {
        print("ERROR: (Tried to send HTTP error) $status\n");
    }
    print("ERROR: $str\n");
    exit(0);
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
function get_post_values($params, $n) {

    global $_POST;

    $hash = array();

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
function are_numbered($params, $n) {

    global $_POST;

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
    $cmd =  "\n   SELECT relname FROM pg_class WHERE " .
            "\n\t relkind = 'S' AND " .
            "\n\t relnamespace IN ( " .
            "\n\t SELECT oid FROM pg_namespace WHERE " .
            "\n\t nspname NOT LIKE 'pg_%' AND " .
            "\n\t nspname != 'information_schema') " .
            "\n\t AND relname NOT LIKE '%id_seq';";

    $set         = array();
    $set         = simple_select($cmd);
    $serial_name = array_shift($set);

    $serial_name = 'client_serial';
    $set         = simple_select("SELECT nextval('$serial_name');");
    $serial      = array_shift($set);

    return $serial;
}

# Special debug routine to audit INSERT statements
function var_dump_debug_inserts($function, $line, $var_name, $arr) {

    if ($GLOBALS['verbose'] or $GLOBALS['debug']) {
        $output = "\ndebug: $function:$line, $var_name = ";
        foreach (array_keys($arr) as $k) {
            $output .= "\n\t '$k' => '" . get_scalar($arr[$k]) . "'";
        }
        print($output);
    }
}
