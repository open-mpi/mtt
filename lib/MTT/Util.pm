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
@EXPORT = qw(does_hash_key_exist);

#--------------------------------------------------------------------------

sub does_hash_key_exist {
    my $hash = shift;
    my $key = shift;
    while (defined($key) ) {
        return undef
            if (!exists($hash->{$key}));
        $hash = $hash->{$key};
        $key = shift;
    }
    return $hash;
}

1;
