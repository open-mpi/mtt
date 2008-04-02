#!/usr/bin/env perl
#
# Copyright (c) 2007 Sun Microystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Values::Functions::OS::Solaris;

use strict;
use MTT::Messages;

#--------------------------------------------------------------------------

# Get the Solaris release
sub get_release {

    my $release_file = "/etc/release";
    my $head;
    my @tokens;

    if (! -f $release_file) {
        Warning("No $release_file, returning.\n") ;
        return undef;
    }

    # E.g.,
    # $ cat /etc/release
    #             Solaris 10 11/06 s10s_u3wos_10 SPARC
    # Copyright 2006 Sun Microsystems, Inc.  All Rights Reserved.
    #              Use is subject to license terms.
    #                 Assembled 14 November 2006
    #

    open(FH, "< $release_file");
    $head = <FH>;
    $head =~ s/^\s+|\s+$//g;
    @tokens = split(/\s+/, $head);

    return $tokens[3];
}

1;
