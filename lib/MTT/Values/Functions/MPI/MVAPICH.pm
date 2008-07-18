#!/usr/bin/env perl
#
# Copyright (c) 2008      Mellanox Technologies.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Values::Functions::MPI::MVAPICH;

use strict;
use MTT::Messages;
use Data::Dumper;
use Cwd;

#--------------------------------------------------------------------------

sub find_bindings {
    my ($bindir, $lang) = @_;

    return (($lang eq "CXX" && -x "$bindir/mpicxx") ||
            ($lang eq "F77" && -x "$bindir/mpif77") ||
            ($lang eq "F90" && -x "$bindir/mpif90"));
}

#--------------------------------------------------------------------------

sub get_version {
    Debug("get_version got @_\n");
    my $bindir = shift;
    my $ver;
    my $first_line = 1;

    open VERSION, "$bindir/mpirun_rsh -v 2>&1 |";

    while (<VERSION>) {
        chomp;
        my @line = split(' ');
        if ($first_line) {
            $first_line = 0;
            $ver = $line[$#line];
        } else {
            $ver = join('-', $ver, $line[$#line]);
        }
    }
    close(VERSION);
    Debug("get_version returning $ver\n");
    return $ver;
}

1;
