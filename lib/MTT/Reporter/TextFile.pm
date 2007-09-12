#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Reporter::TextFile;

use strict;
use Cwd;
use POSIX qw(strftime);
use MTT::Messages;
use MTT::Values;
use MTT::Files;
use MTT::Version;
use Data::Dumper;
use File::Basename;
use Text::TabularDisplay;
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

#--------------------------------------------------------------------------

sub Init {
    my ($ini, $section) = @_;

    # Grab TextFile INI params

    $summary_header = Value($ini, $section, "textfile_summary_header") . "\n"; 
    $summary_footer = Value($ini, $section, "textfile_summary_footer") . "\n"; 
    $detail_header  = Value($ini, $section, "textfile_detail_header ") . "\n"; 
    $detail_footer  = Value($ini, $section, "textfile_detail_footer ") . "\n"; 
    $textwrap       = Value($ini, $section, "textfile_textwrap"); 

    # Make it an absolute filename, because there's oodles of
    # chdir()'s within the testing.  Whack the file if it's already
    # there.

    if ($filename ne "-") {
        if ($filename !~ /\//) {
            $dirname = cwd();
            $filename = "$filename";
        } else {
            $dirname = dirname($filename);
            $filename = basename($filename);
        }

        Debug("File reporter initialized ($dirname/$filename)\n");
    } else {
        Debug("File reporter initialized (<stdout>)\n");
    }

    1;
}

#--------------------------------------------------------------------------

sub Finalize {

    # Print a roll-up report
    if (@results) {
        _summary_report(\@results);
    }

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

    my $table = Text::TabularDisplay->new(("Phase","Section","Pass","Fail","Time out","Skip"));

    foreach my $results (@$results_arr) {

        foreach my $phase (keys %$results) {
            my $phase_obj = $results->{$phase};

            foreach my $section (keys %{$phase_obj}) {
                my $section_obj = $results->{$phase}{$section};

                my ($pass, $fail, $timed, $skipped) = (0, 0, 0, 0);

                foreach my $results_hash (@$section_obj) {

                    if ($results_hash->{test_result} eq MTT::Values::PASS) {
                        $pass++;
                    } elsif ($results_hash->{test_result} eq MTT::Values::FAIL) {
                        $fail++;
                    } elsif ($results_hash->{test_result} eq MTT::Values::TIMED_OUT) {
                        $timed++;
                    } elsif ($results_hash->{test_result} eq MTT::Values::SKIPPED) {
                        $skipped++;
                    }
                }
                $table->add($phase, $section, $pass, $fail, $timed, $skipped);
            }
        }
    }
    print $table->render . "\n";
    print $summary_footer;

    # Write the Summary report to a file
    my $filename = "All_phase-summary.txt";
    my $file = "$dirname/" . MTT::Files::make_safe_filename("$filename");

    _output_results($file,
        join("\n", ($summary_header, 
                    $table->render,
                    $summary_footer)));

    1;
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
        open(OUT, ">>$file");
        print OUT $str;
        close(OUT);
        Verbose(">> Reported to text file $file\n")
            if (!exists($written_files->{$file}));
    }
    $written_files->{$file} = 1;
}

sub _create_temp_file {
    my ($dir, $suffix) = @_;

    use File::Temp qw/tempfile tempdir/;

    my ($filehandle, $tempfile) =
        tempfile(DIR => $dir, SUFFIX => $suffix);

    return $tempfile;
}

sub _get_filename {

    my ($report, $section) = @_;

    # Substitute in the filename
    my $date = strftime("%m%d%Y", localtime);
    my $time = strftime("%H%M%S", localtime);
    my $mpi_name = $report->{mpi_name};
    my $mpi_version = $report->{mpi_version};
    my $phase = $report->{phase};
    my $file;

    # User specifies a filename
    my $filename = "$phase-$section-$mpi_name-$mpi_version.txt";

    # Do not be strict on this eval.  The user may supply
    # some undeclared vars in the filename format template,
    # but it's not the end of the world.
    no strict;
    eval "\$file = MTT::Files::make_safe_filename(\"$filename\");";
    use strict;

    if ($@) {
        Warning("Could not create " . caller() . " $file: $@\n");
        return undef;
    }
    return "$dirname/$file";
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

1;
