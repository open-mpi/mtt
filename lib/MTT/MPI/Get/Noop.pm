#!/usr/bin/env perl
#
# Copyright (c) 2007 Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2008 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::MPI::Get::Noop;
my $package = __PACKAGE__;

use strict;
use MTT::Values;
use MTT::DoCommand;

#--------------------------------------------------------------------------

sub Get {
    my $ret;
    $ret->{version} = MTT::Values::RandomString(10);
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{have_new} = 1;
    $ret->{result_message} = "Success";
    $ret->{prepare_for_install} = "${package}::PrepareForInstall";
    return $ret;
} 

#--------------------------------------------------------------------------

sub PrepareForInstall {
    return MTT::DoCommand::cwd();
}

1;
