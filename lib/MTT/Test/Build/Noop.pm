#!/usr/bin/env perl
#
# Copyright (c) 2007 Sun Microsystems, Inc. All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Build::Noop;

use strict;

use MTT::Values;

#--------------------------------------------------------------------------

sub Build {
    my ($ini, $mpi_install, $config) = @_;

    # In case of tests located in different folder and no much space available
    # on target scratch, it can be useful to point another location of prebuilt
    # tests.
    my $install_dir = Value($ini, $config->{full_section_name}, "installdir");

    my $ret;
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{exit_status} = 0;
    $ret->{result_message} = "Success";
    $ret->{installdir} = $install_dir if $install_dir;

    return $ret;
} 

1;
