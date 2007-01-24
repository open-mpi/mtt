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

package MTT::Test::Specify;

use strict;
use MTT::Module;
use Data::Dumper;

#--------------------------------------------------------------------------

sub Specify {
    my ($module, $ini, $section, $test_build, $mpi_install, $config) = @_;

    my $ret = MTT::Module::Run("MTT::Test::Specify::$module",
                            "Specify", $ini, $section, $test_build,
                            $mpi_install, $config);
    return $ret;
}

1;
