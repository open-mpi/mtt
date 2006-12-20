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
use MTT::Messages;
use Data::Dumper;

# Global variable to hold the values

our $Values;

# Defaults that are reset on a per-ini-file basis

my $_defaults = {
    hostfile => undef,
    hostlist => undef,
    max_np => undef,
    textwrap => 76,
    drain_timeout => 5,

    mpi_install_save_successful => 0,
    mpi_install_save_failed => 1,
    test_build_save_successful => 0,
    test_build_save_failed => 1,
    test_run_save_successful => 0,
    test_run_save_failed => 0,

    trial => 0,
};

# Reset $Globals per a specific ini file

sub load {
    my ($ini) = @_;

    %$Values = %$_defaults;

    # Max_np (do before hostfile / hostlist) 

    # NOTE: We have to use the full name MTT::Values::Value() here
    # because this file includes MTT::Value which includes
    # MTT::Value::Functions, but MTT::Value::Functions includes this
    # file (i.e., a circular dependency).

    # Hostfile

    my $val = MTT::Values::Value($ini, "MTT", "hostfile");
    if ($val) {
        $Values->{hostfile} = $val;
        parse_hostfile($val);
    }

    # Hostlist

    my $val = MTT::Values::Value($ini, "MTT", "hostlist");
    if ($val) {
        $Values->{hostlist} = $val;
        parse_hostlist($val);
    }

    # Simple parameters

    my @names = qw/max_np textwrap drain_timeout save_successful_mpi_installs save_failed_mpi_installs save_successful_test_builds save_failed_test_builds save_successful_test_runs save_failed_test_runs trial/;

    foreach my $name (@names) {
        my $val = MTT::Values::Value($ini, "MTT", $name);
        $Values->{$name} = $val
            if ($val);
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

    # Here's how we calculte max_np
    #
    # - If the hostname (first token) is of the form "name:X", add X
    #   to $max_np and continue to the next line
    # - If any of the remaining tokens are "slots=X", add X to $max_np
    #   and continue to the next line
    # - If any of the remaining tokens are "max[_-]slots=X", add X to
    #   $max_np and continue to the next line
    # - Add 1 to $max_np

    my $max_np = 0;
    while (<FILE>) {
        # Skip comment lines
        next
            if (/^\s*\#/ ||
                /^\s*\n/);

        # We got a good line; so split it up into tokens
        my @tokens = split(/\s+/);

        # The first token is the hostname
        shift @tokens;
        if (/:(\d+)$/) {
            Debug(">> Hostfile: Found :X = $1\n");
            $max_np += $1;
            next;
        }

        # Go through the rest of them looking for "slots=X"
        my $found = 0;
        foreach (@tokens) {
            if (/^slots=(\d+)/) {
                Debug(">> Hostfile: Found slots = $1\n");
                $max_np += $1;
                $found = 1;
                last;
            }
        }
        next
            if ($found);

        # Go through the rest of them looking for "max[-_]slots=X"
        foreach (@tokens) {
            if (/^max[_-]slots=(\d+)/) {
                Debug(">> Hostfile: Found max_slots = $1\n");
                $max_np += $1;
                $found = 1;
                last;
            }
        }
        next
            if ($found);

        # Didn't find anything.  So just add 1 to $max_np;
        ++$max_np;
    }
    $Values->{hostfile_max_np} = $max_np;
    Debug(">> Got default hostfile: $file, max_np: $max_np\n");
    
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
    Debug(">> Got default hostlist: $hostlist, max_np: $max_np\n");
}

1;
