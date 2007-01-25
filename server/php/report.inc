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

#
#
# Print a report
#
#

$topdir = ".";
include_once("$topdir/reporter.inc");
include_once("$topdir/database.inc");

# Global variables
$new_ttable;
$date_fields;

# Top-level report printing function
#   1. Print the query screen
#   2. Print the report
function dump_report() {

    # Create or update cookie, and set
    # definitions accordingly
    process_cookie($_GET, $_COOKIE);

    # Display input parameters
    debug_cgi($_GET, "GET " . __LINE__);

    # Fresh web page is brought up
    if (! isset($_GET['go']) and 
        ! isset($_GET['click']))
        $nogo = true;
    else
        $nogo = false;

    if (! $nogo) {

        # Process session/cache/temp-table thingy
        $ttable_id_field = process_ttable_id_field($_GET);

        # cherry_fields are the only fields that
        # are filtered by PHP instead of SQL
        $cherry_fields = process_cherry_fields($_GET);

        # Process/mutator controls
        # (they need to come first, because _GET could be mutated here)
        $report_type = process_report_type($_GET);

        # There are oddball field(s) that we constrain *for* the user
        process_oddball_fields($_GET);

        # Process input params
        $phases          = process_phase_field($_GET);
        $date_fields     = process_date_field($_GET);
        $large_fields    = process_large_fields($_GET);
        $input_fields    = process_input_fields($_GET);
        $result_fields   = process_result_fields($phases, $_GET);
        $sort_field      = process_sort_field($_GET);
        $offset_field    = process_offset_field($_GET);

        $trial_field     = process_trial_field(TRIAL);

        # Print either a summary or detail report,
        # depending on whether a 'select_more' parameter is set
        if ($report_type == 'detail') {
            $do_detailed = true;
            $detail_fields = setup_detail_fields(get_scalar($phases));
        } elseif ($report_type == 'performance') {
            $do_performance = true;
            $performance_fields = setup_performance_fields();
        } else
            $do_summary = true;

        # Prepare query components
        $query = array_merge_recursive(
            $date_fields,
            $ttable_id_field,
            $input_fields,
            $large_fields,
            $result_fields,
            $detail_fields,
            $performance_fields,
            $sort_field,
            $offset_field,
            $trial_field
        );

        # Order columns left-to-right
        $query['select']      = order_columns($query['select']);
        $query['select_more'] = order_columns($query['select_more']);

        # Pass down phases field
        $query['phases'] = $phases;

        # Compose query
        $cmd = compose_sql($query);

        # Execute query
        $resource = do_pg_query($cmd);

        # Number of rows in this report
        $rowcount = pg_num_rows($resource);
        $n = rowcount($rowcount, $_GET);
        $o = offset($_GET);

        # Prepare headers array for *_table functions
        $headers['params']      = array_keys($query['select']);
        $headers['details']     = array_keys($query['select_more']);
        $headers['performance'] = array_keys($query['performance']);
        $headers['results']     = array_keys($query['aggregates']);
        $headers['phases']      = $phases;
        $headers['offset']      = $o;
    }

    # Print the user query screen
    dump_query_screen($nogo);

    # Exit if a button hasn't been pressed
    if ($nogo)
        return;

    # Print some basic, useful info atop each report table
    report_header($date_fields, $phases, $n);
    
    # Do not print an empty table
    if (pg_num_rows($resource) < 1) {
        print "<b><i>No data available for the specified query.</i></b>";
        return;
    }

    # Report chunks index
    $slices_links = slices_links($n, LIMIT, $_GET);

    print $slices_links;

    if ($do_detailed)
        detail_table($headers, $resource);
    elseif ($do_summary)
        summary_table($headers, $resource, $cherry_fields);
    elseif ($do_performance) {
        summary_table($headers, $resource, $cherry_fields);
    }

    print $slices_links;

    # Clean up old graphs, csv dumps, and ttables
    housekeeping('./tmp');
    housekeeping_db('ttable');

    pg_close();
}

#########################################
#                                       
#  Report Table Generating Functions
#                                     
#########################################

# Void function to print out a Detail style HTML table
function detail_table($headers, $resource) {

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
        printf("\n<th bgcolor='" . THCOLOR . "'>%s", $labels[$result]);
    }

    # Row numbering starts at the OFFEST arg to LIMIT
    $offset = $headers['offset'];
    $php_row_n = $offset;
    $lastrow = $offset + LIMIT;

    # Remove duplicated headers
    $headers = array_unique(
        array_merge(
            $headers['params'],
            $headers['details']
        )
    );

    # Print data rows
    while ($row = pg_fetch_row($resource)) {

        if ($php_row_n >= $lastrow)
            break;

        # Results are always in the far right cols
        $results = array_splice($row, $num_cols['params']);

        # Splice in the php_row_n in place of db_row_n
        $db_row_n = array_shift(array_splice($row, 0, 1, ($php_row_n + 1)));

        # Stylize rows of "--trial" results
        $trial = process_trial_value($row, 1);

        # Details are always in the far far right cols
        $details = array_splice($results, $num_cols['results']);

        list($pass,
             $fail,
             $skip,
             $time,
             $perf) = $results;

        if ($pass)
            $bgcolor = (($pass > 0) ? stylize_trial_color(LGREEN, $trial)  : "");
        elseif ($fail)
            $bgcolor = (($fail > 0) ? stylize_trial_color(LRED, $trial)    : "");
        elseif ($skip)
            $bgcolor = (($skip > 0) ? stylize_trial_color(LYELLOW, $trial) : "");
        elseif ($time)
            $bgcolor = (($time > 0) ? stylize_trial_color(LYELLOW, $trial) : "");
        elseif ($perf)
            $bgcolor = (($time > 0) ? stylize_trial_color(LBLUE, $trial)   : "");

        print "<table border='1' width='100%'>" .
              "<tr><td bgcolor='$bgcolor'>";

        $td = "<td bgcolor='" . LGRAY . "' width='10%' valign='top'>";
        $tdl = "<td bgcolor='" . stylize_trial_color(WHITE, $trial) . "'>";

        $values =
            array_merge(
                $row,
                $details
            );

        $i = 0;
        print "<table border='1' width='100%'>";
        foreach ($headers as $header) {
            print (($i % 1 == 0) ? "\n<tr>" : "") .
                  "\n$td <b>" . stylize_trial_font(label($header), $trial) . "</b> $tdl " .
                  "\n<pre>" . stylize_trial_font(highlight_match($header, wordwrap($values[$i], WRAP)), $trial) . "</pre>";
            $i++;
        }
        print "</table>";
        print "</table><br>";

        $php_row_n++;
    }

    print "\n</table>" .
          "\n</table>" .
          "\n\n<!-- report_end -->\n\n";
}

# Wrap matches with HTML FONT tags to visually highlight them
function highlight_match($param, $value) {

    $match = $_GET["text_$param"];
    $match = preg_replace("/;/", "|", $match);

    # "all" is the magic word for *no filter*
    if ($match == 'all')
        return $value;
    else
        return preg_replace(
                    "/(" . escape_nonword_chars($match) . ")/i",
                    "<font style=\"background-color:yellow\">$1</font>",
                    $value
               );
}

# Escape non-word characters ([0-9a-zA-Z_]),
# except ^ and $ ... we really mean those
function escape_nonword_chars($str) {
    return preg_replace('/([^\w\^\$])/', "\\\\$1", $str);
}

# Return true if the row is a row flagged "--trial"
# X: THE trial VALUE IS ALWAYS ON THE FAR LEFT (TO THE RIGHT
# OF THE DB ROW NUMBER)
function process_trial_value($row, $i) {
    if (TRIAL) {
        if ($row[$i] == TRIAL_TRUE)
            return true;
        else
            return false;
    }
}

# Print out a summary table
# (and maybe a performance graph)
function summary_table($headers, $resource, $filter) {

    # Are we dumping Performance graphs?
    if (preg_match("/performance/i", $_GET['go']))
        $do_performance = true;

    # Insert useful information on the left-hand side?
    print "\n<div align='center'>" .

          "\n<!-- report_start -->\n\n" .

          "\n<table width='100%' cellpadding='5'>" .
          "\n<tr>" .
          "\n<td bgcolor='" . LGRAY . "'>" .
          "\n<table border='1' width='100%'>";

    # Display headers
    $format  = "\n<th bgcolor='" . THCOLOR . "' rowspan=2>%s";
    $format2 = "\n<th bgcolor='" . THCOLOR . "' rowspan=2 width='1%%'>%s";

    print "<tr>";
    if (allow_cherry_picking($_GET))
        print sprintf($format2, '') .
                # X: MAKE THIS CHECKBOX ''CHECK ALL'' THE BOXES
                #
                #             "<input " . 
                #                 "type='checkbox' " . 
                #                 "name='all_cherries' " . 
                #                 "value='on' " . 
                #                 "checked>") .
                "";

    $pound_sign = array_shift($headers['params']);
    printf($format, label($pound_sign));
    foreach (sorting_links($headers['params']) as $header)
        printf($format, $header);

    # Setup sequence of result colors
    $phases = $headers['phases'];
    $result_colors = result_colors($phases);

    # Create links for drilled-down queries
    $links = drilldown_links($headers['phases']);

    # Print phase headers
    $total_results_cols = 0;
    foreach (array_keys($links) as $phase) {
        $link = array_shift($links[$phase]);
        $colspan = sizeof($links[$phase]);
        $num_result_types[$phase] = $colspan;

        printf("\n<th bgcolor='" . THCOLOR . "' " .
                     "colspan='$colspan'>%s",
                     $link);
        $total_results_cols += $colspan;
    }

    print "\n<tr>";

    # Print phase headers
    foreach (array_keys($links) as $phase)
        foreach ($links[$phase] as $result)
            printf("\n<th id='result' bgcolor='" . THCOLOR . "'>%s", $result);

    # Calculate some colspans
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
    $php_row_n = $offset;
    $lastrow = $offset + LIMIT;

    # printf formats
    $format   = "\n<td bgcolor='%s' align='right'>%s";
    $formatg  = "\n<td bgcolor='" . LGRAY . "' align='right'>%s";
    $formatgc = "\n<td bgcolor='" . LGRAY . "' align='center'>%s";
    $formatw  = "\n<td bgcolor='%s'>";

    # Print data rows
    while ($row = pg_fetch_row($resource)) {

        if ($php_row_n >= $lastrow)
            break;

        # Results are always in the far right cols
        $results = array_splice($row, $num_cols['params'] + 1); # (+1 for row #)

        # Grab the db_row_n
        $db_row_n = array_shift($row);

        # Grab the trial boolean
        $trial = process_trial_value($row, 0);

        # Skip unchecked cherry rows
        if ($filter)
            if (! isset($filter[$db_row_n]))
                continue;

        # Checkbox off the db_row_n, but display ascending php_row_n
        print "\n<tr>";

        if (allow_cherry_picking($_GET))
            printf($formatgc, cherry_checkbox($db_row_n));

        printf($formatg, ($php_row_n + 1));

        for ($i = 0; $i < sizeof($row); $i++) {
            printf($formatw, stylize_trial_color(WHITE, $trial));
            print stylize_trial_font(
                            drilldown_links($headers['params'][$i], $row[$i]),
                            $trial);
        }

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
                    (($pass_count > 0) ? 
                        stylize_trial_color($result_colors[$j], $trial) : LGRAY), 
                        stylize_trial_font($pass, $trial));
            $j++;
            printf($format,
                    (($fail_count > 0) ? 
                        stylize_trial_color($result_colors[$j], $trial) : LGRAY), 
                        stylize_trial_font($fail, $trial));
            $j++;
            if (! is_null($skip)) {
                printf($format,
                        (($skip_count > 0) ? 
                            stylize_trial_color($result_colors[$j], $trial) : LGRAY), 
                            stylize_trial_font($skip, $trial));
                $j++;
            }
            if (! is_null($time)) {
                printf($format,
                        (($time_count > 0) ?
                            stylize_trial_color($result_colors[$j], $trial) : LGRAY), 
                            stylize_trial_font($time, $trial));
                $j++;
            }
            if (! is_null($perf)) {
                printf($format,
                        (($perf_count > 0) ?
                            stylize_trial_color($result_colors[$j], $trial) : LGRAY), 
                            stylize_trial_font($perf, $trial));
                $j++;
            }

            # Tally totals for all result counts
            foreach ($ret['counts'] as $count) {
                $totals[$i++] += $count;
            }

        }

        # Complile some performance data, if requested
        if ($do_performance) {

            $performance = array_slice($results, 0 - $num_cols['performance']);

            # Prepare perf data to be displayed in a graph
            $hash = array_combine(
                        $headers['performance'], 
                        array_map('csv2arr', $performance)
                    );
            $graph_data['plots'][$php_row_n] = $hash;

            # Prepare legend data for each individual line plot
            array_combine2($graph_data['legend'], $headers['params'], $row);

            # Prepare global legend data for the entire perf graph
            $hash = array_combine(
                        $headers['params'], 
                        $row
                    );
            $graph_data['params'][$php_row_n] = $hash;
        }

        $php_row_n++;
    }

    table_footer($totals, $headers, $result_colors);

    print "\n</table>" .
          "\n</table>" .
          "\n<!-- report_end -->" .
          "</div>";

    # Print performance graphs
    if ($do_performance)
        performance_graphs($graph_data);
}

# Change font style for a row of "--trial" results
function stylize_trial_font($str, $trial) {
    if ($trial)
        return '<i>' . $str . '</i>';
    else
        return $str;
}

# Change table cell color of "--trial" results
function stylize_trial_color($color, $trial) {
    if ($trial) {
        if ($color == WHITE)
            return LLLGRAY;
        elseif ($color == LRED)
            return DRED;
        elseif ($color == LGREEN)
            return DGREEN;
        elseif ($color == LYELLOW)
            return DYELLOW;
        elseif ($color == LBLUE)
            return DBLUE;
    } else
        return $color;
}

# Output a checkbox for cherry-picking feature
function cherry_checkbox($n) {
    return "<input type='checkbox' " .
            "name='cherry_$n' " . 
            "value='on' " .
            "checked>";
}

# Only allow cherry picking for Performance reports
function allow_cherry_picking($params) {
    return preg_match("/latency|perf/i", $params['go']);
}

# Print the totals and a cherry-picking button 
# at the foot of the summary table
function table_footer($totals, $headers, $result_colors) {

    $top = DOCROOT;

    # Carryover the report type
    $type = strtolower(process_report_type($_GET));

    print "\n<tfoot><tr>";

    # Print cherry button
    if (allow_cherry_picking($_GET))
        print "\n<td bgcolor='" . LGRAY . "' align='center'>" .
              "\n<button name='go' value='${type}_cherry' type='submit'>" .
                  "\n<img src='$top/images/cherries.gif' width='20' border='0'>" .
              "\n</button>";

    # Print totals
    print "\n<td align='left' " .
                "bgcolor='" . LGRAY . "' " .
                "colspan='" . (sizeof($headers['params']) + 1) . "'>" .
          "\n<b>Totals</b>";

    $i = 0;
    foreach ($totals as $total) {
        print "\n<td align='right' " .
                     "bgcolor='" . (($total > 0) ? $result_colors[$i] : LGRAY) . "'" .
                 "><b>$total</b>";
        $i++;
    }
    print "\n</tfoot>";
}

#########################################
#                                       
#  Report Graph Generating Functions
#                                     
#########################################

# Print all the available performance graphs
function performance_graphs($data) {

    # Do graph(s)
    $types = array(
        'latency_avg',
        'latency_min',
        'latency_max',
        'bandwidth_avg',
        'bandwidth_min',
        'bandwidth_max',
    );

    foreach ($types as $type) {
        $ret = do_graph($data, $type);
        if (! is_null($ret)) {
            $images[] = $ret['image'];
            $widths[] = $ret['width'];
            $raws[] = $ret['raw'];
        }
    }

    $total_width = array_sum($widths);

    # Calculate how many graphs to show per row
    # (Using best guess screen size)
    $avg_width = $total_width/sizeof($widths);
    $cols = floor(SCREEN_WIDTH/$avg_width);

    # Display graphs
    print "<br><table width='100%'>";

    $i = 0;
    foreach ($images as $image) {
        print ((($i % $cols) == 0) ? "<tr>" : "") .
                "<td align='center'>" .  $image .
                "<br><br>Raw data: " .  $raws[$i] . "<br><br>";
        $i++;
    }
    print "</table>";
}

# Print out the actual binary image data
# Uses jpgraph (http://www.aditus.nu/jpgraph)
# type = latency*|bandwidth* 
function do_graph($data, $type) {

    $type = strtolower($type);

    $jpgraph_dir = './jpgraph';
    include_once("$jpgraph_dir/jpgraph.php");
    include_once("$jpgraph_dir/jpgraph_line.php");
    include_once("$jpgraph_dir/jpgraph_log.php");

    # Set axis label unit
    $unit = get_axis_unit($type);

    # Collect graph data
    list($datapoints,
         $lineplots,
         $message_sizes,
         $legend_items,
         $title,
         $subtitle) = collect_graph_data($data, $type);

    # Return nothing if we have no line plots
    if (is_null($lineplots))
      return;

    list($width, 
         $height,
         $xfont,
         $margins,
         $legend_cols) = 
            get_graph_dimensions($legend_items, $message_sizes);

    # Create the graph. These two calls are always required
    $graph = new Graph($width, $height, "auto");    

    # Set axis scaling (default: 'textlin')
    $yscale = YAXIS_SCALE;
    $xscale = XAXIS_SCALE;

    if (! $xscale)
        $xscale = 'text';
    if (! $yscale or $yscale == 'text')
        $yscale = 'lin';

    $scale = "$xscale$yscale";

    $graph->SetScale($scale);

    # Do not let the plots go off the bottom of the graph!
    $ymin = min(array_map('min', $datapoints));
    $ymin2 = array_map('min', $datapoints);

    # For logarithmic axis scaling, JpGraph incorrectly
    # defaults to 10^0 when the min approaches zero, set the
    # y-minimum to 10^-2 (0.01)
    if ($ymin < 0.01 and $yscale == 'log')
        $graph->yaxis->scale->SetAutoMin(-2);

    $gJpgBrandTiming = true;

    list($lmargin,
         $rmargin,
         $tmargin,
         $bmargin) = array_values($margins);
    $graph->img->SetMargin($lmargin, $rmargin, $tmargin, $bmargin);
    
    # Setup legend
    $graph->legend->SetPos(0.05,0.95, 'right','bottom');
    $graph->legend->SetColumns($legend_cols);
    $graph->legend->SetLineWeight(10);

    # Setup titles
    $graph->title->Set($title);

    if (! HIDE_SUBTITLE)
        $graph->subtitle->Set($subtitle);

    $graph->subtitle->ParagraphAlign("left");
    $graph->title->SetFont(FF_FONT1, FS_BOLD);
    $graph->subtitle->SetFont(FF_FONT1, FS_NORMAL);

    # Setup axes
    $titles['xaxis'] = "Message size - bytes";
    $titles['yaxis'] = label($type) . " - $unit";

    $graph->xaxis->SetTickLabels($message_sizes);
    $graph->xaxis->SetLabelAngle(90);
    $graph->xaxis->SetFont($xfont);
    $graph->xaxis->SetTitleMargin(25);
    $graph->yaxis->SetTitleMargin(40);
    $graph->xaxis->setTitle($titles['xaxis'], "middle");
    $graph->yaxis->setTitle($titles['yaxis'], "middle");
    $graph->xaxis->title->SetFont(FF_FONT1, FS_BOLD);
    $graph->yaxis->title->SetFont(FF_FONT1, FS_BOLD);

    # Plot the lines
    foreach (array_keys($lineplots) as $i) {
        $graph->Add($lineplots[$i]);
    }

    $graph->SetShadow();

    # Write the graph to a file
    # (Timestamp it so the browser doesn't reload a cached
    # image when/if the user changes a graphing preference)
    $filename = "./tmp/".time().'_'.title2filename($title.' '.$type.' '.$subtitle).'.png';
    unlink($filename);
    $graph->Stroke($filename);

    # Snarf plots argument
    $plots = $data['plots'];

    # Create 2D array to feed to raw data output function
    $meta_data['title']          = $title;
    $meta_data['subtitle']       = $subtitle;
    $meta_data['unit']           = $unit;
    $meta_data['type']           = $type;
    $meta_data['legend_items']   = $legend_items;
    $table_data['message_sizes'] = $message_sizes;
    $table_data['plots']         = $plots;

    $arr = prepare_raw_data_arr($meta_data, $table_data);
    $raw = prepare_raw_data_links($arr);

    $image = "<img src='$filename' " .
                  "alt='$title' " .
                  "border='0'>";

    # Return links to the image, raw data, and width
    $ret = array(
        'image' => $image,
        'raw'   => $raw,
        'width' => $width
    );

    return $ret;
}

function get_graph_dimensions($legend_items, $message_sizes) {

    # Default margin sizes
    $margins['left']   = 60;
    $margins['right']  = 50;

    # Top margin is adjusted automatically for
    # title/subtitle 
    $margins['top']    = 0;

    # Bottom margin for legend
    $margins['bottom'] = 80;

    # Font width in pixels (NEED A WAY TO DETERMINE THESE
    # NUMBERS CORRECTLY!)
    $fontwidth = 6.2;
    $fontheight = 6;
    $legend_mark = 20;
    $legend_entry_width = $fontwidth *
                    max(array_map('strlen', $legend_items)) +
                    $legend_mark;
    $legend_width = $legend_entry_width;

    # Best guess for pixel:char and line:char ratios
    # WE WOULD HAVE TO GUESS AGAIN IF WE CHANGE FONT!
    # (NEED A BETTER WAY TO GET PIXEL SIZE OF FONTS)
    $c2p = 20;
    $l2p = 21;
    
    # Set image dimensions 
    # Width: based on ticks on the x-axis (and legend, if wide)
    # Height: based on max latency/bw value
    $xticks = sizeof($message_sizes);
    $width = $xticks * $c2p;
    $height = 400;

    list($width, $xfont) = constrain_graph_attrs($width);

    $legend_cols       =  floor($width / $legend_entry_width);
    $legend_cols       =  max(1, $legend_cols);
    $legend_rows       =  ceil(sizeof($legend_items) / $legend_cols);
    $height            += $legend_rows * $l2p;
    $margins['bottom'] += $legend_rows * $l2p;

    # Will the legend go off the edge?
    if ($legend_cols)
        $legend_width = $legend_entry_width * $legend_cols;

    if ($legend_rows)
        $legend_height = $fontheight * $legend_rows;

    # Pad for a tight-fit legend
    $diff = abs($legend_width - $width);
    $width += $diff + 50;

    list($width, $xfont) = constrain_graph_attrs($width);

    $ret = array(
        $width, 
        $height, 
        $xfont,
        $margins,
        $legend_cols
    );

    return $ret;
}

function get_axis_unit($type) {
    if (preg_match("/latency/i", $type))
        $unit = 'usec';
    elseif (preg_match("/bandwidth/i", $type))
        $unit = 'Mbps';

    return $unit;
}

# Collect and massage graph data
function collect_graph_data($data, $type) {

    # Process inputs
    $legend = $data['legend'];
    unset($data['legend']);

    $params = $data['params'];
    unset($data['params']);

    $plots = $data['plots'];
    unset($data['plots']);

    # Setup line plot colors
    static $colors;
    if (! $colors)
        $colors = graph_colors();

    # Set up titles
    $title = "MTT Performance Results";
    $subtitle = create_subtitle($legend);

    # Tests may have differing lists of message sizes,
    # so find the longest series for the x-axis
    $pad = 0;
    foreach (array_keys($plots) as $i) {
        $message_size = $plots[$i]['message_size'];
        if ($pad < sizeof($message_size)) {
            $message_sizes = $message_size;
            $pad = sizeof($message_size);
        }
    }

    $j = 0;

    # Collect the line plots
    foreach (array_keys($plots) as $i) {
        
        $line = $plots[$i][$type];

        # Create the linear plot
        if ($line) {
            $empty = false;

            $ydata = array_pad($line, $pad, null);

            $color = $colors[$j++];

            # Avoid null color error
            if (! $color)
                $color = 'black';

            $lineplots[$i] = new LinePlot($ydata);
            $datapoints[$i] = $ydata;

            # Human row numbers are +1
            $legend_items[$i] = 
                ($i + 1) . ' ' . create_legend_item($params[$i], $legend);

            $lineplots[$i]->SetColor($color);
            $lineplots[$i]->SetWeight(2);
        }
    }

    # Do not print a legend for a single line plot
    if (sizeof($legend_items) > 1)
        foreach (array_keys($legend_items) as $i)
            $lineplots[$i]->SetLegend($legend_items[$i]);

    return array($datapoints,
                 $lineplots,
                 $message_sizes,
                 $legend_items,
                 $title,
                 $subtitle);
}

# Create 2D array to feed to raw data output function
function prepare_raw_data_arr($meta, $data) {

    $title         = $meta['title'];
    $subtitle      = $meta['subtitle'];
    $unit          = $meta['unit'];
    $type          = $meta['type'];
    $legend_items  = $meta['legend_items'];
    $message_sizes = $data['message_sizes'];
    $plots         = $data['plots'];

    $i = 0;
    $arr[$i++] = $title . "<br>" . label($type);
    $arr[$i++] = $subtitle;
    $arr[$i++] = 'bytes';
    $arr[$i++] = $unit;

    # Note: There is no legend item that goes above message size
    foreach (array_keys($plots) as $p) {
        if (! is_null($legend_items[$p]))
            $arr[$i][] = $legend_items[$p];
    }
    $i++;

    for ($j = 0; $j < sizeof($message_sizes); $j++) {
        $arr[$i][0] = $message_sizes[$j];
        $k = 1;
        foreach (array_keys($plots) as $p) {
            if ($plots[$p][$type]) {
                $arr[$i][$k++] = $plots[$p][$type][$j];
            }
        }
        $i++;
    }

    return $arr;
}

# Return links to raw data in HTML and CSV format
function prepare_raw_data_links($arr) {

    # Adjust size of raw data links
    $cols = max(array_map('sizeof', array_values($arr)));
    $rows = sizeof($arr);
    $rwidth = (90 * $cols) + 50;
    $rheight = ((20 * $rows) + 200);
    if ($rheight > 800)
        $rheight = 800;
    if ($rwidth > SCREEN_WIDTH)
        $rwidth = SCREEN_WIDTH;

    # Setup list of raw data formats
    $styles = array(
                'HTML' => 'html', 
                'CSV'  => 'text');

    # Provide popups for raw data
    foreach (array_keys($styles) as $style) {
        $ctype = strtolower($styles[$style]);

        if ($ctype == 'html')
            $raw .=
                "\n<a class='black_ln' href='javascript:popup_${ctype}(" .
                    "\n\"" . $rwidth . "\", " .
                    "\n\"" . $rheight . "\"," .
                    "\n\"Raw performance numbers\"," .
                    "\n\"\"," .
                    "\n\"" . htmlentities(raw_data($arr, $style), ENT_QUOTES) . "\"," .
                    "\n\"font-family:Courier,monospace\"" .
                ")' " .
                ">" .
                "\n$style" .
                "</a>&nbsp;";
        elseif ($ctype == 'text')
            $raw .=
                "\n<a href='" . raw_data($arr, $style) . "'>$style</a>&nbsp;";
    }
    return $raw;
}

# Max-out/bottom-out image/font size
function constrain_graph_attrs($width) {
    $font = FF_FONT1;
    if ($width > SCREEN_WIDTH) {
        $width = SCREEN_WIDTH;
        $font = FF_FONT0;
    } elseif ($width < 250)
        $width = 250;

    return array($width, $font);
}

# Convert a 2D array (output by do_graph) to an HTML or CSV table
# HTML: returns HTML string
# CSV: returns .csv filename 
#
# X: IT WOULD BE PREFERABLE TO DO CSV THE SAME WAY WE DO HTML
# SO THAT THE LINK NEVER "EXPIRES"
function raw_data($arr, $style) {

    # Headers are always here
    $colspan = sizeof($arr[5]) - 1;

    # Number of plots = colspan
    $plots = $colspan;

    # HTML
    if (strtolower($style) == 'html') {
        $tbl  = "\n<br><table border='1'>";
        $tbl_ = "\n</table>";
        $tr   = "\n<tr>";
        $tdr  = "\n<td align='right'>";
        $th   = "\n<th bgcolor='" . LGRAY . "'>";
        $tdl  = "\n<td bgcolor='" . LGRAY . "'>";
        $tdll = "\n<td bgcolor='" . LLGRAY . "' align='right'>";
        $ths  = "\n<th bgcolor='" . LGRAY . "' colspan='$colspan'>";
        $tdc  = "\n<td bgcolor='" . LGRAY . "' align='center'>";
        $tdc_ = "\n<td bgcolor='" . LGRAY . "' align='center'>";
        $br  = "<br>";

        # Functions for eval
        $sp2func  = "sp2br";
        $nl2br  = "nl2br";
    }
    # CSV
    else {
        $tbl_ = "\n";
        $tdll = "\ndata:";
        $tdr  = ",";
        $th   = "data:column-units:";
        $ths  = ",";
        $tdc_ = "\ndata:column-names:message-size, ";
        $tdc  = ",";
        $br_  = "title:";

        # Functions for eval
        $nl2br     = "";
        $unalign   = "unalign";
        $stripfunc = "strip_html";
        $br2hyphen = "br2hyphen";

        # Repeat column unit (e.g., usec) per number of
        # columns 
        $str_repeat = 
            '$str = ' .
                'rtrim(' . 
                    'str_repeat(' .
                        '"," . $arr[$i + 1], ' .
                        'sizeof($arr[$i + 2]) - 1' .
                    '), ","' . 
                ');';
    }

    $i = 0;

    # Title
    eval("\$title = $br2hyphen(\$arr[\$i]);");
    $content .= "$br_$br<b>" . $title . "</b>";
    $i++;

    # Subtitle
    eval("\$subtitle = $nl2br(\$arr[\$i]);");

    # Prepare a logical filename for the CSV file
    $filename = './tmp/'.title2filename($title.$subtitle).'.csv';

    eval("\$subtitle = $unalign(\$subtitle);");
    $content .= "$br<b><i>" . font('-1', $subtitle) . "</b></i>";
    $i++;

    $content .= $tbl;
    $content .= $tr;

    # Repeat the unit for the number of legend columns
    eval($str_repeat);
    
    # "bytes", "usec or Mbps"
    $content .= $th  . font('-2', $arr[$i++]);
    $content .= $ths . font('-2', $arr[$i++] . $str);
    $content .= $tr;
    $content .= $tdl;

    # Headers (legend items)
    $j = 0;
    foreach ($arr[$i] as $cell) {
        eval("\$cell = $sp2func('$cell');");
        $content .= ($j++ ? $tdc : $tdc_) . font('-2', $cell);
    }

    # For each message size ...
    for ($i++; $i < sizeof($arr); $i++) {
        $content .= $tr;
        $content .= $tdll . font('-2', $arr[$i][0]);

        # ... print the corresponding latency/bandwidth
        # values for the message size
        for ($j = 1; $j <= $colspan; $j++) {
            if (! is_null($arr[$i][$j]))
                $data = sprintf("%01.2f", $arr[$i][$j]);
            else
                $data = null;
            $content .= $tdr . font('-2', $data);
        }
    }
    $content .= $tbl_;

    # If it's a CSV, strip all the tags out
    eval("\$content = $stripfunc(\$content);");

    # Write the CSV to a file
    if (strtolower($style) == 'csv') {
        unlink($filename);
        $fh = fopen($filename, 'x');
        fwrite($fh, $content);
        fclose($fh);
        return $filename;
    }
    # Return an HTML string
    else
        return $content;
}

function title2filename($str) {
    $cclass = '[a-zA-Z0-9_ \t]';
    $str = preg_replace("/$cclass+:\s+/", "_", $str);
    $str = preg_replace('/\s+|\n+|\r+/', '_', $str);
    return $str;
}

function strip_html($str) {
    return strip_tags($str);
}

# For unaligning the subtitle for the CSV dump
function unalign($str) {
    $arr = explode("\n", $str);
    foreach ($arr as $l) {
        if (preg_match('/^([^:]+):\s+(.*)$/', $l, $m)) {
            $left = preg_replace('/\s+/', ':', strtolower($m[1]));
            $right = $m[2];
            $ret .= "\nsubtitle:" . $left . ':' . $right;
        }
    }
    return $ret . "\n";
}

# Wrap a string in font tags
function font($size, $str) { 
    return sprintf("<font size='%s'>%s</font>", $size, $str);
}

# ' ' -> '<br>'
function sp2br($str) {
    return preg_replace('/\s+/', '<br>', $str);
}

# '<br>' -> ' - '
function br2hyphen($str) {
    return preg_replace('/<br>/', ' - ', $str);
}

# Return HTML colors for the lineplots
function graph_colors() {
    return array(
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
}

# Return a subtitle out of items that would be redundant in
# the legend (whack those would-be legend items)
function create_subtitle(&$legend) {

    # Remove singletons from legend and put them in 
    # the subtitle
    foreach (array_keys($legend) as $k) {
        $items = array_keys($legend[$k]);
        if (sizeof($items) == 1) {
            unset($legend[$k]);
            $subtitle[$k] = array_shift($items);
        }
    }

    $subtitle_pad = max(
                      array_map('strlen', 
                        array_map('label', 
                          array_keys($subtitle)))) + 3;

    # Loop through the singletons and create a nicely aligned table
    foreach (array_keys($subtitle) as $k) {
        $item = $subtitle[$k];
        $ret .= "\n" . str_pad(label($k) . ': ', $subtitle_pad) . $item;
    }

    $ret .= "\n";

    return $ret;
}

# Return string for a given hash entry. 
# $legend is keyed by params that are *not* in the subtitle,
# because they differ across lineplots
function create_legend_item($hash, $legend) {

    foreach (array_keys($legend) as $k)
        if (isset($legend[$k]))
            $items[] = $hash[$k];

    $ret = join(' ', $items);
    
    return $ret;
}

# Generate a random string
# function randstr($length) {
# 
#     $pattern = "abcdefghijklmnopqrstuvwxyz";
#     for($i = 0; $i < $length; $i++) {
#         if (isset($key))
#             $key .= $pattern{rand(0,26)};
#         else
#             $key = $pattern{rand(0,26)};
#     }
#     return $key;
# }

#########################################

# Return a sequence of result cell bgcolors
function result_colors($phases) {

    # Arrayify the argument
    if (! is_array($phases))
        $phases = array($phases);

    if (array_search('mpi_install', $phases) !== false) {
        $colors[] = LGREEN;
        $colors[] = LRED;
    }
    if (array_search('test_build', $phases) !== false) {
        $colors[] = LGREEN;
        $colors[] = LRED;
    }
    if (array_search('test_run', $phases) !== false) {
        $colors[] = LGREEN;
        $colors[] = LRED;
        $colors[] = LYELLOW;
        $colors[] = LYELLOW;
        $colors[] = LBLUE;
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
function slices_links($n, $limit, $params) {
    
    # Globalize the date range
    global $date_fields;

    $top = DOCROOT;

    # Convenience arrow for going through 100s of rows
    $img  = "<img src='$top/images/%s_arrow.gif' border='0'>";
    $href = "<a href='$self?%s' class='black_ln' target='_self'>%s</a>";
    $prev = sprintf($img, 'no');
    $next = sprintf($img, 'no');

    $qstring_arr = $params;
    $qstring_arr['rows'] = $n;

    $phase  = process_phase_field($params['phase']);
    $offset = offset($params);

    $go = strtolower($params['go']);

    # Determine report type
    if (preg_match('/(summary|detail)/i', $go, $m))
        $qstring_arr['go'] = $m[1];

    # Differentiate between link clicks and button clicks
    unset($qstring_arr['click']);

    # Report "slices" should use absolute date range
    # because the LIMIT clause may not make sense in
    # the future
    $absolute_date = handle_absolute_date($date_fields);
    $qstring_arr['text_start_timestamp'] = $absolute_date;

    # Flag all the links as slices
    $qstring_arr['slice'] = 1;

    # This is needed because the hidden 'lastgo' is 
    # not passed on an href, only a submit
    $qstring_arr['lastgo'] = $qstring_arr['go'];

    $i = 0;
    while ($i < $n) {
        $qstring_arr['offset'] = $i;
        $label = (($i/$limit) + 1);

        $qstring = arr2qstring($qstring_arr);

        # Numbered links
        if ($i == $offset)
            $links[] = $label;
        else
            $links[] = sprintf($href, $qstring, $label);

        # Arrows
        $prevn = $offset - $limit;
        $nextn = $offset + $limit;
        if ($i == $prevn)
             $prev = sprintf($href, $qstring, sprintf($img, "left"));
        elseif ($i == $nextn)
             $next = sprintf($href, $qstring, sprintf($img, "right"));

        $i += $limit;
    }
    $ret .= "\n<br>";

    # Do not print a lone '1'
    if (sizeof($links) > 1) {
        $ret .= "\n<table width='100%'><tr><td align='center'>";

        # Left arrow
        $ret .= "\n$prev";

        foreach ($links as $link)
            $ret .= "\n&nbsp;$link";

        # Right arrow
        $ret .= "\n&nbsp;$next<br><br>";
    }
    $ret .= "\n</table>";

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
#
# X: THIS FUNCTION IS A MESS! IT SHOULD USE THE SAME
# METHOD OF CREATING A DRILLDOWN FOR EACH CASE. THAT IS,
# TAKE THE EXISTING _GET ARRAY, AND PRUNE/ADD WHAT'S NEEDED
# FOR THE DRILLDOWN (IN OTHER WORDS, form_carryover SHOULD 
# ONLY BE USED FOR AUTO-FILLING A FORM)
function drilldown_links() {

    # This function has three forms (see above comment)
    $argc = func_num_args();

    static $phase_results_table;
    if (! $phase_results_table)
        $phase_results_table = phase_results_table();

    $self = 'http://' . $_SERVER['SERVER_NAME'] . $_SERVER['SCRIPT_NAME'];
    $format = "<a href='$self?%s' class='black_ln' target='_self'>%s</a>";

    # 1. Entire row or data
    #    * Phase, series of param/value pairs, result counts
    #    * For "colored" result count table cells
    #
    # USING TTABLE FOR THIS CASE
    if ($argc == 4) {

        $headers = func_get_arg(0);
        $params  = func_get_arg(1);
        $results = func_get_arg(2);
        $phase   = func_get_arg(3);

        # Drilldowns are not allowed from a cherry-picked report
        # Return plain non-clickable text labels
        if (is_cherry_pick($_GET))
            return array(
                'links' => $results,
                'counts' => $results,
            );

        # Bring over phase-independent selections, and
        # combine them with phase-dependent defaults
        $defaults = setup_mainwin_fields($phase);
        $qstring_arr = form_carryover($defaults);
        $qstring_arr['phase'] = $phase;

        # NOTE: WE CANNOT MARK THIS AS A TRUE DRILLDOWN,
        # BECAUSE WE FETCH EXTRA PHASE-SPECIFIC FIELDS WHICH
        # ARE NOT CACHED IN TTABLE.

        sanitize_qstring_arr($qstring_arr);

        $j = 0;
        # Loop over result count values
        foreach ($results as $count) {

            $i = 0;
            # Loop over header names
            foreach ($headers['params'] as $param) {

                $qstring_arr["text_$param"] = 
                    exact_match($param, $params[$i++]);
            }
            $qstring_arr['test_result'] = $phase_results_table[$phase][$j++];

            $ret['links'][] = sprintf($format, arr2qstring($qstring_arr), $count);
            $ret['counts'][] = $count;
        }
    }

    # 2. Just a single param/value pair
    #    * For "white" parameter table cells
    #    
    # USING TTABLE FOR THIS CASE
    elseif ($argc == 2) {

        $header = func_get_arg(0);
        $param  = func_get_arg(1);

        # We do not know how to provide drilldowns for start_timestamp right
        # now. It would require a lot of conditionalizing about whether a
        # ttable is being used, carrying over the date rollup ('by interval'),
        # etc.
        if ($header == 'start_timestamp')
            return $param;

        # Prepare a query string for manipulation
        # Note the direct assignment from _GET, instead of using
        # form_carryover
        $qstring_arr = $_GET;

        # Unset some fields that may be set illogicallly
        sanitize_qstring_arr($qstring_arr);

        # Mark this as a drilldown so we can use the tttable
        $qstring_arr['drill'] = 1;

        # Drilldowns are not allowed from a cherry-picked report
        # Return plain non-clickable text labels
        if (is_cherry_pick($_GET))
            return $param;

        $qstring_arr["text_$header"] = 
            exact_match($header, $param);

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
    # DO NOT USE TTABLE FOR THIS CASE
    elseif ($argc == 1) {

        $phases = func_get_arg(0);

        # Drilldowns are not allowed from a cherry-picked
        # report. Return plain non-clickable text labels.
        if (is_cherry_pick($_GET)) {
            foreach ($phases as $phase) {
                $ret[$phase][] = label($phase);
                foreach ($phase_results_table[$phase] as $result)
                    $ret[$phase][] = label(label($result));
            }
            return $ret;
        }

        foreach ($phases as $phase) {

            # Bring over phase-independent selections, and
            # combine them with phase-dependent defaults
            $defaults = setup_mainwin_fields($phase);
            $qstring_arr = form_carryover($defaults);
            $qstring_arr['phase'] = $phase;

            # NOTE: WE CANNOT MARK THIS AS A TRUE DRILLDOWN,
            # BECAUSE WE FETCH EXTRA PHASE-SPECIFIC FIELDS WHICH
            # ARE NOT CACHED IN TTABLE.

            sanitize_qstring_arr($qstring_arr);

            # test_result will be getting reset for each
            # result count cell
            unset($qstring_arr['test_result']);
            $ret[$phase][] = sprintf($format, arr2qstring($qstring_arr), label($phase));

            foreach ($phase_results_table[$phase] as $result) {
                $qstring_arr['test_result'] = $result;

                # Do label(label()) because we go from 
                # "result code" to "column name" to "web page label"
                $label = 
                    sprintf($format, arr2qstring($qstring_arr), label(label($result)));
                $header = sorting_links($result, $label, 0.85);
                $ret[$phase][] = $header;
            }
        }
    }

    return $ret;
}

function sanitize_qstring_arr(&$arr) {

    # Globalize the date range
    global $date_fields;

    # Do not bring over LIMIT clause for a drilldown
    unset($arr['rows']);
    unset($arr['offset']);
    unset($arr['slice']);

    # Differentiate between link clicks and button clicks
    unset($arr['click']);

    # Drilldowns should use absolute date range in case
    # the user walks away from the browser for awhile
    # (some data points could slip out of a relative
    # date range)
    $absolute_date = handle_absolute_date($date_fields);
    $arr['text_start_timestamp'] = $absolute_date;

    # Cherries are not applicable for a drilldown report
    unset_cherries($arr);

    # Strip off _cherry|_slice
    $arr['go'] = base_type($arr['go']);

    # This is needed because the hidden 'lastgo' is 
    # not passed on an href, only a submit
    $arr['lastgo'] = $arr['go'];
}

# Return true if the user has clicked the cherry button
function is_cherry_pick($params) {
    $go = $params['go'];
    if (preg_match("/cherry/i", $go))
        return true;
    else
        return false;
}

# Mutator function to clear out all cherry checkbox values
function unset_cherries(&$arr) {
    foreach (array_keys($arr) as $k)
        if (preg_match("/cherry_\d+/i", $k))
            unset($arr[$k]);
}

# Create headers wrapped by up/down sort arrows
# (Rather have this as another if/else in drilldown_links.
# Oh well.) (Override the standard text label with $label
# argument)
function sorting_links($headers, $label, $arrow_size) {

    # Globalize the date range
    global $date_fields;

    $scalar_context = false;
    $default_label = false;

    # Arrayify the argument
    if (! is_array($headers)) {
        $headers = array($headers);
        $scalar_context = true;
    }

    # Drilldowns are not allowed from a cherry-picked report
    # Return plain non-clickable text labels
    if (is_cherry_pick($_GET))
        return array_map('label', $headers);

    # Use standard label by default
    if (is_null($label))
        $default_label = true;

    # Adjust arrow size
    if ($arrow_size) {
        list($width) = getimagesize('./images/right_arrow.gif');
        $size = "width='" . ($arrow_size * $width) . "'";
    }

    # Prepare a query string for manipulation
    $qstring_arr = $_GET;

    # Do not bring over LIMIT or ORDER BY info for a header link
    unset($qstring_arr['orderby_up']);
    unset($qstring_arr['orderby_down']);
    unset($qstring_arr['rows']);
    unset($qstring_arr['offset']);
    unset($qstring_arr['slice']);

    # Differentiate between link clicks and button clicks
    unset($qstring_arr['click']);

    # Cherries are not applicable for a sorted report
    unset_cherries($arr);

    # Report "slices" should use absolute date range
    # because the LIMIT clause may not make sense in
    # the future
    $absolute_date = handle_absolute_date($date_fields);
    $qstring_arr['text_start_timestamp'] = $absolute_date;

    # Setup printf formats
    $top = DOCROOT;

    $a_format = "<a href='$self?%s' class='black_ln' target='_self'>%s</a>";
    $img_format = "<img src='$top/images/%s_arrow.gif' $size border='0'>";

    # ASC and DESC sort
    $directions = array('up', 'down');

    foreach ($headers as $header) {

        foreach ($directions as $direction) {
            $qstring_arr["orderby_$direction"] = $header;
            $qstring = arr2qstring($qstring_arr);
            $links[] = sprintf($a_format, $qstring, sprintf($img_format, $direction));
            unset($qstring_arr["orderby_$direction"]);
        }

        if ($default_label)
            $label = label($header);

        $ret[] = array_shift($links) .
                 $label .
                 array_shift($links);
    }

    if ($scalar_context)
        $ret = array_shift($ret);

    return $ret;
}

# If the param is not a ''large_field'', return the string with
# beginning/ending regexp match boundaries (param/value drilldown links on
# table cells should use this)
function exact_match($param, $str) {

    static $special_fields;
    if (! $special_fields)
        $special_fields = setup_large_fields();

    # A few fields are *highly*  unlikely to be searched 
    # for in the ''exact'' sense
    if (! preg_match("/" . join("|", $special_fields) . "/i", $param))
        return '^' . $str . '$';
    else
        return $str;
}

# Return number of rows in report
# (Needed becase if we have filtered by LIMIT, the PG
# resource will contain only LIMIT rows despite the same
# query minus the LIMIT clause returning more than LIMIT
# rows)
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

    $current = $date_fields["current"];
    $absolute = $date_fields["absolute"];

    # Strip off regexp for the report header
    if (preg_match('/^\^(.*)\$$/', $absolute, $m))
        $absolute = $m[1];

    $ret = "<table>" .
          "<tr><td><b>Current time (" . strtoupper(TIMEZONE) . ")</b>:<td>" . $current . 
          "<tr><td><b>Date range (" . strtoupper(TIMEZONE) . ")</b>: <td>" .  $absolute .
          "<tr><td><b>Phase(s)</b>:<td>" . en_join(array_map('label', $phases));

    if ($_GET["test_result"])
        $ret .= "<tr><td><b>Result</b>:<td>" . label(label($_GET["test_result"])) . " only";

    $ret .= "<tr><td><b>Number of rows</b>:<td>" . $num_rows .
            "</table>";

    return $ret;
}

#########################################

# Compose an SQL SELECT statement
function compose_sql($query) {

    $selects = array();
    $nl = "\n\t";

    # Setup a temporary TABLE/SEQUENCE 
    # NOTE: the above so-called temporary SQL relations are
    # NOT truly temporary, it is just that we do intend to
    # delete them after the user's session expires
    $new_ttable = $query['new_ttable'];
    $ttable     = $query['ttable'];
    $tseq       = $query['tseq'];

    # Handle ORDER BY
    if (isset($query['orderby_up']))
        $orderby = $query['orderby_up'];
    elseif (isset($query['orderby_down']))
        $orderby = $query['orderby_down'] . ' DESC';

    # Handle LIMIT + OFFSET
    $offset = offset($query);

    # Prepare default return statement
    $select_star = "SELECT * FROM $ttable %s;";
    $ret = sprintf($select_star, '');

    # Just select from the last ttable if we do not need to
    # prepare a new one
    if (! $new_ttable) {

        # We have already filtered by date range
        unset($query['where']['start_timestamp']);

        # Whack WHERE clause if the column is not
        # in the ttable
        foreach (array_keys($query['where']) as $column)
            if (! column_exists($column, $ttable))
                unset($query['where'][$column]);

        $where = array_values2($query['where']);

        if ($where)
            $criteria .= "\nWHERE " . join(" AND $nl", $where);

        if ($orderby)
            $criteria .= "\nORDER BY " . $orderby;

        if ($offset)
            $criteria .= "\nLIMIT " . LIMIT . " OFFSET $offset";

        $criteria .= ';';

        $ret = sprintf($select_star, $criteria);

        return $ret;
    }

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
    #
    # (NOTE: SELECTs MUST BE ORDERED LIKE SO FOR *_table FUNCTIONS)
    $selects = array_unique(
        array_merge(
            $query['select'],
            $aggregates,
            $query['select_more'],
            $query['performance']
        )
    );

    # Do not GROUP BY or ORDER BY row number
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

    $wheres = array_values2($query['where']);

    # Splice out orderby's old position, and place
    # it at the front of the ORDER BY clause
    if ($orderby) {
        for ($i = 0; $i < sizeof($orderbys); $i++) {
            if ($orderbys[$i] == $orderby) {
                array_splice($orderbys, $i, 1);
                break;
            }
        }
        array_unshift($orderbys, $orderby . $direction);
    }
    
    # Row numbering is always the hidden primary sort key
    $offset = offset($query);

    # Piece together all the clauses
    $cmd  = "\n SELECT " .
                "$nl" . join(",$nl", $selects);

    $cmd .= "\n INTO TABLE $ttable ";

    $cmd .= "\n FROM " .
                "$nl" . join(",$nl", $tables);

    if ($wheres) {
        $cmd .= "\n WHERE " .
                    "$nl" . join("$nl AND $nl", $wheres);
    }

    if (array_keys($query['select'])) {
        $cmd .= "\n GROUP BY " .
                    "$nl" . join(",$nl ", $groupbys);

        $cmd .= "\n ORDER BY " .
                    "$nl" . join(",$nl ", $orderbys) .
                    "$nl $direction";
    }
    if ($offset)
        $cmd .= "\n LIMIT " . LIMIT . " OFFSET $offset";

    $cmd .= ";";

    debug_sql($cmd, 1);
    do_pg_query($cmd);

    return $ret;
}

# Return the array values that are a depth of 
# 2 away from the argument passed
function array_values2($arr) {
    foreach (array_keys($arr) as $k)
        $ret[] = $arr[$k];

    return $ret;
}

# Return 1 if $column exists in $table
function column_exists($column, $table) {
    return select_scalar("SELECT 1 FROM information_schema.columns " .
                            "WHERE column_name = '$column' AND " .
                                "table_name = '$table'");

}

#########################################
#                                       
#  Input Processing Functions          
#                                     
# The following process_*_field(s) functions return arrays
# ready to be fed to compose_sql. The query array is
# structured more or less like an SQL SELECT statement:
#
# All SELECT items (including aggregates) are formatted as:
# [column alias] => {string functions|column alias}
#
# (type)
# (all)    $query['ttable']      => session DB table to select from
# (all)    $query['select']      => list of general SELECTs
# (all)    $query['aggregates']  => list of COUNT clauses for result counts
# (detail) $query['select_more'] => list of detail SELECT columns
# (detail) $query['performance'] => list of performance SELECT columns
# (all)    $query['where']       => list of WHERE clauses
# (all)    $query['limit']       => LIMIT value
# (all)    $query['offset']      => OFFSET value
# (all)    $query['orderby_*']   => primary sort for ORDER BY
#
#########################################

# Determine report type, Summary or Detail
#
# SHOULD THIS FUNCTION BE "PASS BY REFERENCE"?
function process_report_type($params) {

    $slice = $params['slice'];
    $go    = strtolower($_GET['go']);
    $click = strtolower($_GET['click']);

    # Report type is carried onward, not the button click event
    if ($click)
        $go = $click;

    # Determine report type, and
    # whether this is a "slice" report
    if (preg_match("/(summary|detail|performance|latency\w+)/i", $go, $m)) {
        $type = $m[1];

        if (! $slice) {
            unset($_GET['rows']);
            unset($_GET['offset']);
            unset($_GET['slice']);
        }
    }

    # Press 'Summary' for them if they traverse from a
    # detailed report into multi-phase mode
    $phases = process_phase_field($_GET);
    if ((sizeof($phases) > 1) and (! preg_match("/summary/i", $type))) {
        $type = 'summary';
    } 
    # Press 'Summary' for them if they go from a performance
    # report to a non-test_run radio button
    elseif (preg_match("/performance/i", $type) and $phases[0] != 'test_run') {
        $type = 'summary';
    }

    # Put the report type into the global env
    $_GET['go'] = $type;

    if (preg_match("/cherry/i", $go))
        $_GET['go'] = $go;

    return $type;
}

# 1. Generate WHERE clause pieces from user-entered textfields
# 2. Generate SELECT items from user-entered show/hide menus
function process_input_fields($params) {

    global $new_ttable;

    static $query;
    if ($query)
        return $query;

    $query['where'] = array();
    $query['select'] = array();

    # These fields will not be string searchable
    $special_fields = array_merge(
        array("timestamp", "phase"),

        # Handle these with process_large_fields()
        setup_large_fields()
    );

    foreach (array_keys($params) as $k) {

        if (preg_match("/" . join("|", $special_fields) . "/i", $k))
            continue;

        # If it's a textfield, tokenize it and add each
        # item to WHERE clause
        elseif (preg_match("/^text_/i", $k)) {
            $column = strip_prefix($k);

            $clauses = array();

            # No WHERE clause, if field is blank or "all"
            if (preg_match("/^\s*all\s*$|^\s*$/i", $params[$k]))
                continue;

            $str = $params[$k];

            # Use LIKE if there is a '%'
            if (strpos($str, '%') !== false)
                $clauses[] = "$column LIKE '$str'";

            # Exact match for '^...$'
            # (Optimize here, by doing a straight '='
            # comparison instead of using the regular
            # expression engine)
            elseif (preg_match('/^\^.*\$$/', $str))
                $clauses[] = "$column = '" . trim($str, '^$') . "'";

            # Otherwise, regular expression(s)
            else
                foreach (tokenize($params[$k]) as $str)
                    $clauses[] = "$column ~* '$str'";

            $query['where'][$column] = "(" . join(" OR ", $clauses) . ")";
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

    $nl = "\n\t\t";

    return $query;
}

# TEST_NAME IS AN ODDBALL FIELD. WE DO NOT ALLOW USERS
# TO HIDE IT IN DETAIL VIEW
function process_oddball_fields($params) {

    $go = get_go_or_click($_GET);
    $phase = array_shift(process_phase_field($_GET));

    if (preg_match("/detail/i", $go) and 
        $phase == 'test_run') {
        $_GET['show_test_name'] = 'show';
    }
}

# Arguments:
# 1. English filter (e.g., 'yesterday' or
#    'past x days')
# 2. Optional timestamp string description (e.g.,
#    "by second", "by hour", ...)
#
# Returns: 
#   - SQL date filter with string function
#   - Absolute time stamp
function process_date_field($params) {

    # Globalize the date range
    global $date_fields;

    $date = array();
    $tokens = array();

    $sep = '[\s\+]';
    $c = '/\s*;\s*/';
    $nl = "\n\t";

    # Remove the GMT offset from fetched string
    $format = "replace(date_trunc('second', %s), '+00', '')";

    # Grab global TIMEZONE constant
    $timezone = strtoupper(TIMEZONE);

    $now = select_scalar("SELECT " . sprintf($format, "now() AT TIME ZONE '$timezone'"));
    $date['current'] = $now;

    $timestamp_name      = "start_timestamp";
    $time_at_timezone    = "CAST($timestamp_name as TIMESTAMP WITH TIME ZONE) AT TIME ZONE '$timezone'";
    $timestamp_param     = $params["text_$timestamp_name"];

    # This will immediately put reporter.php in ''absolute date range'' mode
    $force_absolute_date = $params["force_absolute_date"];

    # Date-string functions
    $format2 = "\n substring($time_at_timezone from 0 for %d) || ':00 - ' || " .
               "\n substring($time_at_timezone + interval '1 %s' from 0 for %d)  || ':00' " .
               "\n   as $timestamp_name";
    $format3 = "\n substring($time_at_timezone from 0 for %d) || ' - ' || " .
               "\n substring($time_at_timezone + interval '1 %s' from 0 for %d) " .
               "\n   as $timestamp_name";
    $format4 = "\n $time_at_timezone " .
               "\n   as $timestamp_name";

    if (preg_match($c, $timestamp_param, $m))
        $tokens = tokenize($timestamp_param);
    else
        $tokens[] = $timestamp_param;

    foreach ($tokens as $token) {

        # Do date filtering
        if (! preg_match("/by /i", $token)) {

            # Yesterday
            if (preg_match("/yesterday/i", $token, $m)) {
                $operand = "'yesterday' AT TIME ZONE '$timezone'";
                $where = "$time_at_timezone > $operand";
                $absolute =
                    select_scalar("SELECT " . sprintf($format, $operand)) . " - $now";
            }
            # Today
            elseif (preg_match("/today/i", $token, $m)) {
                $operand = "'today' AT TIME ZONE '$timezone'";
                $where = "$time_at_timezone > $operand";
                $absolute =
                    select_scalar("SELECT " . sprintf($format, $operand)) . " - $now";
            }
            # Past x increments
            elseif (preg_match(
                        "/past$sep*" .
                        "(\w+)$sep*" .
                        "(\w+)/i", $token, $m)) {

                $operand = "now()  AT TIME ZONE '$timezone' - interval '" . strtonumeral($m[1]) . " $m[2]'";
                $where = "$time_at_timezone > $operand";
                $absolute =
                    select_scalar("SELECT " . sprintf($format, $operand)) . " - $now";
            }
            # Range (e.g., date1 - date2)
            elseif (preg_match("/(?:between)?" .
                                "(.*)" .
                                "(?:through|thru|and| - )" .
                                "(.*)/i", $token, $m)) {
                $where =
                    "$time_at_timezone > '$m[1]'" . " AND $nl" .
                    "$time_at_timezone < '$m[2]'";
                $absolute = "$m[1] - $m[2]";
            }
            # Exact date
            elseif (preg_match("/-|\//", $token)) {
                $where = "$time_at_timezone = '$token'";
                $absolute = $token;
            }
            # Nothing (used to prevent an SQL error on a
            # clean bring-up of reporter.php)
            else {
                $where = "$time_at_timezone = 'now()'";
            }
        }
        # Do date aggregation
        else {

            if (preg_match("/by(?:-| *)sec(?:onds?)?/i", $token)) {
                $clause = $format4;

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

    $type = strtolower(process_report_type($_GET));

    # Always show ''by second'' timestamps in Detail view
    if ($type == 'detail') {
        $clause = $format4;
        $date["rollup"] = 'by second';
    }

    # PROTECT AGAINST AN EMPTY DATE RANGE.
    # OUGHT TO PRINT A JAVASCRIPT ALERT AS WELL
    if (! $where) {
        $operand = "now() AT TIME ZONE '$timezone' - interval '24 hours'";
        $where = "$time_at_timezone > $operand";
        $absolute =
            select_scalar("SELECT " . sprintf($format, $operand)) . " - $now";
        $date['select'][$timestamp_name] = $timestamp_name;
    }

    $date['select'][$timestamp_name] = $clause;
    $date['where'][$timestamp_name] = $where;
    $date['absolute'] = $absolute;

    # Put reporter.php in absolute date range mode
    # (This is an option for cron/alerts.php)
    if ($force_absolute_date)
        $_GET["text_$timestamp_name"] = $absolute;

    # Globalize the date range
    $date_fields = $date;

    return $date;
}

# Return 
# 1. An array of SQL COUNT(CASE ...) clauses
#    which will be used to tally the result numbers
# 2. A result filter (optional)
# (Reference: postgresql.org/docs/7.3/static/functions-conditional.html)
function process_result_fields($phases, $params) {

    global $new_ttable;

    $test_result = $params['test_result'];

    $table = phase_results_table();

    $format = "COUNT(CASE WHEN %s THEN '%s' END) as %s";

    foreach (array_keys($table) as $phase) {
        foreach ($table[$phase] as $result) {
            if (array_search($phase, $phases) !== false) {

                # The result alias has gone from
                # pass|fail|... to _xx in the ttable
                if ($new_ttable)
                    $when[$result] = label($result) . " = '$result'";
                else
                    $when[$result] = "$result > 0";

                $results['aggregates'][$result] =
                    sprintf($format, $when[$result], $result, $result);
            }
        }
    }

    if ($test_result)
        $results['where'][$test_result] = $when[$test_result];

    return $results;
}

# Process OFFSET value for LIMIT clause
function process_offset_field($params) {
    $offset = $_GET['offset'];
    return array('offset' => $offset);
}

# This function always returns a 'ttable_id' for
# compose_sql, whether it is a new or recycled ttable
function process_ttable_id_field($params) {

    global $new_ttable;

    # Setup a temporary TABLE/SEQUENCE 
    # NOTE: the above so-called temporary SQL relations are
    # NOT truly temporary, it is just that we intend to DROP
    # them after the user's session expires
    $ttable_id = $params['ttable_id'];

    $tformat = "mtttemp_%s_table";
    $sformat = "mtttemp_%s_seq";

    $ttable = sprintf($tformat, $ttable_id);
    $tseq   = sprintf($sformat, $ttable_id);

    $use_ttable = use_ttable($params);

    # Do not use last session's ttable
    if (! $use_ttable) {

        # Out with the old ...
        do_pg_query("DELETE FROM ttable WHERE tname = '$ttable';", SILENT);
        do_pg_query("DROP TABLE $ttable;", SILENT);
        do_pg_query("DROP SEQUENCE $tseq;", SILENT);

        # ... in with the new
        list($ttable_id, $ttable, $tseq) = setup_ttable();

        # Setup ttable stuff for compose_sql
        $query['new_ttable'] = true;
        $new_ttable = true;
        $query['select']['n'] = "nextval('$tseq') as n";
    }
    # Use last session's ttable (update access time)
    else {

        $cmd = "SELECT 't' " .
               "FROM information_schema.tables " .
               "WHERE table_name = '$ttable';";

        $bool = select_scalar($cmd);

        # If the table is there, use it
        if ($bool) {

            do_pg_query("UPDATE ttable SET accessed = now() " . 
                        "WHERE tname = '$ttable';", SILENT);

            # This will result in a simple SELECT * FROM 
            # ttable [ limit | slice | drill | cherry ....]
            $query['new_ttable'] = false;
            $new_ttable = false;
            $query['select']['n'] = "n";

        # Otherwise, we need to rebuild the ttable
        } else {

            list($ttable_id, $ttable, $tseq) = setup_ttable($ttable_id);

            $query['new_ttable'] = true;
            $new_ttable = true;
            $query['select']['n'] = "nextval('$tseq') as n";
        }

    }

    $ttable = sprintf($tformat, $ttable_id);
    $query['ttable'] = $ttable;

    # Put ttable_id into the environment
    $_GET['ttable_id'] = $ttable_id;

    # Return ttable for compose_sql
    return $query;
}

# Process OFFSET value for LIMIT clause
function process_sort_field($params) {
    $orderbys = array(
        'orderby_up',
        'orderby_down',
    );
    foreach ($orderbys as $orderby) {
        $field = $_GET[$orderby];
        if (! is_null($field))
            return array($orderby => $field);
    }
}

# Generate WHERE clause for row numbers
function process_cherry_fields($params) {

    $go = $params['go'];

    # Cherries are only picked with the cherry button
    if (! preg_match("/cherry/i", $go))
        return null;

    # Compile all the cherry checkboxes and 
    # place them in an array (eliminating duplicates)
    foreach (array_keys($params) as $k) {
        if (preg_match("/cherry_(\d+)/i", $k, $m))
            $filter[] = $m[1];
    }

    if ($filter)
        return array_flip($filter);
}

# Generate WHERE and SELECT clause for ''trial'' boolean
function process_trial_field($trial) {

    if (! $trial) {
        $query['where']['trial'] = "(trial = 'f')";
    } else {
        $query['select']['trial'] = 'trial';
    }

    return $query;
}

# X: COULD USING THIS BE AN OPTIMZATION? OR IS
# IT USELESS?
#
# Return 'on' if all cherries are checked
# Return 'off' if all cherries are unchecked
# Return false if cherries are heterogeneous
# function is_homogenous($params) {
#     $on = 0;
#     $off = 0;
#     foreach (array_keys($params) as $k)
#         if (preg_match("/^cherry:/i", $k))
#             preg_match("/^on:/i", $params[$k]) ? $on++ : $off++;
# 
#     if (! $on)
#         return 'off';
#     elseif (! $off)
#         return 'on';
#     else
#         return false;
# }

# Read/create/update a cookie, and put its data into the
# environment
function process_cookie(&$params, &$cookie) {

    $remote_go = $params['remote_go'];
    $do_cookies = $params['do_cookies'];

    # Keep cookies around for 1 yr
    $days = 365;

    unset($params['remote_go']);
    unset($params['do_cookies']);

    $no_cookies = isset($params['no_cookies']) ? 1 : 0;

    # 'click' the button for them according to the report
    # type (which was exported from the Preferences window)
    if ($remote_go) {
        unset($params['go']);
        $params['click'] = $remote_go;
    }

    static $defaults;
    if (! $defaults)
        $defaults = setup_prefs();

    foreach (array_keys($defaults) as $category) {
        foreach (array_keys($defaults[$category]) as $p) {

            # Their browser has cookies disabled, or
            # they've been sent a link - use _GET
            if ($params[$p] != "") {
                define(strtoupper($p), param2constant($params[$p]));

                # Set the cookies, if asked to
                if ($do_cookies) {
                    setcookie("mtt_$p",
                              $params[$p],
                              time() + ($days * 24 * 60 * 60)
                    );
                }

            # Use the cookie
            } elseif ($cookie["mtt_$p"] and ! $no_cookies) {
                define(strtoupper($p), param2constant($cookie["mtt_$p"]));

            # None of the above, use the defaults
            } else {
                define(strtoupper($p), param2constant(prefs_default($p)));
            }
        }
    }
}

# Large fields are categorized as fields that often contain
# more than ~32 chars.  Return a list of fields that need to
# be ''substring-ed'' out in order to fit properly in a
# Summary table
function setup_large_fields() {

    static $ret;
    if ($ret)
        return $ret;

    $ret = array(
        'configure_arguments',
        'command',
        'result_message',
        'result_stdout',
        'result_stderr',
        'environment',
    );

    return $ret;
}

# Generate WHERE clause pieces from user-entered textfields
function process_large_fields($params) {

    static $query;
    if ($query)
        return $query;

    $type = strtolower(process_report_type($_GET));

    $fields = setup_large_fields();

    foreach ($fields as $field) {
        $value = $params["text_$field"];

        if ($value and $value != 'all') {

            $value = preg_replace("/;/", "|", $value);

            # In Summary view, use a string function to extract the match
            # for display in the table
            if ($type == 'summary' or 
                $type == 'performance') {
                $query['select'][$field] =
                    "substring($field from '$value') as $field";

            # In Detail view, display the entire field (with the matches highlighted)
            #
            # X: WE SHOULD PUT THE RETURN VALUES HERE THROUGH A PL/pgSQL FUNCTION OF 
            # SOME KIND TO DO THE HIGHLIGHTING THERE
            } else {
                $query['select_more'][$field] = $field;
            }

            $query['where'][$field] = "(" . "$field ~* '$value')";
        }
    }

    return $query;
}

# Convert a _GET param to a define() constant
function param2constant($str) {

    $str = strtolower(strip_star($str));

    static $map;
    if (! $map)
        $map = array(
            'on'  => true,
            'off' => false,

            # On the x-axis, linear scaling is actually
            # ''text'' scaling because we are setting the
            # tick labels manually (on the y-axis, linear
            # is linear)
            'linear'      => 'text',
            'logarithmic' => 'log',
        );

    if (isset($map[$str]))
        return $map[$str];
    else 
        return $str;
}

# Return the default value of preference named $pref
function prefs_default($pref) {

    # Compile the prefs hash
    static $prefs;
    if (! $prefs) {
        $_prefs = setup_prefs();
        foreach (array_keys($_prefs) as $cat)
            foreach (array_keys($_prefs[$cat]) as $p)
                $prefs[$p] = $_prefs[$cat][$p];
    }

    $value = array_shift($prefs[$pref]);

    if (is_bool($value) or is_scalar($value))
        $ret = $value;
    elseif (is_array($value)) {
        foreach ($value as $v)
            if (preg_match('/^\*/', $v))
                $ret = strip_star($v);
    
    }

    return $ret;
}

#########################################
#                                       
#  Column Processing
#                                     
#########################################

# Loop through column aliases, and return a
# left-to-right ordering of SELECT clauses
#
# X: CAN WE GRAB THIS ORDERING FROM A setup_*
# FUNCTION?
function order_columns($columns) {

    $layout = array(

        # row number
        'n'                   => 1,

        # trial
        'trial'               => 1,

        # results (left)
        'start_timestamp'     => 1,

        # submit
        'http_username'       => 1,
        'local_username'      => 1,
        'hostname'            => 1,
        'platform_name'       => 1,

        # compute_cluster
        'platform_hardware'   => 1,
        'platform_type'       => 1,
        'os_name'             => 1,
        'os_version'          => 1,

        # mpi_install
        'mpi_name'            => 1,
        'mpi_version'         => 1,
        'bitness'             => 1,
        'endian'              => 1,
        'vpath_mode'          => 1,
        'compiler_name'       => 1,
        'compiler_version'    => 1,
        'configure_arguments' => 1,

        # test_build
        'suite_name'          => 1,

        # test_run
        'test_name'           => 1,
        'np'                  => 1,
        'variant'             => 1,
        'command'             => 1,

        # results (right)
        'exit_value'          => 1,
        'exit_signal'         => 1,
        'duration'            => 1,
        'client_serial'       => 1,
        'result_message'      => 1,
        'result_stdout'       => 1,
        'result_stderr'       => 1,
        'environment'         => 1,

        # performance
        'message_size'        => 1,
        'bandwidth_min'       => 1,
        'bandwidth_max'       => 1,
        'bandwidth_avg'       => 1,
        'latency_min'         => 1,
        'latency_max'         => 1,
        'latency_avg'         => 1,
    );

    foreach (array_keys($layout) as $column)
        if (isset($columns[$column]))
            $ordering[$column] = $columns[$column];

    return $ordering;
}

# Add these to select statements for Detail reports
function setup_detail_fields($phase) {

    static $ret;
    if ($ret)
        return $ret;

    # MPI Install
    if ($phase == 'mpi_install')
        $phase_columns = array(
            'configure_arguments' => 'configure_arguments',
            'compiler_version'    => 'compiler_version',
            'vpath_mode'          => 'vpath_mode',
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
        'exit_value'      => 'exit_value',
        'exit_signal'     => 'exit_signal',
        'duration'        => 'duration',
        'result_message'  => 'result_message',
        'result_stdout'   => 'result_stdout',
        'result_stderr'   => 'result_stderr',
        'environment'     => 'environment',
        'client_serial'   => 'client_serial',
    );
    
    $ret =
        array('select_more' =>
            array_merge(
                $phase_columns,
                $results_columns
            )
        );

    # Whack fields set in this function that have already been filtered on
    $large_fields = process_large_fields($_GET);
    $input_fields = process_input_fields($_GET);

    $query = array_merge_recursive(
        $large_fields,
        $input_fields
    );

    foreach (array_keys($ret['select_more']) as $k)
        if (isset($query['where'][$k]))
            unset($ret['select_more'][$k]);

    return $ret;
}

# Return performance columns
function setup_performance_fields() {

    static $ret;
    if ($ret)
        return $ret;

    $ret =
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
    return $ret;
}

#########################################
#                                       
#  String & List Processing Functions
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

# PHP5 has this function built-in
function array_combine($keys, $values) {
    $arr = array();
    for ($i = 0; $i < sizeof($keys); $i++)
        $arr[$keys[$i]] = $values[$i];

    return $arr;
}

# Take keys and values and mutate hash
# like so: list[keys][values] = 1
function array_combine2(&$hash, $keys, $values) {
    for ($i = 0; $i < sizeof($values); $i++) {
        $hash[$keys[$i]][$values[$i]] = 1;
    }
}

# '%' -> '%%'
function esc_percent($str) {
    return preg_replace('/%/', '%%', $str);
}

#########################################
#                                       
#  Housekeeping
#                                     
#########################################

# Clean up expired session db TABLE/SEQUENCEs listed in $listing
function housekeeping_db($listing) {

    # Cherry-picking sessions expire
    # (Is 'accessed' more recent than '60 minutes ago'?)

    # no_cache option for developers
    if (isset($_GET['no_cache']))
        $cmd = "SELECT tname FROM $listing;";
    else
        $cmd = "SELECT tname FROM $listing WHERE accessed < now() - interval '60 minutes';";

    $tables = simple_select($cmd);

    foreach ($tables as $table) {
        $tseq = preg_replace('/_table$/', '_seq', $table);

        do_pg_query("DROP TABLE $table;", SILENT);
        do_pg_query("DROP SEQUENCE $tseq;", SILENT);
        do_pg_query("DELETE FROM $listing WHERE tname = '$table';", SILENT);
    }
}

# Clean up old image and csv files
function housekeeping($dir) {

    $res = opendir($dir);

    $root = dirname($_SERVER["SCRIPT_FILENAME"]);

    $file_types = array("\.gif$",
                       "\.jpg$",
                       "\.png$",
                       "\.jpeg$",
                       "\.pdf$",
                       "\.csv$");

    # Threshold to unlink a file
    $hours = 1;

    $now = time();

    # Loop through the files and delete any old ones
    while ($filename = readdir($res)) {

        # unlink needs a full path
        $filename = "$root/$dir/$filename";

        if (preg_match('/'.join('|', $file_types).'/i', $filename)) {
            $age = $now - fileatime($filename);
            if ($age > (60 * 60 * $hours))
                unlink($filename);
        }
    }
    closedir($res);
}

?>
