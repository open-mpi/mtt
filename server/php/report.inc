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

#
#
# Print a report
#
#

$topdir = ".";
include_once("$topdir/reporter.inc");
include_once("$topdir/database.inc");
include_once("$topdir/html.inc");

# Print report
function dump_report() {

    global $thcolor, $gray, $dgray, $lgray, $llgray, $lllgray, $white;

    # Process buttons 
    # (needs to come first, because _GET could be mutated here)
    $button_press = process_buttons($_GET);

    debug_cgi($_GET, "GET");

    # Process input params
    $phases        = process_phase_field($_GET);
    $date_fields   = process_date_field($_GET);
    $input_fields  = process_input_fields($_GET);
    $offset_field  = process_offset_field($_GET);
    $result_fields = process_result_fields($phases, $_GET);

    # Print either a summary or detail report,
    # depending on whether a 'select_more' parameter is set
    if ($button_press == 'detail') {
        $do_detailed = true;
        $detail_fields = detail_fields(get_scalar($phases));
    } elseif ($button_press == 'performance') {
        $do_performance = true;
        $detail_fields = detail_fields(get_scalar($phases));
        $performance_fields = performance_fields();
    } else
        $do_summary = true;

    # Prepare query components
    $query = array_merge_recursive(
        $date_fields,
        $input_fields,
        $result_fields,
        $detail_fields,
        $performance_fields,
        $offset_field
    );
    $query['phases'] = $phases;

    # Order columns left-to-right
    $query['select'] = order_columns($query['select']);

    # Compose query
    $cmd = compose_sql($query);

    # Execute query
    $resource = do_pg_query($cmd);

    # Generate headers
    foreach ($phases as $phase)
        $keys = array_keys($result_fields['codes'][$phase]);
        foreach ($keys as $result)
            $results[] = $result;

    # Number of rows in this report
    $rowcount = pg_num_rows($resource);
    $n = rowcount($rowcount, $_GET);
    $o = offset($_GET);

    # Prepare headers array for *_table functions
    $headers['params']      = array_keys($query['select']);
    $headers['details']     = array_keys($query['select_more']);
    $headers['performance'] = array_keys($query['performance']);
    $headers['results']     = $results;
    $headers['phases']      = $phases;
    $headers['offset']      = $o;

    # Print some basic, useful info atop each report table
    report_header($date_fields, $phases, $n);
    
    # Do not print an empty table
    if (pg_num_rows($resource) < 1) {
        print "<b><i>No data available for the specified query.</i></b>";
        return;
    }

    # Display report in chunks of 100 rows
    $next_n_rows = next_n_rows($n, 100, $date_fields, $_GET);

    print "$next_n_rows<br><br>";

    if ($do_detailed)
        detail_table($headers, $resource);
    elseif ($do_summary)
        summary_table($headers, $resource);
    elseif ($do_performance) {
        #performance_table($headers, $resource);
        performance_graph($headers, $resource);
    }

    # Provide links to slices of the report ('x' rows at a time)
    print "<br>$next_n_rows";

    print "\n<br><hr><br></body></html>";

    pg_close();
}

# PHP5 has this function built-in
function array_combine($keys, $values) {
    $arr = array();
    for ($i = 0; $i < sizeof($keys); $i++)
        $arr[$keys[$i]] = $values[$i];

    return $arr;
}

# Convert an SQL array (bracketed CSV) to a PHP array
function csv2arr($str) {
    if (preg_match("/{([^}]+)}/i", $str, $m)) {
        $csv = $m[1];
        $arr = explode(',', $csv);
    }
    else 
        $arr = false;

    return $arr;
}

#########################################
#                                       
#  Report Table Generating Functions (2)
#                                     
#########################################

# Void function to print out a summary style HTML data table
function summary_table($headers, $resource) {

    global $thcolor, $gray, $dgray, $lgray, $llgray,
           $lllgray, $white;

    # Insert useful information on the left-hand side?
    print "\n<div align=center>" .

          "\n\n<!-- report_start -->\n\n" .

          "\n<table width='100%' cellpadding=5>" .
          "\n<tr>" .
          "\n<td bgcolor='$lgray'>" .
          "\n<div align=center>" .
          "\n<table border=1 width='100%'>";

    # Display headers
    $format = "\n<th bgcolor='$thcolor' rowspan=2>%s";

    print "<tr>" . sprintf($format, '#');
    foreach ($headers['params'] as $header)
        printf($format, label($header));

    # Setup sequence of result colors
    $phases = $headers['phases'];
    $result_colors = result_colors($phases);

    # Create links for drilled-down queries
    $links = drilldown_links($headers['phases']);

    # Print result headers
    $total_results_cols = 0;
    foreach (array_keys($links) as $phase) {
        $link = array_shift($links[$phase]);
        $colspan = sizeof($links[$phase]);
        $num_result_types[$phase] = $colspan;

        printf("\n<th bgcolor='$thcolor' " .
                     "colspan='$colspan'>%s",
                     $link);
        $total_results_cols += $colspan;
    }

    print "\n<tr>";

    foreach (array_keys($links) as $phase)
        foreach ($links[$phase] as $result)
            printf("\n<th bgcolor='$thcolor'>%s", $result);

    # Row numbering starts at the OFFEST arg to LIMIT
    $offset = $headers['offset'];
    $row_n = $offset;
    $lastrow = $offset + 100;

    # Print data rows
    while ($row = pg_fetch_row($resource)) {

        # Results are always in the far right cols
        $results = array_splice($row, sizeof($row) - $total_results_cols);

        # printf formats
        $format  = "\n<td bgcolor='%s' align='right'>%s";
        $formatg = "\n<td bgcolor='$lgray' align='right'>%s";
        $formatw = "\n<td bgcolor='$white'>%s";

        if ($row_n >= $lastrow)
            break;

        print "\n<tr>" . sprintf($formatg, $row_n + 1);
        for ($i = 0; $i < sizeof($row); $i++)
            printf($formatw, drilldown_links($headers['params'][$i], $row[$i]));

        $i = 0;
        $j = 0;

        foreach ($headers['phases'] as $phase) {
            
            # Each phase has differing result types
            $_results =
                array_splice($results, 0, $num_result_types[$phase]);

            # Link result counts to filtered drill-down reports
            $ret = drilldown_links($headers,
                                  $row,
                                  $_results,
                                  $phase);
            list($pass,
                 $fail,
                 $skip,
                 $time,
                 $perf) = $ret['links'];

            list($pass_count,
                 $fail_count,
                 $skip_count,
                 $time_count,
                 $perf_count) = $ret['counts'];

            printf($format,
                    (($pass_count > 0) ? $result_colors[$j] : $lgray), $pass);
            $j++;
            printf($format,
                    (($fail_count > 0) ? $result_colors[$j] : $lgray), $fail);
            $j++;
            if (! is_null($skip)) {
                printf($format,
                        (($skip_count > 0) ? $result_colors[$j] : $lgray), $skip);
                $j++;
            }
            if (! is_null($time)) {
                printf($format,
                        (($time_count > 0) ? $result_colors[$j] : $lgray), $time);
                $j++;
            }
            if (! is_null($perf)) {
                printf($format,
                        (($perf_count > 0) ? $result_colors[$j] : $lgray), $perf);
                $j++;
            }

            # Tally totals for all result counts
            foreach ($ret['counts'] as $count) {
                $totals[$i++] += $count;
            }
        }
        $row_n++;
    }

    $i = 0;

    # Print results totals in last row
    print "\n<tfoot><tr>" .
          "\n<td align='left' " .
                "bgcolor='$lgray' " .
                "colspan='" . (sizeof($headers['params']) + 1) . "'>" .
          "\n<b>Totals</b>";

    foreach ($totals as $total) {
        print "\n<td align='right' " .
                     "bgcolor='" . (($total > 0) ? $result_colors[$i] : $lgray) . "'" .
                 "><b>$total</b>";
        $i++;
    }
    print "\n</tfoot>" .
          "\n</table>" .
          "\n</table>" .
          "\n\n<!-- report_end -->\n\n";
}

# Void function to print out a detail style HTML data table
function detail_table($headers, $resource) {

    global $thcolor, $gray, $dgray, $lgray, $llgray,
           $lllgray, $lred, $lgreen, $lyellow, $white;

    # Print result headers
    $phase_results_table = phase_results_table();
    $num_cols['results'] = 0;
    foreach ($headers['phases'] as $phase) {
        $num_cols['results'] += sizeof($phase_results_table[$phase]);
    }
    $num_cols['details'] = sizeof($headers['details']);
    $num_cols['params'] = sizeof($headers['params']);

    print "\n<tr>";

    foreach ($headers['results'] as $result) {
        printf("\n<th bgcolor='$thcolor'>%s", $labels[$result]);
    }

    # Row numbering starts at the OFFEST arg to LIMIT
    $offset = $headers['offset'];
    $row_n = $offset;
    $lastrow = $offset + 100;

    # Remove duplicated headers
    $headers = array_unique(
        array_merge(
            $headers['params'],
            $headers['details']
        )
    );

    # Print data rows
    while ($row = pg_fetch_row($resource)) {

        if ($row_n >= $lastrow)
            break;

        # Results are always in the far right cols
        $results = array_splice($row, $num_cols['params']);

        # Details are always in the far far right cols
        $details = array_splice($results, $num_cols['results']);

        list($pass,
             $fail,
             $skip,
             $time,
             $perf) = $results;

        if ($pass)
            $bgcolor = (($pass > 0) ? $lgreen  : "");
        elseif ($fail)
            $bgcolor = (($fail > 0) ? $lred    : "");
        elseif ($skip)
            $bgcolor = (($skip > 0) ? $lyellow : "");
        elseif ($time)
            $bgcolor = (($time > 0) ? $lyellow : "");
        elseif ($perf)
            $bgcolor = (($time > 0) ? $lblue   : "");

        print "<table border='1' width='100%'>" .
              "<tr><td bgcolor='$bgcolor'>";

        $td = "<td bgcolor='$lgray' width='10%' valign='top'>";
        $tdl = "<td bgcolor='$white'>";

        $values =
            array_merge(
                $row,
                $details
            );

        $i = 0;
        print "<table border='1' width='100%'>";
        foreach ($headers as $header) {
            print (($i % 1 == 0) ? "\n<tr>" : "") .
                  "\n$td <b>" . label($header) . "</b> $tdl " .
                  "\n<pre>" . wordwrap($values[$i], 100) . "</pre>";
            $i++;
        }
        print "</table>";
        print "</table>";
    }

    print "\n</table>" .
          "\n</table>" .
          "\n\n<!-- report_end -->\n\n";
}

# Void function to print out a table of performance data
function performance_table($headers, $resource) {

    global $thcolor, $gray, $dgray, $lgray, $llgray,
           $lllgray, $lred, $lgreen, $lyellow, $white;

    # Print result headers
    $phase_results_table = phase_results_table();
    $num_cols['results'] = 0;
    foreach ($headers['phases'] as $phase) {
        $num_cols['results'] += sizeof($phase_results_table[$phase]);
    }
    $num_cols['details'] = sizeof($headers['details']);
    $num_cols['params'] = sizeof($headers['params']);
    $num_cols['performance'] = sizeof($headers['performance']);

    foreach ($headers['results'] as $result) {
        printf("\n<th bgcolor='$thcolor'>%s", $labels[$result]);
    }

    # Row numbering starts at the OFFEST arg to LIMIT
    $offset = $headers['offset'];
    $row_n = $offset;
    $lastrow = $offset + 100;

    # Remove duplicated headers
    $headers = array_unique(
        array_merge(
            $headers['params'],
            $headers['details'],
            $headers['performance']
        )
    );

    # Print data rows
    while ($row = pg_fetch_row($resource)) {

        if ($row_n >= $lastrow)
            break;

        # Results are always in the far right cols
        $results = array_splice($row, $num_cols['params']);

        # Details are always in the far far right cols
        $details = array_splice($results, $num_cols['results']);

        list($pass,
             $fail,
             $skip,
             $time,
             $perf) = $results;

        if ($pass)
            $bgcolor = (($pass > 0) ? $lgreen  : "");
        elseif ($fail)
            $bgcolor = (($fail > 0) ? $lred    : "");
        elseif ($skip)
            $bgcolor = (($skip > 0) ? $lyellow : "");
        elseif ($time)
            $bgcolor = (($time > 0) ? $lyellow : "");
        elseif ($perf)
            $bgcolor = (($time > 0) ? $lblue   : "");

        print "<table border='1' width='100%'>" .
              "<tr><td bgcolor='$bgcolor'>";

        $td = "<td bgcolor='$lgray' width='10%' valign='top'>";
        $tdl = "<td bgcolor='$white'>";

        $values =
            array_merge(
                $row,
                $details
            );

        $i = 0;
        print "<table border='1' width='100%'>";
        foreach ($headers as $header) {
            print (($i % 1 == 0) ? "\n<tr>" : "") .
                  "\n$td <b>" . label($header) . "</b> $tdl " .
                  "\n<pre>" . wordwrap($values[$i], 100) . "</pre>";
            $i++;
        }
        print "</table>";
        print "</table>";
    }

    print "\n</table>" .
          "\n</table>" .
          "\n\n<!-- report_end -->\n\n";
}

# Void function to print out a summary table,
# with a performance graph. (Legend the 
# graph using the row numbers from the summary table)
function performance_graph($headers, $resource) {

    global $thcolor, $gray, $dgray, $lgray, $llgray,
           $lllgray, $white;

    # Insert useful information on the left-hand side?
    print "\n<div align=center>" .

          "\n\n<!-- report_start -->\n\n" .

          "\n<table width='100%' cellpadding=5>" .
          "\n<tr>" .
          "\n<td bgcolor='$lgray'>" .
          "\n<div align=center>" .
          "\n<table border=1 width='100%'>";

    # Display headers
    $format = "\n<th bgcolor='$thcolor' rowspan=2>%s";

    print "<tr>" . sprintf($format, '#');
    foreach ($headers['params'] as $header)
        printf($format, label($header));

    # Setup sequence of result colors
    $phases = $headers['phases'];
    $result_colors = result_colors($phases);

    # Create links for drilled-down queries
    $links = drilldown_links($headers['phases']);

    # Print result headers
    $total_results_cols = 0;
    foreach (array_keys($links) as $phase) {
        $link = array_shift($links[$phase]);
        $colspan = sizeof($links[$phase]);
        $num_result_types[$phase] = $colspan;

        printf("\n<th bgcolor='$thcolor' " .
                     "colspan='$colspan'>%s",
                     $link);
        $total_results_cols += $colspan;
    }

    print "\n<tr>";

    foreach (array_keys($links) as $phase)
        foreach ($links[$phase] as $result)
            printf("\n<th bgcolor='$thcolor'>%s", $result);

    # Print result headers
    $phase_results_table = phase_results_table();
    $num_cols['results'] = 0;
    foreach ($headers['phases'] as $phase) {
        $num_cols['results'] += sizeof($phase_results_table[$phase]);
    }
    $num_cols['details'] = sizeof($headers['details']);
    $num_cols['params'] = sizeof($headers['params']);
    $num_cols['performance'] = sizeof($headers['performance']);

    # Row numbering starts at the OFFEST arg to LIMIT
    $offset = $headers['offset'];
    $row_n = $offset;
    $lastrow = $offset + 100;

    $format  = "\n<td bgcolor='%s' align='right'>%s";

    $result_colors = result_colors('test_run');

    # Print data rows
    while ($row = pg_fetch_row($resource)) {

        # Results are always in the far right cols
        $results = array_splice($row, $num_cols['params']);

        # Details are always in the far far right cols
        $details = array_splice($results, $num_cols['results']);

        # Performance is always in the far far far right cols
        $performance = array_splice($details, $num_cols['details']);

        # printf formats
        $format  = "\n<td bgcolor='%s' align='right'>%s";
        $formatg = "\n<td bgcolor='$lgray' align='right'>%s";
        $formatw = "\n<td bgcolor='$white'>%s";

        if ($row_n >= $lastrow)
            break;

        print "\n<tr>" . sprintf($formatg, $row_n);
        for ($i = 0; $i < sizeof($row); $i++)
            printf($formatw, drilldown_links($headers['params'][$i], $row[$i]));

        # Link result counts to filtered drill-down reports
        $ret = drilldown_links($headers,
                               $row,
                               $results,
                               'test_run');

        list($pass,
             $fail,
             $skip,
             $time,
             $perf) = $ret['links'];

        list($pass_count,
             $fail_count,
             $skip_count,
             $time_count,
             $perf_count) = $ret['counts'];

        $j = 0;
        printf($format,
                (($pass_count > 0) ? $result_colors[$j] : $lgray), $pass);
        $j++;
        printf($format,
                (($fail_count > 0) ? $result_colors[$j] : $lgray), $fail);
        $j++;
        if (! is_null($skip)) {
            printf($format,
                    (($skip_count > 0) ? $result_colors[$j] : $lgray), $skip);
            $j++;
        }
        if (! is_null($time)) {
            printf($format,
                    (($time_count > 0) ? $result_colors[$j] : $lgray), $time);
            $j++;
        }
        if (! is_null($perf)) {
            printf($format,
                    (($perf_count > 0) ? $result_colors[$j] : $lgray), $perf);
            $j++;
        }

        # Tally totals for all result counts
        foreach ($ret['counts'] as $count) {
            $totals[$i++] += $count;
        }

        # Prepare perf data to be displayed in a graph
        $hash = array_combine(
                    $headers['performance'], 
                    array_map('csv2arr', $performance)
                );
        $graph_data[$row_n] = $hash;

        # Tests may have differing series of message sizes,
        # so find the longest series for the x-axis
        if ($pad < sizeof($hash['message_size'])) {
            $message_sizes = $hash['message_size'];
            $pad = sizeof($message_sizes);
        }
        $row_n++;
    }

    print "\n</table>" .
          "\n</table>" .
          "\n\n<!-- report_end -->\n\n";

    # Do graph(s)
    display_graph($graph_data, 'latency_avg', $message_sizes);
    display_graph($graph_data, 'latency_min', $message_sizes);
    display_graph($graph_data, 'latency_max', $message_sizes);
    display_graph($graph_data, 'bandwidth_avg', $message_sizes);
    display_graph($graph_data, 'bandwidth_min', $message_sizes);
    display_graph($graph_data, 'bandwidth_max', $message_sizes);

    # Clean up old graphs
    housekeeping('./images/tmp');
}

# Clean up old graphs
function housekeeping($dir) {

    $res = opendir($dir);

    $root = dirname($_SERVER["SCRIPT_FILENAME"]);

    $img_types = array("\.gif$",
                       "\.jpg$",
                       "\.png$",
                       "\.jpeg$",
                       "\.pdf$");

    # Threshold to unlink a file
    $hours = 1;

    $now = time();

    # Loop through the files and delete any old ones
    while ($filename = readdir($res)) {

        # unlink needs a full path
        $filename = "$root/$dir/$filename";

        if (preg_match('/'.join('|', $img_types).'/i', $filename)) {
            $age = $now - filemtime($filename);
            if ($age > (60 * 60 * $hours))
                unlink($filename);
        }
    }
    closedir($res);
}

# Print out the actual binary image data
# Uses jpgraph (http://www.aditus.nu/jpgraph)
function display_graph($data, $type, $message_sizes) {

    $jpgraph_dir = './jpgraph';
    include_once("$jpgraph_dir/jpgraph.php");
    include_once("$jpgraph_dir/jpgraph_line.php");

    $pad = sizeof($message_sizes);

    # Set axis label units
    if (preg_match("/latency/i", $type))
        $unit = 'usec';
    elseif (preg_match("/bandwidth/i", $type))
        $unit = 'Mbps';

    $colors = array(
        '#FFA500', # 255,165,0       Orange              	
        '#0000FF', # 0,0,255         Blue	
        '#FF0000', # 255,0,0         Red                 	
        '#008000', # 0,128,0         Green               	
        '#DAA520', # 218,165,32      GoldenRod           	
        '#FF00FF', # 255,0,255       Magenta             	
        '#000000', # 0,0,0           Black
        '#00FFFF', # 0,255,255       Cyan                	
        '#808080', # 128,128,128     Gray                	
        '#DA70D6', # 218,112,214     Orchid              	
        '#F0E68C', # 240,230,140     Khaki               	
        '#DC143C', # 237,164,61      Crimson             	
        '#66CDAA', # 102,205,170     MediumAquaMarine    	
        '#0000CD', # 0,0,205         MediumBlue          	
        '#BA55D3', # 186,85,211      MediumOrchid        	
        '#9370D8', # 147,112,219     MediumPurple        	
        '#3CB371', # 60,179,113      MediumSeaGreen      	
        '#7B68EE', # 123,104,238     MediumSlateBlue     	
        '#00FA9A', # 0,250,154       MediumSpringGreen   	
        '#48D1CC', # 72,209,204      MediumTurquoise     	
        '#C71585', # 199,21,133      MediumVioletRed     	
        '#00008B', # 0,0,139         DarkBlue            	
        '#B8860B', # 184,134,11      DarkGoldenRod       	
        '#006400', # 0,100,0         DarkGreen           	
        '#8B008B', # 139,0,139       DarkMagenta         	
        '#A9A9A9', # 169,169,169     DarkGray            	
        '#FF8C00', # 255,140,0       Darkorange          	
        '#008B8B', # 0,139,139       DarkCyan            	
        '#BDB76B', # 189,183,107     DarkKhaki           	
        '#556B2F', # 85,107,47       DarkOliveGreen      	
        '#9932CC', # 153,50,204      DarkOrchid          	
        '#8B0000', # 139,0,0         DarkRed             	
        '#E9967A', # 233,150,122     DarkSalmon          	
        '#8FBC8F', # 143,188,143     DarkSeaGreen        	
        '#483D8B', # 72,61,139       DarkSlateBlue       	
        '#2F4F4F', # 47,79,79        DarkSlateGray       	
        '#00CED1', # 0,206,209       DarkTurquoise       	
        '#9400D3', # 148,0,211       DarkViolet          	
    );

    # Create the graph. These two calls are always required
    $gJpgBrandTiming = true;
    $graph = new Graph(600, 400, "auto");    
    $graph->SetScale("textlin");

    # Make the margin around the plot a little bit bigger then default
    $graph->img->SetMargin(40,100,40,60);    
    #$graph->xaxis->title->Set("Message size (bytes)");
    $graph->yaxis->title->Set(label($type) . " - $unit");

    $graph->title->Set("MTT Performance Results");
    $graph->title->SetFont(FF_FONT1, FS_BOLD);
    $graph->yaxis->title->SetFont(FF_FONT1, FS_BOLD);
    $graph->xaxis->title->SetFont(FF_FONT1, FS_BOLD);

    # Setup the labels
    $graph->xaxis->SetTickLabels($message_sizes);
    $graph->xaxis->SetLabelAngle(90);

    $j = 0;

    $type = strtolower($type);

    # jpgraph doesn't like empty graphs
    $empty = true;

    # Plot the data
    foreach (array_keys($data) as $i) {
        
        $line = $data[$i][$type];

        # Create the linear plot
        if ($line) {
            $empty = false;

            $ydata = array_pad($line, $pad, null);

            $color = $colors[$j++];

            # Avoid null color error
            if (! $color)
                $color = 'black';

            $lineplots[$i] = new LinePlot($ydata);

            $lineplots[$i]->SetColor($color);
            $lineplots[$i]->SetWeight(2);
            $lineplots[$i]->SetLegend("$i");

            $graph->Add($lineplots[$i]);
        }
    }
    if ($empty)
        return;

    $graph->SetShadow();

    # Write the graph to a file
    $filename = 'images/tmp/' . randstr(10) . '.png';
    $graph->Stroke($filename);

    # Display the graph
    print "<br><div align='center'><img src='$filename'></div>";
}

# Generate a random string
function randstr($length) {

    $pattern = "1234567890abcdefghijklmnopqrstuvwxyz";
    for($i = 0; $i < $length; $i++) {
        if (isset($key))
            $key .= $pattern{rand(0,35)};
        else
            $key = $pattern{rand(0,35)};
    }
    return $key;
}

#########################################

# Return a sequence of result cell bgcolors
function result_colors($phases) {

    global $lred, $lgreen, $lyellow, $lblue;

    # Arrayify the argument
    if (! is_array($phases))
        $phases = array($phases);

    if (array_search('mpi_install', $phases) !== false) {
        $colors[] = $lgreen;
        $colors[] = $lred;
    }
    if (array_search('test_build', $phases) !== false) {
        $colors[] = $lgreen;
        $colors[] = $lred;
    }
    if (array_search('test_run', $phases) !== false) {
        $colors[] = $lgreen;
        $colors[] = $lred;
        $colors[] = $lyellow;
        $colors[] = $lyellow;
        $colors[] = $lblue;
    }
    return $colors;
}

# Return either the first element of the list
# or the scalar argument
function get_scalar($var) {
    if (is_array($var))
        return $var[0];
    else
        return $var;
}

#########################################
#                                       
#  Link Generating Functions
#                                     
#########################################

# Show links to report slices ('x' rows at a time)
function next_n_rows($n, $limit, $date_fields, $params) {

    # Prepare an href element to use for linking to report
    # slices
    $self = 'http://' . $_SERVER['SERVER_NAME'] . $_SERVER['SCRIPT_NAME'];
    $format = "<a href='$self?%s' class='black_ln' target='_self'>%s</a>";

    # Convenience arrow for going through 100s of rows
    $img = "<img src='./images/%s_arrow.gif' border='0'>";

    $qstring_arr = $params;
    $qstring_arr['rows'] = $n;

    $phase = process_phase_field($params['phase']);
    $offset = offset($params);

    $go = strtolower($params['go']);

    # Determine report type
    if (preg_match("/(summary|detail)/i", $go, $m))
        $qstring_arr['go'] = $m[1]."_slice";

    # Report "slices" should use absolute date range
    # because the LIMIT clause may not make sense in
    # the future
    $absolute_date = handle_absolute_date($date_fields);

    $qstring_arr["text_start_timestamp"] = $absolute_date;

    $i = 0;
    while ($i < $n) {
        $qstring_arr['offset'] = $i;
        $label = (($i/$limit) + 1);

        $qstring = arr2qstring($qstring_arr);

        # Numbered links
        if ($i == $offset)
            $links[] = $label;
        else
            $links[] = sprintf($format, $qstring, $label);

        # Arrows
        $prevn = $offset - $limit;
        $nextn = $offset + $limit;
        if ($i == $prevn and ($i != 0))
             $prev = sprintf($format, $qstring, sprintf($img, "left"));
        elseif ($i == $nextn)
             $next = sprintf($format, $qstring, sprintf($img, "right"));

        $i += $limit;
    }

    # Do not print a lone '0'
    if (sizeof($links) > 1) {
        $ret .= "\n<table width='100%'><tr><td align='center'>";

        # Left arrow
        $ret .= "\n$prev";

        foreach ($links as $link)
            $ret .= "\n&nbsp;$link";

        # Right arrow
        $ret .= "\n&nbsp;$next";
    }
    return $ret;
}

# Create links that drill down by phase, result, and a set
# of general params This function takes the following three
# forms:
#
# 1. Entire row or data
#    * Phase, series of param/value pairs, result counts
#    * For "colored" result count table cells
#       
# 2. Just a single param/value pair
#    * For "white" parameter table cells
#    
# 3. List of phases
#    * For phase/result table header cells
#
# Note: this function takes a variable number of arguments
function drilldown_links() {

    # This function has three forms (see above comment)
    $argc = func_num_args();

    $phase_results_table = phase_results_table();

    # Prepare a query string for manipulation
    $qstring_arr = $_GET;

    # Do not bring over LIMIT clause for a drilldown
    unset($qstring_arr['rows']);
    unset($qstring_arr['offset']);

    $self = 'http://' . $_SERVER['SERVER_NAME'] . $_SERVER['SCRIPT_NAME'];
    $format = "<a href='$self?%s' class='black_ln' target='_self'>%s</a>";

    # 1. Entire row or data
    #    * Phase, series of param/value pairs, result counts
    #    * For "colored" result count table cells
    if ($argc == 4) {

        $headers = func_get_arg(0);
        $params  = func_get_arg(1);
        $results = func_get_arg(2);
        $phase   = func_get_arg(3);

        # Bring over phase-independent selections, and
        # combine them with phase-dependent defaults
        $defaults = setup_defaults($phase);
        $qstring_arr = form_carryover($defaults);
        $qstring_arr['phase'] = $phase;

        # Do not bring over LIMIT clause for a drilldown
        unset($qstring_arr['rows']);
        unset($qstring_arr['offset']);

        $j = 0;
        # Loop over result count values
        foreach ($results as $count) {

            $i = 0;
            # Loop over header names
            foreach ($headers['params'] as $param) {
                $qstring_arr["text_$param"] = exact($params[$i++]);
            }
            $qstring_arr['test_result'] = $phase_results_table[$phase][$j++];

            $ret['links'][] = sprintf($format, arr2qstring($qstring_arr), $count);
            $ret['counts'][] = $count;
        }
    }

    # 2. Just a single param/value pair
    #    * For "white" parameter table cells
    #    
    elseif ($argc == 2) {

        $header = func_get_arg(0);
        $param  = func_get_arg(1);

        $qstring_arr["text_$header"] = exact($param);

        # Do not bring over LIMIT clause for a drilldown
        unset($qstring_arr['rows']);
        unset($qstring_arr['offset']);

        $ret = sprintf($format, arr2qstring($qstring_arr), $param);
    }

    # 3. List of phases
    #    * For phase/result table header cells
    #
    # Return a series of links, containing one or three of
    # the following:
    #
    # * MPI Install
    #   Pass, Fail
    # * Test Build
    #   Pass, Fail
    # * Test Run
    #   Pass, Fail, Skipped, Timed out
    #
    elseif ($argc == 1) {

        $phases = func_get_arg(0);

        foreach ($phases as $phase) {

            # Bring over phase-independent selections, and
            # combine them with phase-dependent defaults
            $defaults = setup_defaults($phase);
            $qstring_arr = form_carryover($defaults);
            $qstring_arr['phase'] = $phase;

            # Do not bring over LIMIT clause for a drilldown
            unset($qstring_arr['rows']);
            unset($qstring_arr['offset']);

            unset($qstring_arr['test_result']);
            $ret[$phase][] = sprintf($format, arr2qstring($qstring_arr), label($phase));

            foreach ($phase_results_table[$phase] as $result) {
                $qstring_arr['test_result'] = $result;
                $ret[$phase][] =
                    sprintf($format, arr2qstring($qstring_arr), label($result));
            }
        }
    }
    return $ret;
}

# Return the string with beginning/ending regexp match boundaries
# (param/value drilldown links on table cells should use this)
function exact($str) {
    return '^' . $str . '$';
}

# Return number of rows in report
function rowcount($n, $params) {
    # LIMIT has not been used
    if (! isset($params['rows']))
        return $n;
    else
         return $params['rows'];
}

# Return offset integer from where this report is displaying
function offset($params) {
    if (isset($params['offset']))
        return $params['offset'];
    else
        return 0;
}

# Print some basic, useful info atop each report table
function report_header($date_fields, $phases, $n) {

    $basic_info = basic_info($date_fields, $phases, $n);
    $permalinks = permalinks($date_fields);

    # Print general info/links up top
    print "<table width='100%'><tr>" .
          "<td>$basic_info" .
          "<td align='right'>$permalinks" .
          "</table>";
}

# Show links to point user to more info ...
function permalinks($date_fields) {

    $params = $_GET;

    $domain        = $_SERVER['SERVER_NAME'];
    $uri           = $_SERVER['REQUEST_URI'];
    $script        = $_SERVER['SCRIPT_NAME'];
    $absolute_date = handle_absolute_date($date_fields);

    $start_timestamp = $params["text_start_timestamp"];

    # Tell reporter to create a permalink
    $params["make_redir"] = 1;

    # Do relative link
    $qstring1 = arr2qstring($params);

    # Do absolute link
    $params["text_start_timestamp"] = $absolute_date;
    $qstring2 = arr2qstring($params);

    # Create links to report using relative and absolute date ranges
    $links["Absolute date range"] = "http://$domain$script?$qstring2";

    # Do not display two permalinks with identical URLs
    if ($absolute_date != $start_timestamp)
        $links["Relative date range"] = 
            "http://$domain$script?$qstring1";

    # Formatting for Javascript to open a small window
    $anchor = "<a href='javascript:littleWindow(\"%s\");' " .
                 "class='black_ln'>Create permalink</a>";

    # Formatting for a link which generates a permalink when clicked
    $href = "\n<tr><td><b>%s</b>:<td>$anchor";

    $ret = "\n<table>";

    foreach (array_keys($links) as $k)
        $ret .= sprintf($href, $k, $links[$k]);

    $ret .= "\n</table>";

    return $ret;
}

function handle_absolute_date($date_fields) {
    $absolute_date   = $date_fields["absolute"];
    $rollup          = $date_fields["rollup"];
    $date_field      = $absolute_date;

    if (! is_null($rollup))
        $date_field .= "; $rollup";

    return $date_field;
}

# Print current time, date range, phases, and
# result filter for the report
function basic_info($date_fields, $phases, $num_rows) {

    $ret = "<table>" .
          "<tr><td><b>Current time (GMT)</b>:<td>" . $date_fields["current"] . 
          "<tr><td><b>Date range (GMT)</b>: <td>" . $date_fields["absolute"] .
          "<tr><td><b>Phase(s)</b>:<td>" . en_join(array_map('label', $phases));

    if ($_GET["test_result"])
        $ret .= "<tr><td><b>Result</b>:<td>" . label($_GET["test_result"]) . " only";

    $ret .= "<tr><td><b>Number of rows</b>:<td>" . $num_rows .
            "</table>";

    return $ret;
}

#########################################

# Compose an SQL SELECT statement
function compose_sql($query) {

    $selects = array();
    $nl = "\n\t";

    # Determine table (or views) to SELECT from
    if (sizeof($query['phases']) > 1)
        $tables = array('all_view');
    else
        $tables = suffix_list($query['phases'], '_view');

    foreach (array_keys($query['aggregates']) as $aggregate) {
        $aggregates[] = $query['aggregates'][$aggregate];
    }

    # Compile values for SELECT, GROUP BY,
    # and ORDER BY, and LIMIT clauses
    $selects = array_unique(
        array_merge(
            $query['select'],
            $aggregates,
            $query['select_more'],
            $query['performance']
        )
    );

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

    $offset = offset($query);

    # Piece together all the clauses
    $cmd  = "\n SELECT " .
                "$nl" . join(",$nl", $selects);

    $cmd .= "\n FROM " .
                "$nl" . join(",$nl", $tables);

    if ($query['where']) {
        $cmd .= "\n WHERE " .
                    "$nl" . join("$nl AND $nl", $query['where']);
    }

    if (array_keys($query['select'])) {
        $cmd .= "\n GROUP BY " .
                    "$nl" . join(",$nl ", $groupbys);

        $cmd .= "\n ORDER BY " .
                    "$nl" . join(",$nl ", $orderbys);
    }
    if ($offset)
        $cmd .= "\n LIMIT 100 OFFSET $offset;";

    debug_sql($cmd);

    return $cmd;
}

#########################################
#                                       
#  Input Processing Functions          
#                                     
# The following process_*_field(s) functions return arrays
# ready to be fed to compose_sql. The query array is
# structured more or less like an SQL SELECT statement:
#
# (type)  
# (all)    $query['select'][column alias]      => list of SELECT {string functions | column aliases}
# (all)    $query['aggregates']                => list of COUNT clauses for result counts
# (detail) $query['select_more'][column alias] => list of detail SELECT columns
# (all)    $query['where']                     => list of WHERE clauses
# (all)    $query['limit']                     => LIMIT value
# (all)    $query['offset']                    => OFFSET value
#
#########################################

# Determine report type, Summary or Detail
#
# THIS FUNCTION CHANGES _GET BASED ON WHETHER A "SLICE"
# REPORT IS BEING USED. REASON: THERE IS NO WAY TO CHANGE
# TWO PARAMS IN A SINGLE BUTTON CLICK
function process_buttons($params) {
    $go = strtolower($_GET['go']);

    # Determine report type, and
    # whether this is a "slice" report
    if (preg_match("/(summary|detail|performance|latency\w+)/i", $go, $m)) {
        $type = $m[1];
        if (! preg_match("/slice/i", $go)) {
            unset($_GET['rows']);
            unset($_GET['offset']);
        }
    }

    # Press 'Summary' for them if they traverse from a
    # detailed report into multi-phase mode
    $phases = process_phase_field($_GET);
    if ((sizeof($phases) > 1) and (! preg_match("/summary/i", $type))) {
        $type = 'summary';
        $_GET['go'] = $type;
    }

    return $type;
}

# 1. Generate WHERE clause pieces from user-entered textfields
# 2. Generate SELECT items from user-entered show/hide menus
function process_input_fields($params) {

    $query['where'] = array();
    $query['select'] = array();

    # These fields will not be string searchable
    $special_fields = array(
        "timestamp",
        "duration",
        "phase",
    );

    $enums = enums_table();

    foreach (array_keys($params) as $k) {

        if (preg_match("/" . join("|", $special_fields) . "/i", $k))
            continue;

        # If it's a textfield, tokenize it and add each
        # item to WHERE clause
        elseif (preg_match("/^text_/i", $k)) {
            $column = strip_prefix($k);

            $clauses = array();

            # Compose WHERE clause(s) on special enumerated types
            if (preg_match("/" . join('|', array_keys($enums)) . "/i", $column)) {
                $filters = array_flip($enums[$column]);
                foreach (tokenize($params[$k]) as $t) {
                    if (preg_match("/unknown/i", $t))
                        continue;
                    $clauses[] = "$column = $filters[$t]";
                }
                continue;
            }

            # No WHERE clause, if field is blank or "all"
            if (preg_match("/^\s*all\s*$|^\s*$/i", $params[$k]))
                continue;

            foreach (tokenize($params[$k]) as $t) {
                $clauses[] = "$column ~* '$t'";
            }
            $query['where'][] = "(" . join(" OR ", $clauses) . ")";
        }
        # If "show" is selected, add it to SELECT clause
        elseif (preg_match("/^show_/i", $k)) {
            $column = strip_prefix($k);

            if ($params[$k] == 'show')
                $query['select'][$column] = $column;
        }
        # If it's a "more" param, add it to the ''end'' of the SELECT clause
        elseif (preg_match("/^more_/i", $k)) {
            $column = strip_prefix($k);

            if (isset($params[$k]))
                $query['select_more'][$column] = $column;
        }
    }

    # Compose SELECT clause(s) on special enumerated types
    foreach (array_keys($enums) as $enum) {
        if (isset($query['select'][$enum])) {
            $query['select'][$enum] =
                "(CASE ";
            foreach (array_keys($enums[$enum]) as $k)
                $query['select'][$enum] .=
                    "WHEN $enum = $k THEN '" . $enums[$enum][$k] . "' ";
            $query['select'][$enum] .=
                "ELSE 'unknown' END) as $enum";
        }
    }

    return $query;
}

# Arguments:
# 1. English filter (e.g., 'yesterday' or
#    'past x days')
# 2. Optional timestamp string description (e.g.,
#    "by second", "by hour", ...)
#
# Return the SQL date filter (and string function)
function process_date_field($params) {

    $date = array();
    $tokens = array();

    $sep = '[\s\+]';
    $c = '/\s*;\s*/';

    # Remove the GMT offset from fetched string
    $format = "replace(date_trunc('second', %s), '+00', '')";

    $now = select_scalar("SELECT " . sprintf($format, "now()"));
    $date['current'] = $now;

    $timestamp_name = "start_timestamp";
    $timestamp_param = $params["text_$timestamp_name"];

    if (preg_match($c, $timestamp_param, $m))
        $tokens = tokenize($timestamp_param);
    else
        $tokens[] = $timestamp_param;

    foreach ($tokens as $token) {

        # Do date filtering
        if (! preg_match("/by /i", $token)) {

            # Yesterday
            if (preg_match("/yesterday/i", $token, $m)) {
                $operand = "timestamp without time zone 'yesterday'";
                $where = "$timestamp_name > $operand";
                $absolute =
                    select_scalar("SELECT " . sprintf($format, $operand)) . " - $now";
            }
            # Today
            elseif (preg_match("/today/i", $token, $m)) {
                $operand = "timestamp without time zone 'today'";
                $where = "$timestamp_name > $operand";
                $absolute =
                    select_scalar("SELECT " . sprintf($format, $operand)) . " - $now";
            }
            # Past x increments
            elseif (preg_match(
                        "/past$sep*" .
                        "(\w+)$sep*" .
                        "(\w+)/i", $token, $m)) {

                $operand = "now() - interval '" . strtonumeral($m[1]) . " $m[2]'";
                $where = "$timestamp_name > $operand";
                $absolute =
                    select_scalar("SELECT " . sprintf($format, $operand)) . " - $now";
            }
            # Range (e.g., date1 - date2)
            elseif (preg_match("/(?:between)?" .
                                "(.*)" .
                                "(?:through|thru|and| - )" .
                                "(.*)/i", $token, $m)) {
                $where =
                    "$timestamp_name > '$m[1]'" . " AND " .
                    "$timestamp_name < '$m[2]'";
                $absolute = "$m[1] - $m[2]";
            }
        }
        # Do date aggregation
        else {

            $format2 = "\n substring($timestamp_name from 0 for %d) || ':00 - ' || " .
                       "\n substring($timestamp_name + interval '1 %s' from 0 for %d)  || ':00' " .
                       "\n   as $timestamp_name";
            $format3 = "\n substring($timestamp_name from 0 for %d) || ' - ' || " .
                       "\n substring($timestamp_name + interval '1 %s' from 0 for %d) " .
                       "\n   as $timestamp_name";

            if (preg_match("/by(?:-| *)sec(?:onds?)?/i", $token)) {
                $clause = sprintf($format3, 20, "second", 20);

            } elseif (preg_match("/by(?:-| *)min(?:utes?)?/i", $token)) {
                $clause = sprintf($format3, 17, "minute", 17);

            } elseif (preg_match("/by(?:-| *)hours?/i", $token)) {
                $clause = sprintf($format2, 14, "hour", 14);

            } elseif (preg_match("/by(?:-| *)days?/i", $token)) {
                $clause = sprintf($format3, 11, "day", 11);

            } elseif (preg_match("/by(?:-| *)mon(?:ths?)?/i", $token)) {
                $clause = sprintf($format3, 8, "month", 8);

            } elseif (preg_match("/by(?:-| *)years?/i", $token)) {
                $clause = sprintf($format3, 5, "year", 5);
            }
            $date["rollup"] = $token;
        }
    }

    # PROTECT AGAINST AN EMPTY DATE RANGE.
    # OUGHT TO PRINT A JAVASCRIPT ALERT AS WELL
    if (! $where) {
        $operand = "now() - interval '24 hours'";
        $where = "$timestamp_name > $operand";
        $absolute =
            select_scalar("SELECT " . sprintf($format, $operand)) . " - $now";
        $date['select'][$timestamp_name] = $timestamp_name;
    }

    $date['select'][$timestamp_name] = $clause;
    $date['where'] = $where;
    $date['absolute'] = $absolute;

    return $date;
}

# Return 
# 1. An array of SQL COUNT(CASE ...) clauses
#    which will be used to tally the result numbers
# 2. A result filter (optional)
# (Reference: postgresql.org/docs/7.3/static/functions-conditional.html)
function process_result_fields($phases, $params) {

    $test_result = $params['test_result'];

    $table = phase_results_table();

    # THESE FILTER STRINGS MUST MATCH THE IDENTIFIERS USED
    # IN [source:/trunk/server/sql/views.sql]
    if (preg_match('/pass|true|1/i', $test_result))
        $filter = 'pass';
    elseif (preg_match('/fail|false|0/i', $test_result))
        $filter = 'fail';
    elseif (preg_match('/skip|2/i', $test_result))
        $filter = 'skipped';
    elseif (preg_match('/time|3/i', $test_result))
        $filter = 'timed_out';
    elseif (preg_match('/lat|band|perf/i', $test_result))
        $filter = 'latency_bandwidth';

    $format = "COUNT(CASE WHEN %s THEN '%s' END) as %s";

    foreach (array_keys($table) as $phase) {
        foreach ($table[$phase] as $result) {
            if (array_search($phase, $phases) !== false) {
                $str = result_str($phase, $result);
                $results['codes'][$phase][$result] = $str;
                $when[$result] = "$result = '$str'";
                $results['aggregates'][$str] =
                    sprintf($format, $when[$result], $str, $str);
            }
        }
    }

    $results['where'] = $when[$filter];

    return $results;
}

# Process OFFSET value for LIMIT clause
function process_offset_field($params) {
    $offset = $_GET['offset'];
    return array('offset' => $offset);
}

#########################################

# Loop through column aliases, and return
# a left-to-right ordering of SELECT clauses
function order_columns($columns) {

    $layout = array(

        # results
        'start_timestamp'   => 1,

        # submit
        'http_username'     => 1,
        'local_username'    => 1,
        'hostname'          => 1,

        # mpi_install
        'platform_hardware' => 1,
        'os_name'           => 1,
        'mpi_name'          => 1,
        'mpi_version'       => 1,
        'bitness'           => 1,
        'endian'            => 1,
        'compiler_name'     => 1,
        'compiler_version'  => 1,

        # phase-specific
        'suite_name'        => 1,
        'test_name'         => 1,
        'np'                => 1,

        # performance
        'message_size'      => 1,
        'bandwidth_min'     => 1,
        'bandwidth_max'     => 1,
        'bandwidth_avg'     => 1,
        'latency_min'       => 1,
        'latency_max'       => 1,
        'latency_avg'       => 1,
    );

    foreach (array_keys($layout) as $column)
        if (isset($columns[$column]))
            $ordering[$column] = $columns[$column];

    return $ordering;
}

# Add these to select statements for Detail reports
function detail_fields($phase) {

    # MPI Install
    if ($phase == 'mpi_install')
        $phase_columns = array(
            'compiler_version' => 'compiler_version',
            'vpath_mode' => 'vpath_mode',
        );

    # Test Build
    if ($phase == 'test_build')
        $phase_columns = null;

    # Test Run
    if ($phase == 'test_run')
        $phase_columns = array(
            'command' => 'command',
            'variant' => 'variant',
        );

    $results_columns = array(
        'exit_status'     => 'exit_status',
        'signal'          => 'signal',
        'start_timestamp' => 'start_timestamp',
        'duration'        => 'duration',
        'result_message'  => 'result_message',
        'result_stdout'   => 'result_stdout',
        'result_stderr'   => 'result_stderr',
        'environment'     => 'environment',
        'client_serial'   => 'client_serial',
    );
    
    return 
        array('select_more' => 
            array_merge(
                $phase_columns,
                $results_columns
            )
        );
}

# Return performance columns
function performance_fields() {
    return 
        array('performance' =>
            array(
                'message_size'  => 'message_size',
                'bandwidth_min' => 'bandwidth_min',
                'bandwidth_max' => 'bandwidth_max',
                'bandwidth_avg' => 'bandwidth_avg',
                'latency_min'   => 'latency_min',
                'latency_max'   => 'latency_max',
                'latency_avg'   => 'latency_avg',
            )
        );
}

#########################################
#                                       
#  String Processing Functions
#                                     
#########################################

# The following process_*_field(s) functions return arrays
# Convert English words to integers (1-10)
function strtonumeral($str) {

    $words_to_numerals = array(
        'zero'  => 0,
        'one'   => 1,
        'two'   => 2,
        'three' => 3,
        'four'  => 4,
        'five'  => 5,
        'six'   => 6,
        'seven' => 7,
        'eight' => 8,
        'nine'  => 9,
        'ten'   => 10,
    );

    $converted = $words_to_numerals[strtolower($str)];

    if ($converted)
        return $converted;
    else
        return $str;
}

# Remove the prefix part of the parameter,
# which will leave only a database column name
function strip_prefix($str) {
    return preg_replace('/^more_|^show_|^text_/', '', $str);
}

function suffix_list($arr, $sfx) {
    $tmp = array();
    foreach ($arr as $a)
        $tmp[] = $a . $sfx;
    return $tmp;
}

# Generate the shorthand for the given phase-result code (see process_result_fields)
function result_str($phase, $result) {
    $abbrevs = array(
        'mpi_install' => 'i',
        'test_build' => 'b',
        'test_run' => 'r',
    );
    return '_' . $abbrevs[$phase] . substr($result, 0, 1);
}

#########################################

?>
