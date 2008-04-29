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

package MTT::Common::SCM::Unknown;
my ($package) = (__PACKAGE__ =~ m/(\w+)$/);

use strict;
use MTT::Messages;
use MTT::DoCommand;
use Data::Dumper;

#--------------------------------------------------------------------------

sub Checkout {
    my ($params) = @_;

    my $ret = undef;

    my $x = MTT::DoCommand::Cmd(1, $cmd);

    return $ret
        if (!MTT::DoCommand::wsuccess($x->{exit_status}));

    Warning("MTT does not know how to get a version number from this output: $x->{result_stdout}");

    return "unknown";
}

1;
