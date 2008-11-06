#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2008 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Reporter::TextFile;

use strict;
use POSIX qw(strftime);
use MTT::Messages;
use MTT::Values;
use MTT::Files;
use MTT::Version;
use MTT::Mail;
use MTT::DoCommand;
use Data::Dumper;
use File::Basename;
use Text::Wrap;

# directory and file to write to
my $dirname;
my $filename;

# files we've written to already in this run
my $written_files;

# global array of all the MTT results
my @results;

# user specified headers and footers
my $summary_header;
my $summary_footer;
my $detail_header;
my $detail_footer;

# wordwrap pref for reports
my $textwrap;

# global ini variables
my ($ini, $section);


# send summary by email if requested
my $to;

# Do we have Text::TabularDisplay?
my $have_tabulardisplay;
eval "\$have_tabulardisplay = require Text::TabularDisplay";

#--------------------------------------------------------------------------

sub Init {
    ($ini, $section) = @_;

    # Sanity check
    if (!$have_tabulardisplay) {
        Error("Summary table requested via the TextFile reporter, but the perl module Text::TabularDisplay cannot be found/loaded.  Please install Text::TabularDisplay and try again.\n");
    }

    # Grab TextFile INI params

    $summary_header = Value($ini, $section, "textfile_summary_header") . "\n"; 
    $summary_footer = Value($ini, $section, "textfile_summary_footer") . "\n"; 
    $detail_header  = Value($ini, $section, "textfile_detail_header ") . "\n"; 
    $detail_footer  = Value($ini, $section, "textfile_detail_footer ") . "\n"; 
    $textwrap       = Value($ini, $section, "textfile_textwrap"); 
    $filename       = Value($ini, $section, "textfile_filename"); 
    $dirname        = Value($ini, $section, "textfile_dirname"); 

    # Make it an absolute filename, because there's oodles of
    # chdir()'s within the testing.  Whack the file if it's already
    # there.

    if ($filename ne "-") {
        if ($filename !~ /\//) {
            $dirname = MTT::DoCommand::cwd();
            $filename = "$filename";
        } else {
            $dirname = dirname($filename) if (! defined($dirname));
            $filename = basename($filename);
        }

        # Make sure we have a directory to write to
        MTT::Files::safe_mkdir($dirname);

        Debug("File reporter initialized ($dirname/$filename)\n");
    } else {
        Debug("File reporter initialized (<stdout>)\n");
    }


    # Initialize nail notification for summary 

    $to = Value($ini, $section, "email_to");
    if ($to) {
        # Setup the mailer
        my $agent = Value($ini, $section, "email_agent");
        if (!MTT::Mail::Init($agent)) {
            Debug("Failed to setup TextFileEmail reporter\n");
            return 0;
        }

        Debug("TextFileEmail reporter initialized ($to)\n");
    }




    return 1;
}

#--------------------------------------------------------------------------

sub Finalize {

    # Print a roll-up report
    _summary_report(\@results)
        if (@results);

    undef $dirname;
    undef $filename;
    undef $written_files;
}

#--------------------------------------------------------------------------

sub Submit {
    my ($info, $entries) = @_;

    Debug("File reporter\n");

    # Push entries into the global results array
    push(@results, $entries);

    # TextFile output has its own columns-width
    my $save_columns = $Text::Wrap::columns;
    $Text::Wrap::columns = $textwrap;

    # Do a detail report
    _detail_report($info, $entries);

    $Text::Wrap::columns = $save_columns;
}

# Show counts of section results
sub _summary_report {
    my $results_arr = shift;

    print("\nMTT Results Summary\n");

    print $summary_header;

    my $table = Text::TabularDisplay->new(("Phase","Section","MPI Version", "Duration","Pass","Fail","Time out","Skip","Detailed report"));
    my ($total_fail, $total_succ, $total_duration, $html_table_content) = (0,0,0,"");

    foreach my $results (@$results_arr) {

        foreach my $phase (keys %$results) {
            my $phase_obj = $results->{$phase};

            foreach my $section (keys %{$phase_obj}) {
                my $section_obj = $results->{$phase}{$section};
                my ($per_mpiver) = ();

                foreach my $results_hash (@$section_obj) {

                    my $mpi_version = $results_hash->{mpi_version};
                    if ($results_hash->{test_result} eq MTT::Values::PASS) {
                        $per_mpiver->{$mpi_version}{pass}++;
                        $total_succ++;
                    } elsif ($results_hash->{test_result} eq MTT::Values::FAIL) {
                        $per_mpiver->{$mpi_version}{fail}++;
                        $total_fail++;
                    } elsif ($results_hash->{test_result} eq MTT::Values::TIMED_OUT) {
                        $per_mpiver->{$mpi_version}{timed}++;
                        $total_fail++;
                    } elsif ($results_hash->{test_result} eq MTT::Values::SKIPPED) {
                        $per_mpiver->{$mpi_version}{skipped}++;
                    }
                    if ( defined($results_hash->{duration}) ) {
                        my $one_test_duration = $results_hash->{duration};
                        $one_test_duration =~ s/(\d+).+/$1/g;
                        $per_mpiver->{$mpi_version}{duration} += $one_test_duration;
                        $total_duration += $one_test_duration;
                    }
                    $per_mpiver->{$mpi_version}{report} = $results_hash;
                }

                foreach my $mpi_version (keys %{$per_mpiver}) {
                    my $mpi_stat        = $per_mpiver->{$mpi_version};
                    my $report          = $mpi_stat->{report};
                    my $rep_file        = basename(_get_filename($report, $section));

                    my $duration_human  = _convert_duration($mpi_stat->{duration});
                    $table->add($phase, $section, $mpi_version, $duration_human, $mpi_stat->{pass}, $mpi_stat->{fail}, 
                        $mpi_stat->{timed}, $mpi_stat->{skipped}, $rep_file);
                    $html_table_content .= add_tr($phase, $section, $mpi_version, $duration_human, $mpi_stat->{pass}, $mpi_stat->{fail},
                        $mpi_stat->{timed}, $mpi_stat->{skipped}, $rep_file);
                }
            }
        }
    }

    my $total_tests =  $total_fail + $total_succ;
    my $total_duration_human = _convert_duration($total_duration);
    my $perf_stat = "

    Total Tests:    $total_tests
    Total Failures: $total_fail
    Total Passed:   $total_succ
    Total Duration: $total_duration secs. ($total_duration_human)

    ";
    print $table->render . "\n" . $perf_stat . $summary_footer;

    # Write the Summary report to a file
    my $filename = "All_phase-summary.txt";
    my $file = "$dirname/" . MTT::Files::make_safe_filename("$filename");

    my $body = join("\n", ($summary_header, $table->render, $perf_stat, $summary_footer));

    print $body;
    _output_results($file, $body);


    # Wrte html report to a file
    my $html_body = get_html_template();
    $html_body =~ s/%TESTS_RESULTS%/$html_table_content/g;
    my $html_totals = "<td>$total_tests</td><td>$total_fail</td><td>$total_succ</td><td>$total_duration_human</td>\n";
    $html_body =~ s/%TOTALS%/$html_totals/g;

    my $html_filename = "All_phase-summary.html";
    my $html_file = "$dirname/" . MTT::Files::make_safe_filename("$html_filename");

    _output_results($html_file, $html_body);


    if ( $to ) {
        # Evaluate the email subject header and from
        my ($subject, $body_footer);
        my $subject_tmpl = Value($ini, $section, "email_subject");
        my $body_footer_tmpl = Value($ini, $section, "email_footer");
        my $from = Value($ini, $section, "email_from");

        my $overall_mtt_status = "success";
        if ( $total_fail > 0 ) {
            $overall_mtt_status = "failed";
        }
        my $str = "\$body_footer = \"$body_footer_tmpl\"";
        eval $str;

        my $str = "\$subject = \"$subject_tmpl\"";
        eval $str;
        Verbose(">> Subject: $subject\n");

        # Now send it
        MTT::Mail::Send($subject, $to, $from, $body . $body_footer);
        Verbose(">> Reported to e-mail: $to\n");
    }
    return 1;
}

# Show individual test outputs
sub _detail_report {
    my ($info, $entries) = @_;

    my $file;

    my $table = Text::TabularDisplay->new(("Field", "Value"));

    my $separator = { " " => " " };

    foreach my $phase (keys(%$entries)) {
        my $phase_obj = $entries->{$phase};

        foreach my $section (keys(%$phase_obj)) {
            my $section_obj = $phase_obj->{$section};
            my $multi_line;

            # Put fields that are identical all the way through in 
            # the title
            my $title = _get_replicated_fields($section_obj);

            # Make timestamps human-readable
            $title = _convert_timestamps($title);

            $table = _add_to_table($table, $title, undef);
            $table = _add_to_table($table, $separator, undef);

            foreach my $report (@$section_obj) {

                $file   = _get_filename($report, $section);

                $report = _convert_timestamps($report);

                $table = _add_to_table($table, $report, $title);
                $table = _add_to_table($table, $separator, undef);
            }

            # Write the report to a file (or stdout)
            _output_results($file,
                join("\n", ($detail_header, 
                            $table->render,
                            $detail_footer)));
        }
    }
}

# Return a list of field-value pairs to put in the title
# (to avoid print them over and over for each result)
sub _get_replicated_fields {
    my ($section_obj) = @_;

    my $title;

    # Iterate through the array of hashes (each one is an
    # individual test result)
    foreach my $results_hash (@$section_obj) {
        foreach my $key (keys %$results_hash) {
            $title->{$key}->{$results_hash->{$key}} = 1;
        }
    }

    my @to_be_removed;

    # Stick runs of identical keys into the title
    foreach my $key (keys %$title) {
        my @keys = keys %{$title->{$key}};

        if (scalar @keys > 1) {
            push(@to_be_removed, $key);
        } else {
            $title->{$key} = shift @keys;
        }
    }

    # Delete the remaining keys to be printed in _detail_report
    foreach my $key (@to_be_removed) {
        delete $title->{$key};
    }

    return $title;
}

# Add rows to the TabularDisplay object
# (exclude_hash items will not be added)
sub _add_to_table {
    my($table, $include_hash, $exclude_hash) = @_;

    # Skip over database fields that will have
    # *no* meaning to the MTT operator
    my @frivolous = (
        "mpi_install_id",
        "test_build_id",
        "test_result",
    );
    my $frivolous = join("|", @frivolous);

    foreach my $key (sort keys %$include_hash) {

        # Skip over frivolous data
        next if ($key =~ /$frivolous/);

        if (! defined($exclude_hash->{$key})) {
            $table->add($key, wrap('', '', $include_hash->{$key}));
        }
    }

    return $table;
}

# Output results to a file or 
sub _output_results {
    my ($file, $str) = @_;

    Debug("Writing to text file: $file\n");

    # If we have not yet written to the file in this run,
    # then whack the file.

    if (!exists($written_files->{$file})) {
        unlink($file);
    }

    # Write to stdout or append to the file

    if ($file eq "-") {
        print $str;
        Verbose(">> Reported to stdout\n")
            if (!exists($written_files->{$file}));
    } else {
        MTT::Files::SafeWrite(1, $file, $str, ">>");
        Verbose(">> Reported to text file $file\n")
            if (!exists($written_files->{$file}));
    }
    $written_files->{$file} = 1;
}

sub _get_filename {
    my ($report, $section) = @_;

    # Substitute in the filename
    my $date = strftime("%m%d%Y", localtime);
    my $time = strftime("%H%M%S", localtime);
    my $mpi_name = $report->{mpi_name};
    my $mpi_version = $report->{mpi_version};
    my $phase = $report->{phase};
    my $ret;

    # Hardcoded filename
    my $basename = MTT::Files::make_safe_filename("$phase-$section-$mpi_name-$mpi_version.txt");

    # Use an absolute path
    $ret = "$dirname/$basename"; 

    Debug("_get_filename returning $ret\n");
    return $ret;
}

# Make timestamps human-readable
sub _convert_timestamps {
    my $report = shift;

    foreach my $key (keys(%$report)) {
        if ($key =~ /timestamp/ && $report->{$key} =~ /\d+/) {
            $report->{$key} = gmtime($report->{$key});
        }
    }

    return $report;
}

# convert duration in secs to human-readable dd HH:MM:SS
sub _convert_duration
{
    use integer;
    my ($rtime)= @_;

    my $min   = $rtime / 60;
    my $sec   = $rtime % 60;
    my $hour  = $min   / 60;
    my $min   = $min   % 60;
    my $day   = $hour  / 24;
    my $hour  = $hour  % 24;
    my @times;

    if ($day) {
        @times = ($day, $hour, $min, $sec);
    } elsif ($hour) {
        @times = ($hour, $min, $sec);
    } else {
        @times = ($min, $sec);
    }

    my $res = join(':', @times);
    $res =~ s/\b(\d)\b/0$1/g;
    return $res;
}

sub add_tr
{
    my ($phase, $section, $mpi_version, $duration_human, $pass, $fail, $timed, $skipped, $rep_file_url) = @_;
    my $trClass = "Passed";
    if ($fail or $timed) {
        $trClass = "Error";
    } 

    my $tr = "<tr valign='top' class='$trClass'>\n";
    $tr .= "<td><a href='$rep_file_url'>$phase</a></td><td>$section</td><td>$mpi_version</td><td>$duration_human</td><td>$pass</td><td>$fail</td><td>$timed</td><td>$skipped</td>\n</tr>\n";

    return $tr;
}

sub get_html_template
{
    my $tmpl = '
    <html xmlns:lxslt="http://xml.apache.org/xslt" xmlns:stringutils="xalan://org.apache.tools.ant.util.StringUtils">
    <META http-equiv="Content-Type" content="text/html; charset=US-ASCII">
    <head>
    <style type="text/css" media=screen>
    body {
    font:normal 68% verdana,arial,helvetica;
    color:#000000;
    }
    table tr td, table tr th {
    font-size: 68%;
    }
    table.details tr th{
    font-weight: bold;
    text-align:left;
    background:#a6caf0;
    }
    table.details tr td{
    background:#eeeee0;
    }
    p {
    line-height:1.5em;
    margin-top:0.5em; margin-bottom:1.0em;
    }
    h1 {
    margin: 0px 0px 5px; font: 165% verdana,arial,helvetica
    }
    h2 {
    margin-top: 1em; margin-bottom: 0.5em; font: bold 125% verdana,arial,helvetica
    }
    h3 {
    margin-bottom: 0.5em; font: bold 115% verdana,arial,helvetica
    }
    h4 {
    margin-bottom: 0.5em; font: bold 100% verdana,arial,helvetica
    }
    h5 {
    margin-bottom: 0.5em; font: bold 100% verdana,arial,helvetica
    }
    h6 {
    margin-bottom: 0.5em; font: bold 100% verdana,arial,helvetica
    }
    .Error {
    font-weight:bold; color:red;
    }
    .Failure {
    font-weight:bold; color:purple;
    }
    .Properties {
    text-align:right;
    }
    </style>
    </head>
    <title>MTT Results: Summary</title>
    <h1>MTT Results</h1>
    <hr size="1">
    <h2>Summary</h2>
    <table class="details" border="0" cellpadding="5" cellspacing="2" width="95%">
    <tr valign="top">
    <th>Phase</th><th>Section</th><th>MPI Version</th><th>Duration</th><th>Pass</th><th>Fail</th><th>Time Out</th><th>Skip</th>
    </tr>
    %TESTS_RESULTS%
    </table>
    <h2>Totals</h2>
    <table class="details" border="0" cellpadding="5" cellspacing="2" width="95%">
    <tr valign="top">
    <th>Tests</th><th>Failed</th><th>Passed</th><th nowrap>Duration</th>
    </tr>
    <tr valign="top" class="Pass">
    %TOTALS%
    </tr>
    </table>

    </body>
    </html>
    ';
    return $tmpl;
}



1;
