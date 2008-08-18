#!/usr/bin/env perl
#
# Copyright (c) 2007 Sun Microsystems, Inc. All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Values::Functions::SVN;

use strict;
use MTT::Messages;
use Data::Dumper;

#--------------------------------------------------------------------------

sub get_r_number {
    my ($cmd) = @_;

    my $funclet = '&' . FuncName((caller(0))[3]);
    Debug("$funclet: got @_\n");

    $cmd = "svn info" if (!defined($cmd));
    my $out = `$cmd`;

    # Sample output:
    #
    # $ svn info /foo/bar
    # Path: /foo/bar
    # URL: http://svn.acme.org/svn/whizzbang/trunk
    # Repository Root: http://svn.acme.org/svn/whizzbang
    # Repository UUID: 63e3feb5-37d5-0310-a306-e8a459e722fe
    # Revision: 16772
    # Node Kind: directory
    # Schedule: normal
    # Last Changed Author: wiley-coyote
    # Last Changed Rev: 16772
    # Last Changed Date: 2007-11-21 16:37:58 -0500 (Wed, 21 Nov 2007)

    my $ret;
    if ($out =~ /Revision: \s* (\d+)/ix) {
        $ret = $1;
    }

    Debug("$funclet returning \n");
    return $ret;
}

1;
