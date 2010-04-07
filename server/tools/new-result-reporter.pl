#!/usr/bin/env perl

################################################################################
#
# This script churns through a set of MTT results (limited by - as always -
# date range) and gathers pairs of similar tests which have undergone a result
# change.  It then outputs a static HTML page with HTML <A> pointers to these
# interesting result pairs for human inspection.
#
################################################################################

use DBI;
use DBD::Pg qw(:pg_types);
use Data::Dumper;
use Getopt::Long;
use Algorithm::Combinatorics qw(combinations);
use File::Basename;
use strict;

# 0-15 trace level
# DBI->trace(5);

# Grab the basename for the "temporary" TABLE, this way we'll always know what
# TABLEs this script created (lest, e.g., some never get dropped)
my $basename = basename($0);

# Use only legal TABLE name characters
$basename =~ s/([^a-zA-Z0-9])/_/g;

# The TEMPORARY TABLE doesn't seem to persist
# through a single invocation of this script, so 
# we'll create a non-TEMP TABLE, and drop at 
# at the end of the script
my $PID = $$;

# UNCOMMENT
my $start_timestamp_arg;
my $end_timestamp_arg;
my $where_clause_arg;
my $show_sql_arg;
my $no_execute_arg;
my $max_sql_time_arg;
my $show_preview_only_arg;
my $help_arg;

# REMOVE
$start_timestamp_arg = '2010-02-02 00:00:00';
$end_timestamp_arg = '2010-02-02 06:00:00';

# Begin time keeping
my $script_start_time = time();
my $sql_execution_time = 0;
my $sql_start_time;
my $sql_end_time;

# UNCOMMENT
# my $mtt_reporter_url = "http://www.open-mpi.org/mtt/index.php";
my $mtt_reporter_url = "http://www.open-mpi.org/~emallove/svn/mtt/trunk/server/php/index.php";

# Command-line options
&Getopt::Long::Configure("bundling");
my $ok = Getopt::Long::GetOptions(
    "start-timestamp|s=s" => \$start_timestamp_arg,
    "end-timestamp|e=s"   => \$end_timestamp_arg,
    "where-clause|w=s"    => \$where_clause_arg,
    "show-sql|q"          => \$show_sql_arg,
    "no-execute|n"        => \$no_execute_arg,
    "max-sql-time|m=s"    => \$max_sql_time_arg,
    "show-preview-only"   => \$show_preview_only_arg,
    "help|h"              => \$help_arg,
);

# Help menu
if ($help_arg) {
    print "
#############################################################################################
#
# new-result-reporter.pl is under construction.  Use at your own risk.
# 
#############################################################################################

$0 -
 --start-timestamp|s  Filter later than --start-timestamp (e.g., format: YYYY-MM-DD HH:MM:SS)
 --end-timestamp|e    Filter earlier than --end-timestamp (e.g., format: YYYY-MM-DD HH:MM:SS)
 --where-clause|w     Filter on extra WHERE SQL clause
 --show-sql|q         Display SQL queries
 --max-sql-time|m     Set a maximum amount of time to query the database server
 --show-preview-only  Preview the size of the tables and the number of SQL SELECTs
                      that will be run
 --help|h             This help menu
";
    exit;
}

# Connect to the MTT database
my $dbname = "mtt";
my $dbh = DBI->connect("DBI:Pg:dbname=$dbname", "mtt", "");

if (! defined($dbh)) {
    print "There was a problem connecting to the [$dbname] database:\n";
    print "\t$DBI::errstr\n";
    print "Exiting.\n";
    exit;
}

#
# MANDATORY ABSOLUTE DATES! 
# TODO: CONVERT RELATIVE DATE TO ABSOLUTE
#

# Phase->columns data
my $phases;

# Hardcoded column names (see server/sql/schemas-v3.sql)
$phases->{mpi_install}->{id} = "mpi_install_id";
$phases->{mpi_install}->{cols} =
    [
        "submit_id",
        "compute_cluster_id", 
        "mpi_get_id", 
        "mpi_install_compiler_id", 
        "mpi_install_configure_id", 
    ];

# UNCOMMENT
$phases->{test_build}->{id} = "test_build_id";
$phases->{test_build}->{cols} =
    [
        "submit_id",
        "compute_cluster_id",
        "mpi_install_compiler_id",
        "mpi_get_id",
        "mpi_install_configure_id",
        "mpi_install_id",
        "test_suite_id",
        "test_build_compiler_id",
    ];

# UNCOMMENT
$phases->{test_run}->{id} = "test_run_id";
$phases->{test_run}->{cols} =
    [
        "submit_id",
        "compute_cluster_id",
        "mpi_install_compiler_id",
        "mpi_get_id",
        "mpi_install_configure_id",
        "mpi_install_id",
        "test_suite_id",
        "test_build_compiler_id",
        "test_build_id",
        "test_name_id",
        "performance_id",
        "test_run_command_id",
        "np",
        "full_command",
    ];

# k values for the n choose k combinations operations for each phase.  We need
# to have these be different for each phase, otherwise we can end up doing
# waaaay too many queries. E.g., for test run, if we went down to 3 columns (14
# choose {14...3}), we would end up doing 16278 SELECTs!
my $k_values;
$k_values->{mpi_install} = 1;
$k_values->{test_build}  = 2;
$k_values->{test_run}    = 11;

# Pointer to row counts of SQL tables (for debugging)
my $table_row_counts;

my $test_result_field = "test_result";
my $column_ids_cat = "column_ids_cat";

# Variable for SQL query
my $q;

# Variable for row-by-row database records
my $array_ref;

# We are going to be doing a boatload of SELECTs, so 
# first populate a TEMPORARY TABLE to SELECT from
foreach my $phase (keys %$phases) {

    my $columns = $phases->{$phase}->{cols};

    # Compose SQL query
    $q = "
        SELECT
           $phases->{$phase}->{id},
           " . 
               join(",\n\t\t", @$columns) .
           ",
           $test_result_field
        INTO
            TEMPORARY TABLE ${basename}_${phase}
        FROM
            $phase
        WHERE
           (start_timestamp > '$start_timestamp_arg') AND
           (start_timestamp < '$end_timestamp_arg')
    ";

    $q .= "\n AND $where_clause_arg "
        if ($where_clause_arg);

    $q .= "\n;\n";

    # Display the SQL query
    print "\n<br>SQL: $q"
        if ($show_sql_arg);

    my $rc = $dbh->do($q);
    if (! defined($rc)) {
        print "There was a problem executing this query: $q\n";
        print "Exiting.\n";
        exit;
    }

    # DEBUG
    $q = "SELECT COUNT(*) FROM ${basename}_${phase};\n";
    $table_row_counts->{$phase} = simple_select($q);
}

# Keep track of ID pairs where a result change has occurred
my @flagged_for_result_change_arr;
my $flagged_for_result_change_hash;
my $joined_columns;
my $already_flagged;

# Print HTML header
&print_html_header();

# Go through all the "reportable" phases: MPI install, Test build, and Test run
foreach my $phase (keys %$phases) {

    # Get a set of all the column combinations
    my $column_combinations = _get_column_combinations($phases->{$phase}->{cols}, $k_values->{$phase});

    # --show-preview-only
    if ($show_preview_only_arg) {
        print "We will run " . (scalar @$column_combinations) . " SELECT queries on the $phase TABLE (which contains " . $table_row_counts->{$phase} . " rows).\n";
        next;
    }

    foreach my $columns (@$column_combinations) {

        # Mostly a debugging mechanism, to limit the amount of time 
        # we hammer the postmaster for development purposes
        if ($sql_execution_time > $max_sql_time_arg) {
            print "<br>The script has exceeded the maximum SQL time: $sql_execution_time.\n";
            print "<br>Moving on to the search for changed result values.\n";
            goto SEARCH_FOR_RESULT_CHANGES;
        }

        $joined_columns = join(" ", @$columns);

        # Compose SQL query
        $q = "
            SELECT
               $phases->{$phase}->{id},
               (" . 
                   join(" ||\n\t\t", @$columns) .
               ") as $column_ids_cat,
               $test_result_field
            FROM
                ${basename}_${phase}
";
        
        $q .= "
            ORDER BY
               $column_ids_cat ASC,
               $test_result_field ASC
        ;\n";

        # Display the SQL query
        print "\n<br>SQL: $q"
            if ($show_sql_arg);

        # Begin SQL time keeping
        my $sql_start_time = time();

        # Execute the SQL query
        $array_ref = $dbh->selectall_arrayref($q)
            if (! $no_execute_arg);

        # Tally SQL time keeping
        my $sql_end_time = time();
        $sql_execution_time += $sql_end_time - $sql_start_time;

        # Find similar test cases, with differing results
        my $size = scalar @$array_ref;
        my $i = 0;
        my $pair;
        for ($i = 0; $i < $size; $i++) {

            # If the data columns are identical, but the results differ
            # - we consider this noteworthy
            if (($array_ref->[$i][1] == $array_ref->[$i+1][1]) and 
                ($array_ref->[$i][2] != $array_ref->[$i+1][2])) {
                push(@flagged_for_result_change_arr, [$array_ref->[$i][0], $array_ref->[$i+1][0]]);

                $pair = join("|", sort ($array_ref->[$i][0], $array_ref->[$i+1][0]));
                if (! $already_flagged->{$phase}->{$pair}) {
                    push(@{$flagged_for_result_change_hash->{$phase}->{$joined_columns}}, $pair);

                    # Don't report the same pair in multiple categories of similar column groupings
                    $already_flagged->{$phase}->{$pair} = 1;
                }
            }
        }
    }
}

SEARCH_FOR_RESULT_CHANGES:

# Drop the "temporary" TABLEs
# my $s;
# foreach my $phase (keys %$flagged_for_result_change_hash) {
#     $s = "DROP TABLE ${basename}_${phase};";
#     $dbh->do($s) or warn $dbh->errstr;
# }

# HTML gray colors (taken from server/php/report.inc)
my $LGRAY     = "#C0C0C0";
my $LLGRAY    = "#DEDEDE";

my $colspan = 6;
foreach my $phase (keys %$flagged_for_result_change_hash) {

    # For td (red) background colors
    my $red_dec   = 0;
    my $green_dec = 0;
    my $blue_dec  = 0;
    my $red_hex   = "00";
    my $green_hex = "00";
    my $blue_hex  = "00";
    my $RED       = "#FF0000";

    print "\n<table border='1' width='60%'><tr><td colspan=$colspan bgcolor=$LGRAY>Phase: $phase\n";

    my $scalar_column_groups = scalar keys(%{$flagged_for_result_change_hash->{$phase}});
    my $redness_increment = sprintf("%d", 255 / $scalar_column_groups);

    foreach my $cols (sort _column_group_relevance_sort keys(%{$flagged_for_result_change_hash->{$phase}})) {

        print "\n\t<tr><td colspan=$colspan bgcolor=$LLGRAY>Matching columns: $cols\n";

        my $i = 0;
        foreach my $ids (@{$flagged_for_result_change_hash->{$phase}->{$cols}}) {

            if ($i++ % $colspan == 0) {
                print "\n\t<tr>"
            }
            
            # Provide a link to test results
            #
            # Note: the 'id1|id2' is an iffy regexp (e.g., there could be some
            # spurious matches), but it should work okay in this case, given an
            # appropriate date range
            #
            # TODO: SHORTEN THESE URLS!  THEY JACK UP THE SIZE
            # OF THE RESULTING HTML PAGE ENORMOUSLY.
            print "\n\t\t<td align=center bgcolor=$RED>" .
                "<a class='black_ln' href=\"" .
                "$mtt_reporter_url?" .
                "&phase=$phase" .
                "&show_platform_hardware=show" .
                "&show_os_name=show" .
                "&show_mpi_name=show" .
                "&show_mpi_version=show" .
                "&show_compiler_name=show" .
                "&show_bitness=show" .
                "&show_endian=show" .
                "&show_http_username=show" .
                "&show_platform_name=show" .
                "&click=Summary" .
                "&show_compiler_version=show" .
                "&show_vpath_mode=show" .
                "&show_exit_value=hide" .
                "&show_exit_signal=hide" .
                "&show_duration=hide" .
                "&show_client_serial=hide" .
                "&lastgo=summary" .
                "&text_${phase}_id=$ids" .
                "&text_start_timestamp=$start_timestamp_arg - $end_timestamp_arg" .
                "\">$ids</a>";
        }

        # As the results become less relevant, lighten the shade of red
        $red_hex   = "FF";
        $green_dec = $green_dec + $redness_increment;
        $green_hex = sprintf("%02X", $green_dec + $redness_increment);
        $blue_dec  = $blue_dec + $redness_increment;
        $blue_hex  = sprintf("%02X", $blue_dec + $redness_increment);
        $RED       = "#$red_hex$green_hex$blue_hex";
    }

    print "\n</table><br>";
}

# Finish time keeping
my $script_end_time = time();
my $script_execution_time = $script_end_time - $script_start_time;

# End of HTML page
print "
<br>Total script execution time: $script_execution_time second(s)
<br>Total SQL execution time: $sql_execution_time second(s)
</body>
</html>\n";

# Close the database connection
$dbh->disconnect();

# Exit the program
exit;

################################################################################
#
# Helper subroutines
#
################################################################################

# Return a list of all possible combinations
# using 1 through n elements
#   $l - list to perform combinatorics on
#   $t - n choose n, n choose n-1, ... n choose t
sub _get_column_combinations {
    my ($l, $t) = @_;
    my @ret;

    my $size = scalar @$l;

    while ($size >= $t) {
        push(@ret, combinations($l, $size));
        $size--;
    }
    return \@ret;
}

# Ewww.  We want to inspect the column groupings
# with the most columns, so we create this custom
# sorting callback routine.
sub _column_group_relevance_sort {
    my $a_count;
    my $b_count;
    my @x;

    @x = split(/\s+/, $a);
    $a_count = scalar @x;
    @x = split(/\s+/, $b);
    $b_count = scalar @x;

    return $b_count <=> $a_count;
}

sub simple_select {
    my ($q) = @_;
    my $r = $dbh->selectall_arrayref($q);
    my $x = shift @$r;
    my $ret = shift @$x;
    return $ret;
}

# Print HTML header
sub print_html_header {
    print "<html>
    <head>
        <style type='text/css'>

            a.black_ln:link    { color: #000000 } /* for unvisited links */
            a.black_ln:visited { color: #555555 } /* for visited links */
            a.black_ln:active  { color: #FFFFFF } /* when link is clicked */
            a.black_ln:hover   { color: #FFFF40 } /* when mouse is over link */

            a.lgray_ln:link    { color: #F8F8F8; font-size: 105%; text-decoration:none; }
            a.lgray_ln:visited { color: #F8F8F8; font-size: 105%; text-decoration:none; }
            a.lgray_ln:active  { color: #FFFFFF; font-size: 105%; text-decoration:none; }
            a.lgray_ln:hover   { color: #FFFF40; font-size: 105%; text-decoration:none; }

            td { font-size: 75%; } 
            p  { font-size: 75%; } 
            th { font-size: 80%; } 
            th#result { font-size: 55%; } 
            img#result { width: 55%; height: 55%; } 

        </style> 
    </head>
    <body>\n";

    print "
        <title>MTT result changes: $start_timestamp_arg - $end_timestamp_arg</title>

        <table>
            <tr><td><font size='2'>MTT result changes
            <tr><td><font size='2'>Date range: $start_timestamp_arg - $end_timestamp_arg
            <tr><td><font size='2'>SQL WHERE clause: $where_clause_arg
            <tr><td><font size='2'>SQL execution time limit: $max_sql_time_arg seconds
        </table>
        <br>
    ";
}
