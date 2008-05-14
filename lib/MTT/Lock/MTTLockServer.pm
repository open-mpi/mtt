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

package MTT::Lock::MTTLockServer;

use strict;
use MTT::Values;
use MTT::Messages;
use IO::Socket;

#--------------------------------------------------------------------------

# Universal EOL
my $EOL = "\015\012";

# Connection to server
my $server;

#--------------------------------------------------------------------------

sub Init {
    my ($ini) = @_;

    my $host = MTT::Values::Value($ini, "lock", "mttlockserver_host");
    my $port = MTT::Values::Value($ini, "lock", "mttlockserver_port");
    if (!$host || !$port) {
        Warning("You must specify both an mttlockserver_host and an mttlockserver_port\n");
        return 1;
    }
    Verbose("*** Initializing connection to MTT lock server\n");

    $server = IO::Socket::INET->new(Proto => "tcp",
                                    PeerAddr => $host,
                                    PeerPort => $port);
    if (!$server) {
        Warning("    Unable to open connection to MTT lock server on $host:$port\n");
        return 1;
    }

    # Identify ourselves to the server / verify communication
    my $hostname = `hostname`;
    chomp($hostname);
    my $id = "MTT client on $hostname:$$";
    print $server "$id$EOL";

    # Server should reply
    my $reply = <$server>;
    if ($reply !~ /^Hello $id/) {
        Warning("    Got unexpected response from server: $reply\n");
        close($server);
        return 1;
    }

    # All happy
    Verbose("    MTT lock server connection initialized\n");
    return 0;
}

#--------------------------------------------------------------------------

sub Finalize {
    close($server)
        if ($server);
    $server = undef;
    Verbose("*** MTT lock server connection shut down\n");
    return 0;
}

#--------------------------------------------------------------------------

sub Lock {
    my $name = shift;

    if (!defined($server)) {
        Warning("Attempt to lock '$name' when not connected to server!\n");
        return 1;
    }
    Debug("Locking '$name' on MTT lock server\n");
    
    # Request the lock from the server
    print $server "lock $name$EOL";

    # Get reply back
    my $reply = <$server>;
    if ($reply !~ /Locked $name/) {
        Warning("Got unexpected response from server: $reply\n");
        close($server);
        return 1;
    }

    # All happy
    Debug("Got lock '$name'!\n");
    return 0;
}

#--------------------------------------------------------------------------

sub Unlock {
    my $name = shift;

    if (!defined($server)) {
        Warning("Attempt to unlock '$name' when not connected to server!\n");
        return 1;
    }
    
    # Request the lock from the server
    Debug("Unlocking '$name' on MTT lock server\n");
    print $server "unlock $name$EOL";

    # Get reply back
    my $reply = <$server>;
    if ($reply !~ /Unlocked $name/) {
        Warning("Got unexpected response from server: $reply\n");
        close($server);
        return 1;
    }

    # All happy
    Debug("Unlocked '$name'!\n");
    return 0;
}

#--------------------------------------------------------------------------

1;
