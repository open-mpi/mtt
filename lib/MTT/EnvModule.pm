#!/usr/bin/env perl
#
# Copyright (c) 2007 Cisco, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::EnvModule;

# Thin wrapper around the Env::Modulecmd perl module so that we can
# separate the rest of MTT from it and tolerate if it is not
# available.

use strict;

use MTT::Messages;

#--------------------------------------------------------------------------

# See if we've got Env::Modulecmd.
my $_haveit;
eval "\$_haveit = require Env::Modulecmd";

#--------------------------------------------------------------------------

sub _do_error {
    my $action = shift;
    Error("The \"env_module\" field was used in the INI file to $action the \"@_\" module(s), but the Env::Modulecmd perl module was not found.  Please install the EnvModulecmd perl module and try again.  Aborting.\n");
}

#--------------------------------------------------------------------------

sub load {
    _do_error("load", @_)
        if (!$_haveit);

    Env::Modulecmd::load(@_);
}

#--------------------------------------------------------------------------

sub unload {
    _do_error("unload", @_)
        if (!$_haveit);

    Env::Modulecmd::unload(@_);
}


1;
