#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2007-2008 Sun Microsystems, Inc.  All rights reserved.
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
use File::Spec;
use File::Basename;
use File::Temp qw(tempfile);
use Storable qw(dclone);
use vars qw(@EXPORT);
use base qw(Exporter);
@EXPORT = qw(WriteINI ReadINI GetSimpleSection);

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
       
    my $ini_save = dclone($ini);

    return $ini if (! $section_arg and ! $no_section_arg);

    my ($delete,
        $section,
        $patterns,
        @patterns_and,
        $re,
        $del_on_match,
        $del_on_mismatch,
        @sections_to_delete
    );

    if (defined(@$section_arg[0])) {
        $patterns = $section_arg;
        $del_on_match = 0;
        $del_on_mismatch = 1;
    } else {
        $patterns = $no_section_arg;
        $del_on_match = 1;
        $del_on_mismatch = 0;
    }

    my $or_delimiter = '\s+';
    my $and_delimiter = '\;';

    # Iterate through the ini file, section by section
    foreach $section ($ini->Sections) {

        # Always process the "mtt" and "lock" sections
        next
            if ($section =~ /^\s*mtt\s*$/ ||
                $section =~ /^\s*lock\s*$/);

        # Iterate through every ---[no]-section argument,
        # and OR them together
        foreach my $pattern_arg (@$patterns) {

            # Allow for a CSV of section filters, so
            #   --section foo --section --bar
            # compacts to:
            #   --section "foo bar"
            $delete = 0;
            foreach my $pattern (split(/$or_delimiter/, $pattern_arg)) {

                # Generate on-the-fly, perl code that will
                # perform the regular expressions, and AND
                # them together.
                # (Conform to agrep ';' syntax for AND operations)
                my $tmp = $pattern;
                $tmp =~ s/\//\\\//g;
                @patterns_and = split /$and_delimiter/, $tmp;
                $re = join(" and ", map { "\$section =~ /$_/i" } @patterns_and);
                Debug("FilterINI: regexp (section=$section): $re\n");
                my $eval = "
                if ($re) {
                    \$delete = $del_on_match;
                    last;
                } else {
                    \$delete = $del_on_mismatch;
                }";
                eval $eval;
                Debug("FilterINI: Delete: $delete (del on match: $del_on_match, del on mismatch: $del_on_mismatch)\n");
            }

            # If we're deleting on no match (i.e., --section), if any
            # of the $delete results are false, then we're done (i.e.,
            # we matched and therefore we're keeping the section).

            # If we're deleting on match (i.e., --no-section), if any
            # of the $delete results are true, then we're done (i.e.,
            # we matched and therefore we're deleting the section).

            last if (($del_on_mismatch && !$delete) ||
                     ($del_on_match && $delete));
        }
        # Flag sections for deletion (to be safe, we do not
        # delete sections while iterating over them)
        push(@sections_to_delete, $section) if ($delete);
    }

    # Delete the flagged sections
    foreach my $section (@sections_to_delete) {
        $ini->DeleteSection($section);
    }

    my @final_section_list;
    my @ini_sections = $ini->Sections;

    # Make sure there is at least one MPI Details section
    if (! grep(/mpi details/i, @ini_sections)) {

        # Delete the flagged sections,
        # but this time leave in "mpi details" sections
        foreach my $section (@sections_to_delete) {
            next if ($section =~ /mpi.details/);

            $ini_save->DeleteSection($section);
        }
        @final_section_list = $ini_save->Sections;
        Debug("FilterINI: Final list of sections:\n    " . 
                join("\n    ", map { "[$_]" } @final_section_list) . "\n");  

        return $ini_save;
    }

    @final_section_list = $ini->Sections;
    Debug("FilterINI: Final list of sections:\n    " . 
            join("\n    ", map { "[$_]" } @final_section_list) . "\n");  

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

# Predefine some INI parameters such as the name
# of the INI file
sub InsertINIPredefines {
    my($ini, $file) = @_;

    # Prevent "Can't store GLOB items" error from
    # Storable::dclone. (It makes no sense to set INI_NAME
    # if the INI is coming from STDIN)
    if (ref($file) =~ /GLOB/i) {
        $file = undef;
    }

    my $zero;

    # Convert relative paths to absolute paths and expand "~"
    $file = File::Spec->rel2abs(glob $file);
    $zero = File::Spec->rel2abs(glob $0);

    foreach my $section ($ini->Sections) {
        if (! defined($ini->val($section, "INI_NAME"))) {
            $ini->delval($section, "INI_NAME");
            $ini->newval($section, "INI_NAME", $file);
        }
    }

    foreach my $section ($ini->Sections) {
        if (! defined($ini->val($section, "PROGRAM_NAME"))) {
            $ini->delval($section, "PROGRAM_NAME");
            $ini->newval($section, "PROGRAM_NAME", $zero);
        }
    }

    return $ini;
}

# Expand include_section parameters
sub ExpandIncludeSections {
    my($ini) = @_;

    foreach my $section ($ini->Sections) {
        _expand_include_sections($ini, $section);
    }
    return $ini;
}

# Worker subroutine for recursive ExpandIncludeSections
sub _expand_include_sections {
    my($ini, $section) = @_;

    foreach my $parameter ($ini->Parameters($section)) {
        if ($parameter eq "include_section") {

            my $include_section = $ini->val($section, $parameter);

            # Get CSV of include_sections
            my @include_sections = split(/,/, $include_section);

            # Allow leading and trailing whitespace in include_section lists
            foreach (@include_sections) {
                s/^\s*|\s*$//g;
            }

            foreach $include_section (@include_sections) {
                if (! $ini->SectionExists($include_section)) {
                    Error("include_section [$include_section] does not exist!\n");
                }

                # Traverse to other includes in case the include itself
                # has included sections
                _expand_include_sections($ini, $include_section);

                # Add in all of the include_section params into the section
                foreach my $p ($ini->Parameters($include_section)) {
                    my $v = $ini->val($include_section, $p);

                    # Parent INI sections take precendence in a
                    # name collision
                    if (! defined($ini->val($section, $p))) {
                        $ini->newval($section, $p, $v);
                    }
                }
            }
        }
    }
}

# Expand include_file parameters
sub ExpandIncludeFiles { 
    my ($file) = @_;
    Debug("Expanding include_file(s) parameters in $file\n");

    # Get the path to the INI file
    $file = File::Spec->rel2abs(glob $file);
    my $dirname = dirname($file);

    # Replace include_file parameters
    my $contents = MTT::Files::Slurp($file);

    my $ret = _expand_include_files($contents, $dirname);

    # Write the expanded INI file to a temporary file,
    # and return the file name
    my ($fh, $tempfile) = tempfile(SUFFIX => ".ini");

    MTT::Files::SafeWrite(1, $tempfile, $ret);

    return $tempfile;
}

# Recursively expand all the include_files parameters
sub _expand_include_files {
    my ($contents, $dirname) = @_;

    # Search for this pattern and splice in contents of its value
    my $pattern = '\n\s*include_files?\s+=(.*)\n';

    # Just return the contents if there's nothing to expand
    if ($contents !~ /$pattern/i) {
        return $contents;
    }

    my $ret;
    while ($contents =~ /$pattern/i) {
        my @files = split(/,/, $1);

        # Gather the contents of the include_files
        my $include_contents;
        foreach my $file (@files) {
            Debug("Including INI file: $file\n");

            # Remove leading/trailing whitespace and make it 
            # an absolute path (it is all relative to the argument
            # given to --file|f)
            $file =~ s/(^\s+)|(\s+$)//g;

            # If an absolute path is not used, then the file is assumed to be
            # relative to the main --file|f option
            if ($file !~ /^\s*\//) {
                $file = "$dirname/" . basename($file);
            }

            if (! -r $file) {
                Warning("Could not read include_file parameter: $file; skipping.\n");
                next;
            }

            # The inluded contents may contain include_files parameters themselves
            $include_contents .= _expand_include_files(MTT::Files::Slurp($file), $dirname);
        }

        $contents =~ s/$pattern/\n$include_contents/;
    }

    $ret = _expand_include_files($contents);

    return $ret;
}

# Takes "Foo: bar" as an argument, and returns "bar"
sub GetSimpleSection {
    my ($str) = @_;
    if ($str =~ /^\s*[^:]+:\s*(.*)$/) {
        my $ret = $1;
        $ret =~ s/\s+$//g;
        return $ret;
    } else {
        return $str;
    }
}

1;
