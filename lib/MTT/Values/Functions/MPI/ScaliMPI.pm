#!/usr/bin/env perl
#
# Copyright (c) 2007 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Values::Functions::MPI::ScaliMPI;

use strict;

#--------------------------------------------------------------------------

# Get the Scali MPI version string from mpirun -version
sub get_version {
    my $bindir = shift;

    return "Someone needs to fill in MTT/Values/Functions/MPI/ScaliMPI.pm";
}

1;
