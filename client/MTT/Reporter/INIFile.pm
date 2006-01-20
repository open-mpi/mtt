#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Reporter::INIFile;

use strict;
use Cwd;
use POSIX qw(strftime);
use MTT::Messages;
use MTT::Values;
use MTT::Files;
use Data::Dumper;

# directory and file to write to
my $dirname;
my $filename;

# files we've written to already in this run
my $written_files;

#--------------------------------------------------------------------------

sub Init {
    my ($ini, $section) = @_;

    # Extract data from the ini fields

    $filename = Value($ini, $section, "file");
    if (!$filename) {
        Warning("Not enough information in INIFile Reporter section [$section]; must have filename; skipping this section");
        return undef;
    }

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
        Debug("INIFile reporter initialized ($dirname/$filename)\n");
    } else {
        Debug("INIFile reporter initialized (<stdout>)\n");
    }

    1;
}

#--------------------------------------------------------------------------

sub Submit {
    my ($id, $entries) = @_;

    Debug("INIFile reporter\n");

    foreach my $entry (@$entries) {
        my $phase = $entry->{phase};
        my $section = $entry->{section};
        my $report = $entry->{report};

        # Substitute in the filename

        my $date = strftime("%m%d%Y", localtime);
        my $time = strftime("%H%M%S", localtime);
        my $mpi_name = $report->{mpi_name} ? $report->{mpi_name} : "Unknown-MPI-name";
        my $mpi_section = $report->{mpi_section_name} ? $report->{mpi_section_name} : "Unknown-MPI-section";
        my $mpi_version = $report->{mpi_version} ? $report->{mpi_version} : "Unknown-MPI-Version";

        my $file;
        my $e = "\$file = MTT::Files::make_safe_filename(\"$filename\");";
        eval $e;
        $file = "$dirname/$file";
        Debug("Writing to INI file: $file\n");

        # If we have not yet written to the file in this run, then
        # whack the file.

        if (!exists($written_files->{$file})) {
            unlink($file);
            $written_files->{$file} = 1;
        }

        # Write the file; append if it's already there

        my $ini = new Config::IniFiles();
        my $section = "Section $written_files->{$file}";
        $ini->AddSection($section);
        $ini->SetSectionComment($section, "This file automatically created by engine.pl.  Any changes made manually are likely to be lost!");
        foreach my $k (keys(%$report)) {
            $ini->newval($section, lc($k), $report->{$k});
        }
        $ini->WriteConfig($file);
        $ini->Delete();
    }
}

1;
