#!/usr/bin/env perl
#
# Copyright (c) 2007 Cisco, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Util;

use strict;

use vars qw(@EXPORT);
use base qw(Exporter);
@EXPORT = qw(does_hash_key_exist);

use MTT::Globals;
use MTT::Messages;
use MTT::Values;

#--------------------------------------------------------------------------

sub does_hash_key_exist {
    my $hash = shift;
    my $key = shift;
    while (defined($key) ) {
        return undef
            if (!exists($hash->{$key}));
        $hash = $hash->{$key};
        $key = shift;
    }
    return $hash;
}

#--------------------------------------------------------------------------

sub find_terminate_file {
    my $files = $MTT::Globals::Values->{terminate_files};

    # If we previously found a terminate file, just return
    return 1
        if ($MTT::Globals::Values->{time_to_terminate});

    # Check for any of the terminate files
    if (defined($files) && $files) {
        foreach my $f (@$files) {
            my $e = EvaluateString($f);
            if (-f $e) {
                Verbose("--> Found terminate file: $e\n");
                Verbose("    Exiting...\n");
                $MTT::Globals::Values->{time_to_terminate} = 1;
                return 1;
            }
        }
    }

    # We didn't find any, so return false
    return 0;
}

1;
