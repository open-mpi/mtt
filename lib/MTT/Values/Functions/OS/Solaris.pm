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
    my $ret;

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
    # $ cat /etc/release
    #              OpenSolaris 2008.05 snv_86_rc3 X86
    # Copyright 2008 Sun Microsystems, Inc.  All Rights Reserved.
    #              Use is subject to license terms.
    #                   Assembled 26 April 2008
    # 

    open(FH, "< $release_file");
    $head = <FH>;

    # Grab the second to last token
    if ($head =~ /(\w+)\s+\w+$/) {
        $ret = $1;
    } else {
        $ret = "unknown";
    }

    return $ret;
}

1;
