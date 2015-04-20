#!/usr/bin/perl
#
#
# Copyright (c) 2015      Mellanox Technologies.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#
#


use strict;
use lib '../lib';
use Cwd;
use MTT::Messages;

my $test_var="hello";

MTT::Messages::Messages(1, 1, cwd(), 1);

if(eval "require MTTHooks;") {
    print "Using Hooks\n";
    MTTHooks::on_start();
} else {
    print "No hooks for you\n";
}
