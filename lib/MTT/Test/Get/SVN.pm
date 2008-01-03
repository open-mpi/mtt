#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Get::SVN;
my $package = __PACKAGE__;

use strict;
use MTT::Messages;
use MTT::Test::Get::SCM;

#--------------------------------------------------------------------------

sub Get {
    Warning("The SVN module is deprecated. Please use SCM instead.\n");
    return MTT::Test::Get::SCM::Get(@_);
}

1;
