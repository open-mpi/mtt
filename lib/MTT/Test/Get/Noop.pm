#!/usr/bin/env perl
#
# Copyright (c) 2007 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Get::Noop;

use strict;

#--------------------------------------------------------------------------

sub Get {
    my $ret;
    $ret->{have_new} = 1;
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";
    $ret->{prepare_for_install} = "MTT::Common::Copytree::PrepareForInstall";
    return $ret;
} 

#--------------------------------------------------------------------------

sub PrepareForInstall {
    return cwd();
}

1;
