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

package MTT::INI;

use strict;
use Config::IniFiles;
use MTT::Messages;
use MTT::Values;
use Data::Dumper;
use vars qw(@EXPORT);
use base qw(Exporter);
@EXPORT = qw(WriteINI ReadINI);

#--------------------------------------------------------------------------

# Simplistic routine to write out a single-level hash to an INI file
sub WriteINI {
    my ($filename, $section, $data) = @_;

    my $cfg = new Config::IniFiles();
    $cfg->AddSection($section);
    $cfg->SetSectionComment($section, "This file was automatically created by Config/IniFiles.pm.  Any changes made manually are likely to be lost!");
    foreach my $k (keys(%$data)) {
        $cfg->newval($section, lc($k), $data->{$k});
    }
    $cfg->WriteConfig($filename);
    $cfg->Delete();
}

#--------------------------------------------------------------------------

# Simplistic routine to read in a single-level hash from an INI file
sub ReadINI {
    my ($filename, $section) = @_;

    if (-f $filename) {
        my $cfg = new Config::IniFiles(-file => $filename,
                                       -nocase => 1,
                                       -allowcontinue => 1);
        if ($cfg && $cfg->SectionExists($section)) {
            my $ret;
            foreach my $p ($cfg->Parameters($section)) {
                $ret->{$p} = $cfg->val($section, $p);
                # Workaround for bug in Config::INI -- it adds an
                # extra \n after each multi-line value
                $ret->{$p} =~ s/\n\n/\n/g;
            }
            return $ret;
        }
    }

    # Nothing found; so sad

    return undef;
}

# Override ini file params with those supplied at command-line
sub OverrideINIParams {

    my($ini, $ini_args) = @_;

    foreach my $param (keys %$ini_args) {
        my @matchers = split /,/, $ini_args->{$param}->{match};
        my $matcher = join("\.\*", @matchers) . '|' . join("\.\*", reverse @matchers);
        foreach my $section ($ini->Sections) {
            if ($section =~ /$matcher/i) {
                $ini->delval($section, $param);
                $ini->newval($section, $param, $ini_args->{$param}->{value});
            }
        }
    }

    return $ini;
}

# Filter ini sections at the command line
sub FilterINISections {

    my($ini, $section_arg, $no_section_arg) = @_;
       
    return $ini if (! $section_arg and ! $no_section_arg);

    my ($delete,
        $section,
        $patterns,
        @patterns_and,
        $re,
        $del_on_match,
        $del_on_mismatch,
        @sections_to_delete);

    if (defined(@$section_arg[0])) {
        $patterns = $section_arg;
        $del_on_match = 0;
        $del_on_mismatch = 1;
    }
    else {
        $patterns = $no_section_arg;
        $del_on_match = 1;
        $del_on_mismatch = 0;
    }

    # Iterate through the ini file, section by section
    foreach $section ($ini->Sections) {

        # Always process the "mtt" and "mpi details" sections
        next if ($section =~ /\bmtt\b|mpi\s+details/i);

        # Iterate through every ---[no]-section argument,
        # and OR them together
        foreach my $pattern (@$patterns) {

            # Generate on-the-fly, perl code that will
            # perform the regular expressions, and AND
            # them together.
            # (Conform to agrep ';' syntax for AND operations)
            @patterns_and = split /\;/, $pattern;
            $re = join(" and ", map { "\$section =~ /$_/i" } @patterns_and);

            my $eval = "
            if (($re)) {
                \$delete = $del_on_match;
                last;
            }
            else {
                \$delete = $del_on_mismatch;
            }";
            eval $eval;
        }
        # Flag sections for deletion (to be safe, we do not
        # delete sections while iterating over them)
        push(@sections_to_delete, $section) if ($delete);
    }

    # Delete the flagged sections
    foreach my $section (@sections_to_delete) {
        $ini->DeleteSection($section);
    }

    return $ini;
}

# Check the INI for duplicate sections
sub ValidateINI {

    my($inifile) = @_;
    my @duplicates;
    my %sections;
    my $opener;

    open(ini, "< $inifile");

    Debug("Validating INI inifile: $inifile\n");

    while (<ini>) {
        my $section = $1 if (/^\s*(\[[^\]]+\])\s*$/);
        $sections{$section}++ if ($section !~ /^\s*$/);
        push(@duplicates, $section) if ($sections{$section} eq 2);
    }

    if (@duplicates) {
        Error("There are duplicate sections for: \n\t" . join("\n\t", @duplicates) . "\n" . 
              "Please eliminate duplicate sections in INI file(s).\n");
    }
    close(*ini);
}

1;
