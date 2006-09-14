#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Run::NPB;

use strict;
use Cwd;
use MTT::Messages;
use MTT::Values;
use Data::Dumper;

#--------------------------------------------------------------------------

sub Specify {
    my ($ini, $section, $build_dir, $mpi_install) = @_;
    my $ret;

    $ret->{success} = 0;
    $ret->{perfbase_xml} = Value($ini, $section, "perfbase_xml");
    my $exists = Value($ini, $section, "only_if_exec_exists");

    # DIRECTLY COPIED FROM SIMPLE -- NEEDS TO BE MODIFIED


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
            my $good = 1;
            $good = 0
                if ($exists && ! -x $t);
            push(@{$ret->{tests}}, {
                executable => $t,
            })
                if ($good);
        }

        $ret->{success} = 1;
    }

    return $ret;
} 

1;
