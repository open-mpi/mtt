#!/usr/bin/env perl
#
# Copyright (c) 2007 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Common::SCM::SVK;

use strict;
use MTT::Common::SCM::SVN;

#--------------------------------------------------------------------------

sub Checkout {
    return MTT::Common::SCM::SVN::Checkout(@_);
}

sub check_previous_revision {
    return MTT::Common::SCM::SVN::check_previous_revision(@_);
}

1;
