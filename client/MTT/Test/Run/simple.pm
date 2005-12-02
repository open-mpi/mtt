#!/usr/bin/env perl
#
# Copyright (c) 2004-2005 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2004-2005 The Trustees of the University of Tennessee.
#                         All rights reserved.
# Copyright (c) 2004-2005 High Performance Computing Center Stuttgart, 
#                         University of Stuttgart.  All rights reserved.
# Copyright (c) 2004-2005 The Regents of the University of California.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Run::simple;

use strict;
use Cwd;
use MTT::Messages;
use MTT::Values;
use Data::Dumper;

#--------------------------------------------------------------------------

sub Run {
    my ($ini, $section, $build_dir, $mpi_install) = @_;
    my $ret;

    $ret->{success} = 0;

    # Look up the tests value.  Handle if we get an ARRAY back or a
    # string of whitespace delimited executables

    my $tests = Value($ini, $section, "tests");
    if ($tests) {
        # Split it up if it's a string
        if (ref($tests) eq "") {
            my @tests = split(/\s/, $tests);
            $tests = \@tests;
        }

        # Now make a list of hashes only containing "executable"
        foreach my $t (@$tests) {
            push(@{$ret->{tests}}, {
                executable => $t,
            });
        }

        $ret->{success} = 1;
    }

    return $ret;
} 

1;
