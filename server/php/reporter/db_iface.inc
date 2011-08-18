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

$nl   = "\n\t";
$nlt  = "\n\t";
$nltt = "\n\t\t";

function db_iface_compose_sql_select($query, $report_type) {
    $sql_cmd = "";

    #print "<pre>".print_r($query, true)."</pre>\n";

    #
    # Detail:
    # Use old query mechanism
    #
    if ($report_type == 'detail') {
        $ret = compose_sql_select($query);
    }
    #
    # Performance:
    # Use old query mechanism
    #
    elseif ($report_type == 'performance') {
        $ret = compose_sql_select($query);
    }
    #
    # Summary:
    #
    else {
        #
        # All Phases
        #
        if( count($query['phases']) > 1 ) {
            $sql_cmd = INTERNAL_db_iface_compose_sql_summary_all($query);
            $ret['sql_cmd'] = $sql_cmd;
        }
        #
        # Single Phase:
        # Use the old mechanism
        #
        else {
            $ret = compose_sql_select($query);
        }
    }
    #print "<pre>\n$sql_cmd\n</pre>";
    #exit;

    return $ret;
}

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
function INTERNAL_db_iface_compose_sql_summary_all($query) {
    global $nlt, $nltt;

    $sql_cmd = "";
    $sql_cmd_debug = "";

    $selects = array_unique(
        array_merge(
            $query['select'],
            $aggregates,
            $query['select_more'],
            $query['performance']
        )
    );
    # Skip the 'row number'
    unset($query['select']['n']);

    $needed_tables = array();
    $needed_idxs   = array();
    $tmp;
    foreach (array_keys($selects) as $column) {
        $tmp = is_needed_w_index($column, $needed_tables);
        if( null != $tmp ) {
            $needed_tables[] = $tmp[0];
            $needed_idxs[] = $tmp[1];
        }
    }

    #
    # Some Debugging Options
    #
    $explain      = isset($_GET['explain'])      ? 1 : 0;
    $analyze      = isset($_GET['analyze'])      ? 1 : 0;
    if ($explain) {
        $sql_cmd_debug .= "EXPLAIN\n";
    }
    if ($analyze) {
        $sql_cmd_debug .= "ANALYZE\n";
    }

    #
    # SELECT
    #
    $sql_cmd .= "SELECT";
    foreach ($selects as $item ) {
        $sql_cmd .= $nlt . $item . ",";
    }
    $sql_cmd .= $nlt;
    $sql_cmd .= join(",$nlt", $query['aggregates']);
    $sql_cmd .= "\n";

    #
    # FROM
    #
    $sql_cmd .= "FROM ($nlt";

    #
    # Get the phase tables for this date range
    #
    $table_mpi_install = INTERNAL_db_iface_compose_sql_summary_mpi_install($query);
    $table_test_build  = INTERNAL_db_iface_compose_sql_summary_test_build($query);
    $table_test_run    = INTERNAL_db_iface_compose_sql_summary_test_run($query);

    $sql_cmd .= "($nlt";
    $sql_cmd .= $table_mpi_install;
    $sql_cmd .= ")\n";

    $sql_cmd .= "UNION ALL$nlt";

    $sql_cmd .= "($nlt";
    $sql_cmd .= $table_test_build ."$nlt";
    $sql_cmd .= ")\n";

    $sql_cmd .= "UNION ALL$nlt";

    $sql_cmd .= "($nlt";
    $sql_cmd .= $table_test_run ."$nlt";
    $sql_cmd .= ")\n";

    $sql_cmd .= ") as summary\n";

    #
    # Tables to join with
    #
    foreach ($needed_tables as $tbl) {
        $sql_cmd .= $nlt."NATURAL JOIN $tbl";
    }

    #
    # Group By
    #
    $groupbys = array_unique(
        array_merge(
            array_keys($query['select']),
            array_keys($query['select_more']),
            array_keys($query['performance'])
        )
    );

    $sql_cmd .= "\n";
    if (array_keys($query['select'])) {
        $sql_cmd .= "GROUP BY " .$nlt;
        $sql_cmd .= join(",$nlt", $groupbys);
    }

    #
    # Order by
    #
    $orderbys =  array_unique(
        array_merge(
            array_keys($query['select'])
        )
    );

    $sql_cmd .= "\n";
    if (array_keys($query['select'])) {
        $sql_cmd .= "ORDER BY " .$nlt;
        $sql_cmd .= join(",$nlt", $orderbys)."\n";;
    }

    #
    # Row Numbers and offsets
    #
    if (array_keys($query['select'])) {
        if( isset($_GET['rows'] ) ) {
            $limit  = LIMIT;
            $sql_cmd .= "\nLIMIT $limit";
        }

        $offset = offset($query);
        $sql_cmd .= "\nOFFSET $offset";
    }

    $sql_cmd .= ";";

    if ($explain || $analyze) {
        $sql_cmd_debug .= $sql_cmd;

        $resource = do_pg_query($sql_cmd_debug);
        $arr = pg_fetch_all($resource);

        foreach (array_keys($arr) as $i) {
            foreach ($arr[$i] as $line) {
                $plan[] = $line;
            }
        }

        $filename = 'tmp/' . params2filename($_GET) . '.txt';
        $plan_txt = join("\n", $plan);

        # Write plan to a file (for right-click Save)
        write_to_file($filename, $plan_txt);

        # Write plan to browser
        debug_sql($plan_txt, 0);
        debug_sql($sql_cmd_debug, 0);

        $top = DOCROOT;

        print "<br><a href='$top/$filename'>Query plan</a>";

    }
    return $sql_cmd;
}

function INTERNAL_db_iface_compose_sql_summary_mpi_install($query) {
    global $nlt, $nltt;

    $sql_cmd .= "SELECT$nltt";

    #
    # Find necessary selects
    #
    $selects = array_unique(
        array_merge(
            $query['select'],
            $aggregates,
            $query['select_more'],
            $query['performance']
        )
    );
    # Skip the 'row number'
    unset($query['select']['n']);

    $needed_tables = array();
    $needed_idxs   = array();
    $tmp;
    foreach (array_keys($selects) as $column) {
        $tmp = is_needed_w_index($column, $needed_tables);
        if( null != $tmp ) {
            $needed_tables[] = $tmp[0];
            $needed_idxs[] = $tmp[1];
        }
    }

    $sql_cmd .= "trial,".$nltt;
    foreach($needed_idxs as $idx ) {
        $sql_cmd .= "$idx,".$nltt;
    }

    #
    # Aggregation fields
    #
    $sql_cmd .= join(",$nltt", $query['cases']['mpi_install']).$nlt;

    #
    # FROM
    #
    $sql_cmd .= "FROM mpi_install".$nlt;

    #
    # WHERE
    #
    $sql_cmd .= "WHERE ".$nltt;
    $sql_cmd .= "(start_timestamp > '".$query['absolute_start'][0]."' AND ";
    $sql_cmd .= " start_timestamp < '".$query['absolute_end'][0]."')".$nltt;
    if(isset($query['where']['trial'])) {
        $sql_cmd .= "AND ";
        $sql_cmd .= $query['where']['trial'] .$nlt;
    }

    return $sql_cmd;
}

function INTERNAL_db_iface_compose_sql_summary_test_build($query) {
    global $nlt, $nltt;

    $sql_cmd .= "SELECT$nltt";

    #
    # Find necessary selects
    #
    $selects = array_unique(
        array_merge(
            $query['select'],
            $aggregates,
            $query['select_more'],
            $query['performance']
        )
    );
    # Skip the 'row number'
    unset($query['select']['n']);

    $needed_tables = array();
    $needed_idxs   = array();
    $tmp;
    foreach (array_keys($selects) as $column) {
        $tmp = is_needed_w_index($column, $needed_tables);
        if( null != $tmp ) {
            $needed_tables[] = $tmp[0];
            $needed_idxs[] = $tmp[1];
        }
    }

    $sql_cmd .= "trial,".$nltt;
    foreach($needed_idxs as $idx ) {
        $sql_cmd .= "$idx,".$nltt;
    }

    #
    # Aggregation fields
    #
    $sql_cmd .= join(",$nltt", $query['cases']['test_build']).$nlt;

    #
    # FROM
    #
    $sql_cmd .= "FROM test_build".$nlt;

    #
    # WHERE
    #
    $sql_cmd .= "WHERE ".$nltt;
    $sql_cmd .= "(start_timestamp > '".$query['absolute_start'][0]."' AND ";
    $sql_cmd .= " start_timestamp < '".$query['absolute_end'][0]."')".$nltt;
    if(isset($query['where']['trial'])) {
        $sql_cmd .= "AND ";
        $sql_cmd .= $query['where']['trial'] .$nlt;
    }

    return $sql_cmd;
}

function INTERNAL_db_iface_compose_sql_summary_test_run($query) {
    global $nlt, $nltt;

    $sql_cmd .= "SELECT$nltt";

    #
    # Find necessary selects
    #
    $selects = array_unique(
        array_merge(
            $query['select'],
            $aggregates,
            $query['select_more'],
            $query['performance']
        )
    );
    # Skip the 'row number'
    unset($query['select']['n']);

    $needed_tables = array();
    $needed_idxs   = array();
    $tmp;
    foreach (array_keys($selects) as $column) {
        $tmp = is_needed_w_index($column, $needed_tables);
        if( null != $tmp ) {
            $needed_tables[] = $tmp[0];
            $needed_idxs[] = $tmp[1];
        }
    }

    $sql_cmd .= "trial,".$nltt;
    foreach($needed_idxs as $idx ) {
        $sql_cmd .= "$idx,".$nltt;
    }

    #
    # Aggregation fields
    #
    $sql_cmd .= join(",$nltt", $query['cases']['test_run']).$nlt;

    #
    # FROM
    #
    $sql_cmd .= "FROM test_run".$nlt;

    #
    # WHERE
    #
    $sql_cmd .= "WHERE ".$nltt;
    $sql_cmd .= "(start_timestamp > '".$query['absolute_start'][0]."' AND ";
    $sql_cmd .= " start_timestamp < '".$query['absolute_end'][0]."')".$nltt;
    if(isset($query['where']['trial'])) {
        $sql_cmd .= "AND ";
        $sql_cmd .= $query['where']['trial'] .$nlt;
    }

    return $sql_cmd;
}

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------

# Compose an SQL SELECT statement
function compose_sql_select($query) {
    global $nl;

    $selects = array();


    # Process SQL params
    $dynamic_view = isset($_GET['dynamic_view']) ? 1 : 0;
    $static_view  = isset($_GET['static_view'])  ? 1 : 0;
    $explain      = isset($_GET['explain'])      ? 1 : 0;
    $analyze      = isset($_GET['analyze'])      ? 1 : 0;

    #
    # Handle ORDER BY
    #
    if (isset($query['orderby_up'])) {
        $orderby = $query['orderby_up'];
    }
    elseif (isset($query['orderby_down'])) {
        $orderby = $query['orderby_down'] . ' DESC';
    }

    #
    # Handle LIMIT + OFFSET
    #
    $offset = offset($query);
    $limit  = LIMIT;

    #
    # Select or create a VIEW to tally the results in
    #
    $phases = $query['phases'];

    foreach (array_keys($query['aggregates']) as $aggregate) {
        $aggregates[] = $query['aggregates'][$aggregate];
    }

    #
    # Compile values for SELECT, GROUP BY,
    # and ORDER BY, and LIMIT clauses
    #
    # (NOTE: SELECTs MUST BE ORDERED LIKE SO FOR *_table FUNCTIONS)
    #
    $selects = array_unique(
        array_merge(
            $query['select'],
            $aggregates,
            $query['select_more'],
            $query['performance']
        )
    );

    #
    # Do not GROUP BY or ORDER BY row number
    #
    unset($query['select']['n']);

    $groupbys = array_unique(
        array_merge(
            array_keys($query['select']),
            array_keys($query['select_more']),
            array_keys($query['performance'])
        )
    );

    $orderbys =  array_unique(
        array_merge(
            array_keys($query['select'])
        )
    );

    #
    # Splice out orderby's old position, and place
    # it at the front of the ORDER BY clause
    #
    if ($orderby) {
        for ($i = 0; $i < sizeof($orderbys); $i++) {
            if ($orderbys[$i] == $orderby) {
                array_splice($orderbys, $i, 1);
                break;
            }
        }
        array_unshift($orderbys, $orderby . $direction);
    }

    if ($explain) {
        $ex_cmd .= "\n EXPLAIN ";
    }

    if ($analyze) {
        $ex_cmd .= "\n ANALYZE ";
    }

    $cmd .= "\n SELECT " .
            "$nl" . join(",$nl", $selects);

    $cmd .= "\n";
    $cmd .= " FROM (\n";
    $cmd .= compose_sql_select_from($query);
    $cmd .= " ) as summary\n";

    if (array_keys($query['select'])) {
        $cmd .= "\n GROUP BY " .
                "$nl" . join(",$nl ", $groupbys);

        $cmd .= "\n ORDER BY " .
                "$nl" . join(",$nl ", $orderbys) .
                "$nl $direction";

        if( isset($_GET['rows'] ) ) {
            $cmd .= "\nLIMIT $limit";
        }
        $cmd .= "\nOFFSET $offset";
    }

    $cmd .= ";";

    if($explain) {
        $ex_cmd .= $cmd;
        $resource = do_pg_query($ex_cmd);
        $arr = pg_fetch_all($resource);

        foreach (array_keys($arr) as $i) {
            foreach ($arr[$i] as $line) {
                $plan[] = $line;
            }
        }

        $filename = 'tmp/' . params2filename($_GET) . '.txt';
        $plan_txt = join("\n", $plan);

        # Write plan to a file (for right-click Save)
        write_to_file($filename, $plan_txt);

        # Write plan to browser
        debug_sql($plan_txt, 0);
        debug_sql($ex_cmd, 0);

        $top = DOCROOT;

        print "<br><a href='$top/$filename'>Query plan</a>";
    }
    $ret['sql_cmd'] = $cmd;

    return $ret;
}

function compose_sql_select_from_select($query) {
    $where_items = array_unique( array_merge (
            $query['where'],
            $query['where_not']
            ) );

    $accum = array();

    # Add 'where' items to the select, so we can 'where' on them
    foreach($where_items as $w ) {    
        $w = preg_replace("/\(/", "", $w);
        $w = preg_replace("/\)/", "", $w);
        $keys = preg_split("/\s+/", $w);

        if( column_exists_any($keys[0]) ) {
            $accum[] = $keys[0];
        }
    }

    # Use the string functions in the subquery (not the outer query!)
    # If we use the string functions in the outer query, the GROUP BY
    # does not give the desired effect on the large and timestamp columns
    $select_keys = array_merge(
        array_keys($query['select_in_subquery']),
        array_keys($query['select'])
    );

    # Use whatever Pg/PgSQL function we have in store for the subquery
    # (and *only* in the subquery)
    foreach($select_keys as $k) {
        if (isset($query['select_in_subquery'][$k])) {
            $query['select'][$k] = $query['select_in_subquery'][$k];
        }
    }

    $propose = array_unique( array_merge(
            $query['select'],
            $query['select_more'],
            $query['performance']
            ) );

    $add_rtn = array();

    # Strip out duplicates since these should conflict:
    # start_timestamp as start_timestamp
    #    and
    # start_timestamp
    foreach($propose as $p) {
        foreach($accum as $a) {
            if( 0 != strncmp($p, $a, strlen($a)) ) {
                $add_rtn[$a] = $a;
            }
        }
    }

    return array_unique( array_merge(
            $add_rtn,
            $propose
            ) );
}

function compose_sql_select_from($query) {

    $nl = "\n\t";
    $nlt = "\n\t\t";

    $preface_fields = array("trial");

    $phases = $query['phases'];

   # Handle special bitmapped fields
   $bitmapped_fields = setup_bitmapped_fields();
   foreach (array_keys($bitmapped_fields['select']) as $field) {
       if (isset($query['select'][$field]) || 
           isset($query['select_more'][$field]) || 
           isset($query['where'][$field])) {
           $query['select'][$field] = $bitmapped_fields['select'][$field];
       }
   }

   $select_items = compose_sql_select_from_select($query);

   # Array of tables that we need to pull in for the
   # query to work properly
   $needed_tables = array();

   # Determine tables needed for this phase
   foreach (array_keys($select_items) as $column) {
      $tbl = is_needed($column, $needed_tables);
      if( null != $tbl) {
         $needed_tables[] = $tbl;
      }
   }

   # Gather WHERE clause items
   $wheres = array_values2($query['where']);
   $where_not = array_values2($query['where_not']);

   foreach($phases as $phase) {
      $aggregates = $query['cases'][$phase];

      $selects = array_unique(
          array_merge(
              array_values($select_items),
              $query['select_bm'],
              $aggregates
          )
      );

      foreach ($preface_fields as $preface ) {
        $found = false;
        foreach($selects as $field) {
          if( 0 == strncmp($field, $preface, strlen($preface) ) ) {
            $found = true;
            break;
          }
        }
        if(!$found) {
          $selects[] = $preface;
        }
      }

      $p_from[$phase] = " (\n";

      $p_from[$phase] .= "$nl SELECT $nlt" . join(",$nlt", $selects);

      $p_from[$phase] .= "$nl FROM $nlt " . $phase . "$nlt ";

      # Special Case for test_run.performance join
      if(0 == strncmp($phase, "test_run", strlen("test_run")) ) {
        ;#$p_from[$phase] .= get_join_arg($phase, "performance");
      }

      foreach($needed_tables as $tbl) {
        $p_from[$phase] .= get_join_arg($phase, $tbl);
      }

      if ($wheres) {
          $p_from[$phase] .= "$nl WHERE $nlt" .
                      $nl . join(" AND $nlt", $wheres);
      }

      if ($where_not) {
          $p_from[$phase] .= "$nl AND NOT $nlt" .
                      $nl . join(" AND NOT $nlt", $where_not);
      }

      $p_from[$phase] .= "$nl";
      $p_from[$phase] .= " )\n";
   }

   $from_clause = join(" UNION ALL $nl", $p_from);

   return $from_clause;
}

function get_join_arg($phase, $tbl) {
   $nl = "\n\t";
   $nlt = "\n\t\t";

   $rtn = "$nlt NATURAL JOIN $tbl";

   #
   # Special Cases for Test Run
   #
   if( 0 == strncmp($phase, "test_run", strlen("test_run")) ) {
     #####
     # Test Suites
     if( 0 == strncmp($tbl, "test_suites", strlen("test_suites") ) ) {
       $rtn = "$nlt JOIN $tbl on test_suites.test_suite_id = ".$phase.".test_suite_id ";
     }
     #####
     # Test Names
     else if( 0 == strncmp($tbl, "test_names", strlen("test_names") ) ) {
       $rtn = "$nlt JOIN $tbl on test_names.test_name_id = ".$phase.".test_name_id ";
     }
     #####
     # Compiler
     else if( 0 == strncmp($tbl, "compiler", strlen("compiler") ) ) {
       $rtn = "$nlt JOIN $tbl on compiler.compiler_id = ".$phase.".test_build_compiler_id ";
     }
     #####
     # Test Run Command (need to join with network/interconnect tables)
     #
     # JJH Be careful here:
     # If we NATURAL JOIN against the test_run_networks table then a single tuple
     # will be duplicated N times where N is the number of interconnects used
     # for that run. This will distort the test_run numbers [multiplying them
     # each by N] :(
     # The test_run_networks association table should only be used for coverage
     # stats and controlled queries.
     else if( 0 == strncmp($tbl, "test_run_command", strlen("test_run_command") ) ) {
       $rtn = ("$nlt NATURAL JOIN test_run_command ");
       #$rtn = ("$nlt NATURAL JOIN test_run_command ".
       #        "$nlt NATURAL JOIN test_run_networks ".
       #        "$nlt NATURAL JOIN interconnects");
     }
   }
   #
   # Special Cases for Test Build
   #
   else if( 0 == strncmp($phase, "test_build", strlen("test_build")) ) {
     #####
     # Test Suites
     if( 0 == strncmp($tbl, "test_suites", strlen("test_suites") ) ) {
       $rtn = "$nlt JOIN $tbl on test_suites.test_suite_id = ".$phase.".test_suite_id ";
     }
     #####
     # Test Names
     else if( 0 == strncmp($tbl, "test_names", strlen("test_names") ) ) {
       $rtn = "$nlt JOIN $tbl on test_names.test_name_id = ".$phase.".test_name_id ";
     }
     #####
     # Compiler
     else if( 0 == strncmp($tbl, "compiler", strlen("compiler") ) ) {
       $rtn = "$nlt JOIN $tbl on compiler.compiler_id = ".$phase.".test_build_compiler_id ";
     }
   }
   #
   # Special Cases for MPI Install
   #
   else if( 0 == strncmp($phase, "mpi_install", strlen("mpi_install")) ) {
     #####
     # Compiler
     if( 0 == strncmp($tbl, "compiler", strlen("compiler") ) ) {
       $rtn = "$nlt JOIN $tbl on compiler.compiler_id = ".$phase.".mpi_install_compiler_id ";
     }
   }

   return $rtn;
}

function is_needed($column, $cur_needed) {
    $tmp = is_needed_w_index($column, $cur_needed);
    if( null != $tmp ) {
       return $tmp[0];
    } else {
       return null;
    }
}

function is_needed_w_index($column, $cur_needed) {
    $chk_table = null;

    $list_all_tables = array('compute_cluster',
                             'submit',
                             'compiler',
                             'mpi_get',
                             'description',
                             'result_message',
                             'environment',
                             'mpi_install_configure_args',
                             'test_suites',
                             'test_names',
                             'latency_bandwidth',
                             'performance',
                             'test_run_command'
                            );
    $needed = false;

    #
    # First see if it is a unique item
    #
    if(null == ($chk_table = column_exists_which_table($column, $list_all_tables)) ) {
        return null;
    }

    $needed = true;
    foreach($cur_needed as $nt) {
      if(0 == strncmp($nt, $chk_table, strlen($chk_table))) {
        $needed = false;
      }
    }

    if( $needed ) {
      $rtn[0] = $chk_table;
      $rtn[1] = get_table_index($chk_table);
      return $rtn;
    }
    else {
      return null;
    }
}

function get_table_index($table) {
    if( $table == 'mpi_install_configure_args' ) {
        return "mpi_install_configure_id";
    }
    elseif( $table == 'test_suites' ) {
        return "test_suite_id";
    }
    else {
        return $table."_id";
    }
}
# Return true if the column is a result
function is_result_column($str) {
    static $columns;
    if (! $columns)
        $columns = array('_mpi_p'   => 1,
                         '_mpi_f'   => 1,
                         '_build_p' => 1,
                         '_build_f' => 1,
                         '_run_p'   => 1,
                         '_run_f'   => 1,
                         '_run_s'   => 1,
                         '_run_t'   => 1,
                         '_run_l'   => 1);

    if ($columns[$str])
        return true;
    else
        return false;
}

# Return the array values that are a depth of 
# 2 away from the argument passed
function array_values2($arr) {
    foreach (array_keys($arr) as $k)
        $ret[] = $arr[$k];

    return $ret;
}

# Return true if $column exists in any table
# $column is a CSV of one or more column_name's
function column_exists_any($column) {
    $columns = split(',', $column);

    foreach ($columns as $c) {
        $one = select_scalar("SELECT 1 FROM information_schema.columns " .
                             " WHERE column_name = '$c' " .
                             " AND table_name !~* 'view'");
        if (! $one)
            return false;
    }

    return true;
}

# Return true if $column exists in $table.
# $column is a CSV of one or more column_name's
function column_exists($column, $table) {
    $columns = split(',', $column);

    foreach ($columns as $c) {
        $one = select_scalar("SELECT 1 FROM information_schema.columns " .
                             " WHERE column_name = '$c' " .
                             " AND table_name = '$table'");
        if (! $one)
            return false;
    }

    return true;
}

# Return NULL if more than one table.
# Return a single tablename
function column_exists_which_table($column, $tbls) {
    $select_list = null;
    foreach($tbls as $t) {
        if( $select_list != null ) {
          $select_list .= " OR ";
        }
        else {
          $select_list = " AND ( ";
        }

        $select_list .= " table_name = '$t' ";
    }
    $select_list .= ")";

    $one = select_scalar("SELECT table_name FROM information_schema.columns " .
                         " WHERE column_name = '$column' " .
                         $select_list);

    return $one;
}

# Return 1 if $column exists in $dbname
function column_exists2($column) {

    static $columns;
    if (! $columns) {

        $mtt_tables = setup_mtt_db_tables();

        foreach ($mtt_tables as $table) {
            $wheres[] = "table_name = '$table'";
        }

        $cmd = "\n   SELECT column_name " .
               "\n\t FROM information_schema.columns WHERE \n\t" .
                join(" OR \n\t", $wheres) . ";";

        $columns = simple_select($cmd);
    }

    return (array_search($column, $columns) !== false);
}

# Return a list of tables (in $dbname) that need to be
# accessed to SELECT on $selects
function which_tables($selects) {

    static $tables;
    if (! $tables) {

        $mtt_tables = setup_mtt_db_tables();

        foreach ($mtt_tables as $table) {
            $wheres1[] = "table_name = '$table'";
        }

        foreach ($selects as $select) {
            $wheres2[] = "column_name = '$select'";
        }

        $cmd = "\n   SELECT table_name " .
               "\n\t FROM information_schema.columns WHERE \n\t" .
               "\n\t ( " . join(" OR \n\t", $wheres1) . ")" .
               "\n\t AND \n\t" .
               "\n\t ( " . join(" OR \n\t", $wheres2) . ")" .
               "\n\t GROUP BY table_name " .
               ";";

        $tables = simple_select($cmd);

        return $tables;
    }
}

# Return 1 if the $table exists in the database
function table_exists($table) {
    return select_scalar("SELECT 1 FROM information_schema.tables " .
                            "WHERE table_name = '$table'");
}

?>
