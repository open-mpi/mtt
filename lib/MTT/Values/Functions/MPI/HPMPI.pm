#!/usr/bin/env perl
#
# Copyright (c) 2007 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Values::Functions::MPI::HPMPI;

use strict;

#--------------------------------------------------------------------------

# Get the HP MPI version string from mpirun -version
sub get_version {
    my $bindir = shift;

    open INFO, "$bindir/mpirun -version|";

    while (<INFO>) {
        if (m/^mpirun: HP MPI (\d.+)$/) {
            close(INFO);
            return $1;
        }
    }
    close(INFO);
    return undef;
}

1;
