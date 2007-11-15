#!/usr/bin/env perl
#
# Copyright (c) 2007 Sun Microsystems, Inc. All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Values::Functions::SVK;

use strict;
use MTT::Messages;

#--------------------------------------------------------------------------

sub get_mirrored_from_r_number {
    my ($cmd, $depot) = @_;

    my $funclet = '&' . FuncName((caller(0))[3]);
    Debug("$funclet: got @_\n");

    my $svk_cmd = "$cmd info $depot";
    my $out = `$svk_cmd`;

    # Sample output:
    #
    # $ svk info foo
    # Depot Path: foo
    # Revision: 3736
    # Last Changed Rev.: 3732
    # Mirrored From: http://www.acme.com/svn/foo/branches/v1.2, Rev. 16187
    # (In the above example, "16187" is returned)
    my $ret;
    if ($out =~ /\/\S+, \s* Rev. \s* (\d+)/ix) {
        $ret = $1;
    }

    Debug("$funclet returning \n");
    return $ret;
}

1;
