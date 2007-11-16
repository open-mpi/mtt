#!/usr/bin/env perl
#
# Copyright (c) 2007 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Reporter::IRC;
my $package = __PACKAGE__;

use strict;
use IO::Socket;
use MTT::Messages;
use MTT::Values;
use Data::Dumper;

# INI globals
my $ini;
my $section;

# IRC globals
my $bot_name;
my $server_name;
my $server_port;
my $nick;
my $channel;
my $message_val;

#--------------------------------------------------------------------------

sub Init {
    ($ini, $section) = @_;

    # Extract data from the ini fields
    $bot_name = Value($ini, $section, "irc_bot_name");
    $server_name = Value($ini, $section, "irc_server_name");
    $server_port = Value($ini, $section, "irc_server_port");
    $nick = Value($ini, $section, "irc_nick");
    $channel = Value($ini, $section, "irc_channel");

    # Delay the evaluation of the message so it is relevant to
    # when it is sent (e.g., if it messages the current time)
    $message_val = $ini->val($section, "irc_message");

    if (!$server_name) {
        Error("Need to specify an irc_server_name.\n");
        return undef;
    }

    my $default_bot_name = "mtt-bot";
    if (!$bot_name) {
        Warning("$default_bot_name will be the name of the agent sending the IRC message.\n");
        $bot_name = $default_bot_name;
    }

    if (!$nick and !$channel) {
        Error("Need to specify an irc_nick or an irc_channel to message to.\n");
        return undef;
    }

    my $default_port = 6667;
    if (!$server_port) {
        Warning("Defaulting irc_server_port to $default_port\n");
        $server_port = $default_port;
    }

    Debug("$package reporter initialized.\n");
}

#--------------------------------------------------------------------------

sub Finalize {
    undef $message_val;
}

#--------------------------------------------------------------------------

# Send the message then leave
sub Submit {
    my ($info, $entries) = @_;

    # Prepare the message to be sent
    my $message = EvaluateString($message_val, $ini, $section);

    # Do not print a blank message
    return if (! $message);

    # Connect to the server
    my $sock = new IO::Socket::INET(
        PeerAddr => $server_name,
        PeerPort => $server_port,
        Proto => 'tcp'
    ) or warn "Can't connect $!\n";

    # Log on
    print $sock "NICK $bot_name\r\n";
    print $sock "USER $bot_name 8 * :MTT IRC robot\r\n\r\n";

    # Message a #channel
    if ($channel) {
        print $sock "JOIN $channel\r\n";
        print $sock "PRIVMSG $channel :$message\r\n";
    }

    # Message a user
    if ($nick) {
        print $sock "PRIVMSG $nick :$message\r\n";
    }
}

1;
