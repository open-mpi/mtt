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

package MTT::Values::Functions::MPI::MPICH2;

use strict;
use MTT::Messages;
use Data::Dumper;

#--------------------------------------------------------------------------

sub find_bindings {
    my ($bindir, $lang) = @_;

    # MVAPICH mpich2version does not include the bindings
    # listings. #@$%#@$%!!  So first run it and see if we get the CC
    # bindings (which should *always* be there).  If we don't find
    # CC:, then we're in MVAPICH and we have to fall back to a
    # different way to figure out if we have given bindings.
    if (-x "$bindir/mpich2version") {
        open INFO, "$bindir/mpich2version|";
        my @file = <INFO>;
        chomp @file;
        close INFO;

        my $shows_bindings = 0;
        my $found = 0;
        foreach my $l (@file) {
            $shows_bindings = 1
                if ($l =~ /^CC:/);
            $found = 1
                if ($l =~ /^$lang\s+/);
        }
        return $found
            if ($shows_bindings);

        # If we fall through, then mpich2version doesn't show the
        # bindings
    }

    # Check for the specific wrapper compiler; if it's there, we have
    # those language bindings.
    return (($lang eq "CXX:" && -x "$bindir/mpicxx") ||
            ($lang eq "F77:" && -x "$bindir/mpif77") ||
            ($lang eq "F90:" && -x "$bindir/mpif90"));
}

#--------------------------------------------------------------------------

sub find_bitness {
    my ($bindir) = @_;

    # JMS still need to write this
    return "64";
}

#--------------------------------------------------------------------------

sub adjust_wrapper {
    my ($wrapper, $field, $value) = @_;
    Debug("Adjusting MPICH2 wrapper: $wrapper / $field / $value\n");
    if (-f $wrapper && open(WIN, $wrapper) && open(WOUT, ">$wrapper.new")) {
        while (<WIN>) {
            if (m/^$field="(.+)"/) {
                print WOUT "$field=\"$1 $value\"\n";
            } else {
                print WOUT $_;
            }
        }
        close(WIN);
        close(WOUT);
        system("cp $wrapper.new $wrapper");
        unlink("$wrapper.new");
   }
}

1;
