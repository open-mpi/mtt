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

package MTT::Reporter::HTMLReport;

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
use File::Temp;
use Text::Wrap;
use File::Copy;
use IO::File;
use MTT::INI;

# directory and file to write to
my $dirname;
my $filename;

# files we've written to already in this run
my $written_files;

# global array of all the MTT results
my @results;

# user specified headers and footers
my $header;
my $footer;

# wordwrap pref for reports

# global ini variables
my ($ini, $section);


# send summary by email if requested
my $to;

my $domain;

#--------------------------------------------------------------------------

sub Init 
{
    ($ini, $section) = @_;

    $header = Value($ini, $section, "header") . "\n"; 
    $footer = Value($ini, $section, "footer") . "\n"; 
    $filename       = Value($ini, $section, "textfile_filename"); 
    $dirname        = Value($ini, $section, "textfile_dirname"); 
	$domain         = Value($ini, "mtt", "web_url");
	if(!defined($domain))
	{
		$domain  = Value($ini, $section, "web_url");
	}

    # Make it an absolute filename, because there's oodles of
    # chdir()'s within the testing.  Whack the file if it's already
    # there.

    if ($filename ne "-") 
	{
        if ($filename !~ /\//) 
		{
            $dirname = MTT::DoCommand::cwd();
            $filename = "$filename";
        } else 
		{
            $dirname = dirname($filename) if (! defined($dirname));
            $filename = basename($filename);
        }

        MTT::Files::safe_mkdir($dirname);
        MTT::Files::safe_mkdir("$dirname/html");

        Debug("File reporter initialized ($dirname/$filename)\n");
    } else 
	{
        Debug("File reporter initialized (<stdout>)\n");
    }

    $to = Value($ini, $section, "email_to");
    if ($to) 
	{
        my $agent = Value($ini, $section, "email_agent");
        if (!MTT::Mail::Init($agent)) 
		{
            Debug("Failed to setup TextFileEmail reporter\n");
            return 0;
        }

        Debug("TextFileEmail reporter initialized ($to)\n");
    }
    return 1;
}
#--------------------------------------------------------------------------

sub Finalize 
{
	my $flush_mode = undef;
	if ($MTT::Globals::Values->{save_intermediate_report})
	{
		$flush_mode = "finalize";
	}
    # Print a roll-up report
    _summary_report(\@results, $flush_mode)
        if (@results);
	undef $dirname;
	undef $filename;
	undef $written_files;
}

#--------------------------------------------------------------------------

sub Flush
{
	my ($info, $entries) = @_;
	my @results_to_flush = @results;
	push(@results_to_flush, $entries) if $entries;
	_summary_report(\@results_to_flush, "yes")
        if (@results_to_flush);	
        
    _detail_report($info, $entries, "yes");
}

#--------------------------------------------------------------------------

sub Submit 
{
    my ($info, $entries) = @_;
    Debug("File reporter\n");

    push(@results, $entries);

	if ($MTT::Globals::Values->{save_intermediate_report})
	{
		return;
	}

    # Do a detail report
    _detail_report($info, $entries);
}


#--------------------------------------------------------------------------

sub _summary_report 
{
    my $results_arr = shift;
	my $flush_mode = shift;

#	if (!$flush_mode || $flush_mode eq "finalize")
#	{
#    	print("\nMTT Results Summary" . $MTT::Globals::Values->{description} . ", started at: " . $MTT::Globals::Values->{start_time} . " report generated at: " . localtime() . "\n");
#	    print $header;
#    }
    my ($total_fail, $total_succ, $total_duration, $html_table_content) = (0,0,0,"");
    foreach my $results (@$results_arr) 
	{
        foreach my $phase (keys %$results) 
		{
            my $phase_obj = $results->{$phase};

            foreach my $section (keys %{$phase_obj}) 
			{
                my $section_obj = $results->{$phase}{$section};
                my ($per_mpiver) = ();

                foreach my $results_hash (@$section_obj) 
				{

                    my $mpi_version = $results_hash->{mpi_version};
                    if ($results_hash->{test_result} eq MTT::Values::PASS) 
					{
                        $per_mpiver->{$mpi_version}{pass}++;
                        $total_succ++;
                    }
					elsif ($results_hash->{test_result} eq MTT::Values::FAIL) 
					{
                        $per_mpiver->{$mpi_version}{fail}++;
                        $total_fail++;
                    } elsif ($results_hash->{test_result} eq MTT::Values::TIMED_OUT) 
					{
                        $per_mpiver->{$mpi_version}{timed}++;
                        $total_fail++;
                    } elsif ($results_hash->{test_result} eq MTT::Values::SKIPPED) 
					{
                        $per_mpiver->{$mpi_version}{skipped}++;
                    }
                    if ( defined($results_hash->{duration}) ) 
					{
                        my $one_test_duration = $results_hash->{duration};
                        $one_test_duration =~ s/(\d+).+/$1/g;
                        $per_mpiver->{$mpi_version}{duration} += $one_test_duration;
                        $total_duration += $one_test_duration;
                    }
                    $per_mpiver->{$mpi_version}{report} = $results_hash;
                }

                foreach my $mpi_version (keys %{$per_mpiver}) 
				{
                    my $mpi_stat        = $per_mpiver->{$mpi_version};
                    my $report          = $mpi_stat->{report};
                    my $rep_file        = basename(_get_filename($report, $section));
                    $rep_file           =~ s/\.txt/\.html/g;

                    my $duration_human  = _convert_duration($mpi_stat->{duration});
                    $html_table_content .= add_tr($phase, $section, $mpi_version, $duration_human, $mpi_stat->{pass}, $mpi_stat->{fail},
                        $mpi_stat->{timed}, $mpi_stat->{skipped}, $rep_file, $dirname);
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

    # Wrte html report to a file
    my $html_body = get_html_summary_report_template();
    $html_body =~ s/%TESTS_RESULTS%/$html_table_content/g;
    $html_body =~ s/%FOOTER%/$footer/g;
    $html_body =~ s/%HEADER%/$header/g;
    my $html_totals = "<td style=\"background:#eeeee0;\"  >$total_tests</td><td style=\"background:#eeeee0;\"  >$total_fail</td><td style=\"background:#eeeee0;\"  >$total_succ</td><td style=\"background:#eeeee0;\"  >$total_duration_human</td>\n";
    $html_body =~ s/%TOTALS%/$html_totals/g;
    my $html_filename = "All_phase-summary.html";
    my $html_file = "$dirname/" . MTT::Files::make_safe_filename("$html_filename");
    
	_output_results($html_file, $html_body,$flush_mode);

	if (!$flush_mode || $flush_mode eq "finalize")
	{
	    if ( $to ) 
		{
	        # Evaluate the email subject header and from
			my ($subject, $body_footer);
	        my $subject_tmpl = Value($ini, $section, "email_subject");
	        my $body_footer_tmpl = Value($ini, $section, "email_footer");
	        if ($MTT::Globals::Values->{extra_subject})
			{
	        	$subject_tmpl = $subject_tmpl."$MTT::Globals::Values->{extra_subject}";
	        }

            if ($MTT::Globals::Values->{extra_footer})
			{
                $body_footer_tmpl = $body_footer_tmpl."\n\n$MTT::Globals::Values->{extra_footer}";
            }
	        my $from = Value($ini, $section, "email_from");
	        my $detailed_report = Logical($ini, $section, "email_detailed_report");
	
	        my $overall_mtt_status = "success";
	        if ( $total_fail > 0 ) 
			{
	            $overall_mtt_status = "failed";
	        }
	        my $str = "\$body_footer = \"$body_footer_tmpl\"";
	        eval $str;
	
			my $str = "\$subject = \"$subject_tmpl\"";
			eval $str;

            $subject =~ s/[\n\r]//g;
			Verbose(">> Subject: $subject\n");
			Verbose(">> To: $to\n");
			Verbose(">> Body: $html_body\n");

            # todo: Use Mail.pm, need to fix it first to accept "type"
			open MAIL, "|mutt -e \"set content_type=text/html\"  -s \"$subject\" --  $to" || die "Could not open pipe to output e-mail\n";
			print MAIL $html_body;
			close MAIL;


			#}
	
	        Verbose(">> Reported to e-mail: $to\n");
	    }
	}
    return 1;
}

sub is_result_failed
{
    my ($key) = @_;
    my $failed = 0;
    if (($key ne "Success") and ($key ne "Passed") and ($key ne "Skipped")) 
	{
        $failed = 1;
    }
    $failed;
}

sub _bystatus
{
    my $key1 = $$a{result_message};
    my $key2 = $$b{result_message};
    is_result_failed($key2) <=> is_result_failed($key1);
}

# Show individual test outputs
sub _detail_report 
{
    my ($info, $entries, $flush_mode) = @_;
    my $file;

    my $separator = { " " => " " };
    my %existing_report_file = ();

    foreach my $phase (keys(%$entries)) 
	{
        my $phase_obj = $entries->{$phase};

        foreach my $section (keys(%$phase_obj)) 
		{
            my $section_obj = $phase_obj->{$section};
            my $multi_line;
            my $html_table = "";

            # Put fields that are identical all the way through in 
            # the title
            my $title = _get_replicated_fields($section_obj);

            # Make timestamps human-readable
           	$title = _convert_timestamps($title);

			_add_to_tables(\$html_table, $title, undef);

            foreach my $report (sort _bystatus @$section_obj) 
			{
				$file   = _get_filename($report, $section);
				$report = _convert_timestamps($report);
				$report = _convert_array_refs($report);
				_add_to_tables(\$html_table, $report, $title);
            }

            # Write the report to a file (or stdout)
            my $html_file = $file;
            $html_file    =~  s/\.txt/\.html/g;

            my $html_body = "";
            if (not defined $existing_report_file{$html_file}) 
			{
                $existing_report_file{$html_file} = 1;
                my $html_start = get_html_phase_report_template_start();
                Verbose(">> html: adding css $html_file\n");
                $html_body = $html_start;
            } else 
			{
                Verbose(">> html: not adding report css, already exists: $html_file\n");
            }
            $html_body .= $html_table;
 
           	_output_results($html_file, $html_body, $flush_mode);

        }
        foreach my $rep_file (keys %existing_report_file) 
		{
            my $close_report_html = get_html_phase_report_template_stop();
            	_output_results($rep_file, $close_report_html);
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
    foreach my $results_hash (@$section_obj) 
	{
        foreach my $key (keys %$results_hash) 
		{
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
sub _add_to_tables 
{
    my($htable_ref, $include_hash, $exclude_hash) = @_;

    # Skip over database fields that will have
    # *no* meaning to the MTT operator
    my @frivolous = (
        "mpi_install_id",
        "test_build_id",
        "test_result",
        "saved_to",
    );
    my $frivolous = join("|", @frivolous);

    # it can absent, if test did not start from some reason (wrong path to already installed mpi)
    my $strClass = "Passed";
    if ( !$include_hash->{"result_message"} and !$include_hash->{"test_result"}) {
        $strClass = "Error";
    } elsif ( ($include_hash->{"result_message"} ne "Success") and 
        ($include_hash->{"result_message"} ne "Passed") and 
        ($include_hash->{"result_message"} ne "Skipped")) {
        $strClass = "Error";
    }

    my $has_result = 0;
    foreach my $key (sort keys %$include_hash) {
        # Skip over frivolous data
        next if ($key =~ /$frivolous/);

        if (! defined($exclude_hash->{$key})) 
		{
            if (defined $htable_ref) 
			{
                if (!$has_result ) 
				{
                    $$htable_ref .= get_html_phase_report_table_start_template();
                    $has_result++;
                }

                my $val = $include_hash->{$key};

                # can be too big, browser hangs, save it as a href
                if ($key eq "result_stdout") {
                	if (!$MTT::Globals::Values->{save_intermediate_report})
					{
                		$include_hash->{saved_to}=undef;
                	}
                	if (!$include_hash->{saved_to})
					{
						my $tmp = new File::Temp(UNLINK => 0, SUFFIX => '.txt', TEMPLATE=>'test_stdout_XXXXXX', DIR=>"$dirname/html");
						my $fname = $tmp->filename;
						close $tmp;
						_output_results($fname, $val);
						$include_hash->{saved_to} = $fname;
                	}
                	 my $fname_base = basename($include_hash->{saved_to});
                	$$htable_ref .= "<tr valign='top' class='$strClass'><td>$key</td><td><a href='html/$fname_base'>$fname_base</a></td></tr>\n";
                } elsif ( $key eq "result_message") 
				{
                    $val =~ s/\n/<br>/g;
                    $val =~ s/[ ]/&nbsp;/g;
                    $$htable_ref .= "<tr valign='top' class='$strClass'><td>$key</td><td>$val</td></tr>\n";
                } else 
				{
                    $val =~ s/\n/<br>/g;
                    $val =~ s/[ ]/&nbsp;/g;
                    $$htable_ref .= "<tr valign='top' class='Passed'><td>$key</td><td>$val</td></tr>\n";
                }
            }
        }
    }
    if ($has_result && defined $htable_ref) 
	{
        $$htable_ref .= get_html_phase_report_table_stop_template();
    }
}

# Output results to a file or 
sub _output_results 
{
    my ($file, $str, $clear) = @_;

    Debug("Writing to text file: $file\n");

    # If we have not yet written to the file in this run,
    # then whack the file.

	if ($clear){
		unlink($file);
	} elsif (!exists($written_files->{$file})) {
        unlink($file);
    }

    # Write to stdout or append to the file

    if ($file eq "-") 
	{
        print $str;
        Verbose(">> Reported to stdout\n")
            if (!exists($written_files->{$file}));
    } else 
	{
    	if ($clear)
		{
    		MTT::Files::SafeWrite(1, $file, $str, ">");
    	} else 
		{
        	MTT::Files::SafeWrite(1, $file, $str, ">>");
    	}
        Verbose(">> Reported to text file $file\n")
            if (!exists($written_files->{$file}));
    }
    $written_files->{$file} = 1;
}

sub _get_report_filenames 
{
    my $results_arr = shift;
    my @files = ();

    foreach my $results (@$results_arr) 
	{

        foreach my $phase (keys %$results) 
		{
            my $phase_obj = $results->{$phase};

            foreach my $section (keys %{$phase_obj}) 
			{
                my $section_obj = $phase_obj->{$section};

                foreach my $report (@$section_obj) 
				{
                    my $rep_file = _get_filename($report, $section);
                    unshift(@files, $rep_file);
		        }
	        }
	    }
    }

    return @files;
}

sub _get_filename {
    my ($report, $section) = @_;

    # Substitute in the filename
    my $date = strftime("%m%d%Y", localtime());
    my $time = strftime("%H%M%S", localtime());
    my $mpi_name = $report->{mpi_name};
    my $mpi_install_section_name = $report->{mpi_install_section_name};
    my $mpi_version = $report->{mpi_version};
    my $phase = $report->{phase};
	my $suffix = "";
    my $ret;


	if ($mpi_install_section_name) {
		$suffix = "-$mpi_install_section_name"
	}

    # Hardcoded filename
    my $basename = MTT::Files::make_safe_filename("$phase-$section-$mpi_name-$mpi_version" . $suffix . ".txt");

    # Use an absolute path
    $ret = "$dirname/$basename"; 

#    Debug("_get_filename returning $ret\n");
    return $ret;
}

# Stringify any array references
sub _convert_array_refs 
{
    my $report = shift;

    foreach my $key (keys(%$report)) {

        if (ref($report->{$key}) =~ /array/i) {
            $report->{$key} = join("\n\n---\n\n", @{$report->{$key}});
        }
    }

    return $report;
}

# Make timestamps human-readable
sub _convert_timestamps 
{
    my $report = shift;

    foreach my $key (keys(%$report)) 
	{
        if ($key =~ /timestamp/ && $report->{$key} =~ /\d+/ && !($key =~ /human/)) 
		{
            $report->{$key . "_human"} = gmtime($report->{$key});
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
    my ($phase, $section, $mpi_version, $duration_human, $pass, $fail, $timed, $skipped, $rep_file_url, $dir) = @_;
    my $trClass;
    if ($fail or $timed) {
        $trClass = 'font-weight:bold; color:red;';
    } 

    my $tr = "<tr style=\"background:\#eeeee0; $trClass\"  valign='top'>\n";
    $tr .= "<td ><a href='$domain/$dir/$rep_file_url'>$phase</a></td><td>$section</td><td>$mpi_version</td><td >$duration_human</td><td>$pass</td><td>$fail</td><td>$timed</td><td>$skipped</td>\n</tr>\n";

    return $tr;
}

sub get_css_template
{
    my $tmpl = '
    <html xmlns:lxslt="http://xml.apache.org/xslt" xmlns:stringutils="xalan://org.apache.tools.ant.util.StringUtils">
    <META http-equiv="Content-Type" content="text/html; charset=US-ASCII">
    <head>
    <style type="text/css" media=screen>
    body {
    font:normal 100% verdana,arial,helvetica;
    color:#000000;
    }
    table tr td, table tr th {
    font-size: 73%;
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
    ';
    return $tmpl;
}

sub get_html_summary_report_template
{
	my $values_replace = {};
	$values_replace->{'REPORT_DATE'} =  `date +%F` ." ". `date +%k:%M:%S`;
	$values_replace->{'OFED_VERSION'} = `ofed_info -s`;
	$values_replace->{'CLUSTER_NAME'} = MTT::Values::Functions::cluster_name();
	
	my $helpper_hash = {};
	
	my $ini = $MTT::Globals::Internals->{ini};
	my @sects = $ini->Sections();
	my $product_version;
	my $skip_section;
	if ($MTT::Globals::Values->{shuffle_tests}->{sections})
	{
		MTT::Util::shuffle(\@sects);	
	}
	foreach my $section (@sects) 
	{
		print("text reporter: section  $section\n");
		if ($section =~ /^\s*mpi install:/) 
		{
			my $sim_sec_name = GetSimpleSection($section);
			$product_version =  MTT::Values::Value($ini, "mpi install: $sim_sec_name",'product_version');
			$skip_section = MTT::Values::Value($ini, "mpi install: $sim_sec_name",'skip_section');
			if(!defined($helpper_hash->{$product_version}) && $skip_section == 0)
			{
				$values_replace->{'PRODUCT'} .= $product_version . " ";
				$helpper_hash->{$product_version} = 1;
			}
		}
	}
	
    my $tmpl = '
    <html>
    <title>MTT Results: Summary</title>
    <body>
    <h1>MTT Results</h1>
    %HEADER%
    <hr size="1">
    <h2>Additional info</h2>
    <table border="0" cellpadding="5" cellspacing="2" width="95%">
    <tbody><tr style="font-weight: bold; text-align:left; background:#a6caf0;"  valign="top">
    <th>report date</th><th>product</th><th>ofed version</th><th nowrap="">cluster name</th>
    </tr>
    <tr style="font-weight: bold; text-align:left; background:#a6caf0;"  valign="top" class="Pass">
    <td style="background:#eeeee0;"  >%REPORT_DATE%</td><td style="background:#eeeee0;"  >%PRODUCT%</td><td style="background:#eeeee0;"  >%OFED_VERSION%</td><td style="background:#eeeee0;"  >%CLUSTER_NAME%</td>
    </tr>
    </tbody></table>
    <h2>Summary</h2>
    <table border="0" cellpadding="5" cellspacing="2" width="95%">
    <tr style="font-weight: bold; text-align:left; background:#a6caf0;"  valign="top">
    <th>Phase</th><th>Section</th><th>MPI Version</th><th>Duration</th><th>Pass</th><th>Fail</th><th>Time Out</th><th>Skip</th>
    </tr>
    %TESTS_RESULTS%
    </table>
    <h2>Totals</h2>
    <table border="0" cellpadding="5" cellspacing="2" width="95%">
    <tr style="font-weight: bold; text-align:left; background:#a6caf0;"  valign="top">
    <th>Tests</th><th>Failed</th><th>Passed</th><th nowrap>Duration</th>
    </tr>
    <tr valign="top">
    %TOTALS%
    </tr>
    </table>

    %FOOTER%
    </body>
    </html>
    ';
	my $tmp2;
	foreach my $key (keys %{$values_replace})
	{
		$tmp2 = $values_replace->{$key};
		$tmpl =~ s/%$key%/$tmp2/;
	}
    return $tmpl;
}


sub get_html_phase_report_table_start_template
{
    my $tmpl = '
    <table border="0" cellpadding="5" cellspacing="2" width="95%">
    <tr style="font-weight: bold; text-align:left; background:#a6caf0;"  valign="top">
    <th width="20%">Field</th><th>Value</th>
    </tr>
    ';
    return $tmpl;
}
sub get_html_phase_report_table_stop_template
{
    my $tmpl = '
    </table>
    ';
    return $tmpl;
}
sub get_html_phase_report_template_start
{
	my $css = get_css_template();
    my $tmpl = '
    <title>Phase report</title>
    <h1>MTT Report for single phase execution</h1>
    <hr size="1">
    <h2>Report</h2>
    ';
    return $css .  $tmpl;
}

sub get_html_phase_report_template_stop
{
    my $tmpl = '
    </body>
    </html>
    ';
    return $tmpl;
}
1;
