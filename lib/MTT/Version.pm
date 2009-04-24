#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2007-2009 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Version;

use strict;

# Major and minor version number of the MTT

our $Major = "4";
our $Minor = "0";
our $Release = "0";
our $Greek = "a1";

our $Combined = "$Major.$Minor";
$Combined .= ".$Release" if ("0" ne $Release);
$Combined .= $Greek if ($Greek);

1;
