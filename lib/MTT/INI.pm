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

1;


