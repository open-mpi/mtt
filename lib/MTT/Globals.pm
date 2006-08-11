#!/usr/bin/env perl
#
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Globals;

use strict;

use MTT::Values;
use Data::Dumper;

# Global variable to hold the values

our $Values;

# Defaults that are reset on a per-ini-file basis

my $_defaults = {
    hostfile => undef,
    hostlist => undef,
    max_np => undef,
};

# Reset $Globals per a specific ini file

sub load {
    my ($ini) = @_;

    %$Values = %$_defaults;

    # Max_np (do before hostfile / hostlist)

    my $val = Value($ini, "MTT", "max_np");
    $Values->{max_np} = $val
        if ($val);

    # Hostfile

    my $val = Value($ini, "MTT", "hostfile");
    if ($val) {
        $Values->{hostfile} = $val;
        parse_hostfile($val);
    }

    # Hostlist

    my $val = Value($ini, "MTT", "hostlist");
    if ($val) {
        $Values->{hostlist} = $val;
        parse_hostlist($val);
    }
}


#
# Test that a hostfile is good, and if we don't have one already,
# generate a max_np value.
#
sub parse_hostfile {
    my ($file) = @_;

    # Check that the file exists, is readable, and we can open it

    if ($file =~ /^\s*$/) {
        delete $Values->{hostfile};
        return;
    }

    my $bad = 0;
    if (! -r $file) {
        $bad = 1;
    } else {
        open(FILE, $file) || ($bad = 1);
    }

    if ($bad) {
        MTT::Messages::Warning("Unable to read hostfile: $file -- ignoring\n");
        delete $Values->{hostfile};
        return;
    }

    my $lines = 0;

    # First order-approximation -- Ethan to make this better later.
    # Just count the number of non-empty, non-comment lines in the
    # file.  Better would be to actually parse it, count the "cpu=X"
    # stuff, etc.

    while (<FILE>) {
        next
            if (/^\s*\#/ ||
                /^\s*\n/);
        ++$lines;
    }
    $Values->{hostfile_max_np} = $lines;
    
    close(FILE);
}


#
# Test that a hostlist is good, and if we don't have one already,
# generate a max_np value.
#
sub parse_hostlist {
    my ($str) = @_;

    # If it's empty, do nothing

    if ($str =~ /^\s*$/) {
        delete $Values->{hostlist};
        return;
    }

    # Made a hostlist suitable for mpiexec and count the max procs

    my @vals = split(/\s+/, $str);
    my $hostlist;
    my $max_np;
    foreach (@vals) {
        my ($name, $count) = split(/:/);
        $count = 1
            if (! $count);
        $max_np += $count;
        while ($count > 0) {
            $hostlist .= ","
                if ($hostlist);
            $hostlist .= $name;
            --$count;
        }
    }
    
    # Save the final values
    
    $Values->{hostlist} = $hostlist;
    $Values->{hostlist_max_np} = $max_np;
}

1;
