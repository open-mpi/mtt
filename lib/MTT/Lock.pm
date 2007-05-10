#!/usr/bin/env perl
#
# Copyright (c) 2007      Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

########################################################################

package MTT::Lock;

use strict;
use MTT::Module;
use MTT::Values;
use MTT::Messages;

#--------------------------------------------------------------------------

# Which module was selected for use
my $module;

#--------------------------------------------------------------------------

use Data::Dumper;

sub Init {
    my ($ini) = @_;

    return 0
        if (!$ini->SectionExists("lock"));
    $module = MTT::Values::Value($ini, "lock", "module");
    return 0
        if (!defined($module));

    my $ret = MTT::Module::Run("MTT::Lock::$module", "Init", $ini, "lock");
    Error("Lock module failed to initialize\n")
        if (0 != $ret);
    Debug("Lock module initialized: $module\n");
    return $ret;
}

#--------------------------------------------------------------------------

sub Finalize {
    return 0
        if (!defined($module));
    my $ret = MTT::Module::Run("MTT::Lock::$module", "Finalize");
    Debug("Lock module finalized: $module\n");
    $module = undef;
    return $ret;
}

#--------------------------------------------------------------------------

sub Lock {
    my ($name) = @_;
    Debug("Locking: $name\n");

    # No-op if no lock module was chosen
    return 0
        if (!defined($module));

    MTT::Module::Run("MTT::Lock::$module", "Lock", @_);
}

#--------------------------------------------------------------------------

sub Unlock {
    my ($name) = @_;
    Debug("Unlocking: $name\n");

    # No-op if no lock module was chosen
    return 0
        if (!defined($module));

    MTT::Module::Run("MTT::Lock::$module", "Unlock", @_);
}

#--------------------------------------------------------------------------

1;
