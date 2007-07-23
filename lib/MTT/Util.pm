#!/usr/bin/env perl
#
# Copyright (c) 2007 Cisco, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Util;

use strict;

use vars qw(@EXPORT);
use base qw(Exporter);
@EXPORT = qw(is_hash_defined);

#--------------------------------------------------------------------------

sub is_hash_defined {
    my $hash = shift;
    my $key = shift;
    while (defined($key) ) {
        return undef
            if (!defined($hash->{$key}));
        $hash = $hash->{$key};
        $key = shift;
    }
    return $hash;
}

1;
