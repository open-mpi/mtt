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
package MTTHooks;

use MTT::Messages;

use strict;

sub run_ext_hooks()
{
    my ($hook_file) = (@_);
    my @hooks_dirs;
    push @hooks_dirs, $ENV{'HOME'}    if defined $ENV{'HOME'};
    push @hooks_dirs, $ENV{'MTT_LIB'} if defined $ENV{'MTT_LIB'};

    foreach my $hook (@hooks_dirs) {
        my $hfile="$hook/$hook_file";

        MTT::Messages::Verbose("Checking $hfile\n");

        if ( -f $hfile) {
            MTT::Messages::Verbose("Loading hook $hfile\n");
            my $cmd = `cat $hfile`;
            MTT::Messages::Verbose("hook: $cmd\n");
            eval($cmd);
        } else {
            MTT::Messages::Verbose("no hook in $hfile\n");
        }
    }
}

# access global MTT vars defined with 'our' keyword by $main::var
sub on_start  
{
    MTT::Messages::Verbose("Hook on start\n");
    &run_ext_hooks(".mtt_on_start");
}

sub on_stop
{
    MTT::Messages::Verbose("Hook on stop\n");
    &run_ext_hooks(".mtt_on_stop");
}

1;
