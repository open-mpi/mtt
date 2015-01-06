#!/usr/bin/env perl
#
# Copyright (c) 2006-2010 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::Hooks;

use strict;

use File::Basename;
use Data::Dumper;
use MTT::Values;
use MTT::Messages;


# Hook file that we loaded
my $_file;
my $_prefix;

# These are the hooks that are allowed
my @_hooks = qw/mtt_hook_init mtt_hook_finalize/;


# Load the hooks file
sub init {
    my $ini = shift;

    # If there is a hook .pm file to load, load it now.

    $_file = MTT::Values::Value($ini, "MTT", "hook_file");
    $_prefix = MTT::Values::Value($ini, "MTT", "hook_prefix");
    if (defined($_file)) {
        Error("hook_file defined without hook_prefix")
            if (!defined($_prefix));

        require $_file;
    }
}

# Invoke a hook
sub invoke {
    my $hook = shift;

    # Sanity check to ensure that this is a defined hook.
    my $found = 0;
    foreach my $h (@_hooks) {
        $found = 1
            if ($h eq $hook);
    }
    Error("Tried to invoke undefined hook $hook\n")
        if (0 == $found);

    # Ok, it's s defined hook.  If it exists, invoke it.
    my $func = "$_prefix$hook";
    if (defined(&{$func})) {
        Verbose("*** Invoking hook $func\n");
        eval("$func();");
        return 1;
    }

    Verbose("*** No hook $func; skipping\n");
    return 0;
}

# Close out a hook file
sub finalize {
    # Would be great if we could "un-require" the file here, but I
    # don't see an obvious way to do that.  The only thing I can see
    # to do is to "undef" the hook functions that might exist.

    foreach my $h (@_hooks) {
        undef &{"${_prefix}$h"};
    }

    $_file = undef;
    $_prefix = undef;
}

1;
