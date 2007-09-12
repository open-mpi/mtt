#!/usr/bin/env perl
#
# Copyright (c) 2007 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Values::Functions::MPI::IntelMPI;

use strict;

#--------------------------------------------------------------------------

# Get the Intel MPI version string from mpirun -version
sub get_version {
    my $bindir = shift;

    open INFO, "$bindir/mpirun -version|";

    my $version;
    while (<INFO>) {
        if (m/Version ([\d.]+)/) {
            $version .= $1;
        } elsif (m/\(R\) (.+) applications/) {
            $version .= " $1";
        }
    }
    close(INFO);
    return $version;
}

1;
