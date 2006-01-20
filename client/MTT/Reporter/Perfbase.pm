#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Reporter::Perfbase;

use strict;
use MTT::Messages;
use MTT::Values;
use LWP::UserAgent;
use Data::Dumper;

# http credentials
my $username;
my $password;
my $realm;
my $url;

# platform common name
my $platform;

# LWP user agent
my $ua;

#--------------------------------------------------------------------------

sub Init {
    my ($ini, $section) = @_;

    # Extract data from the ini fields

    $username = Value($ini, $section, "username");
    $password = Value($ini, $section, "password");
    $url = Value($ini, $section, "url");
    $realm = Value($ini, $section, "realm");
    if (!$username || !$password || !$url || !$realm) {
        Warning("Not enough information in Perfbase Reporter section [$section]; must have username, password, url, and realm; skipping this section");
        return undef;
    }
    $platform = Value($ini, $section, "platform");

    # Extract the host and port from the URL.  Needed for the
    # credentials section.

    my $port;
    my $host = $url;
    if ($host =~ /http:\/\/([a-zA-Z0-9.]+):(\d+)/) {
        $host = $1;
        $port = $2;
    } elsif ($host =~ /http:\/\/([a-zA-Z0-9.]+)/) {
        $host = $1;
        $port = 80;
    } elsif ($host =~ /https:\/\/([a-zA-Z0-9.]+)/) {
        $host = $1;
        $port = 443;
    } else {
        return undef;
    }

    # Create the Perl LWP stuff to setup for HTTP PUT's later

    $ua = LWP::UserAgent->new({ env_proxy => 1 });
    $ua->agent("MPI Test Perfbase Reporter");
    $ua->credentials("$host:$port", $realm, $username, $password);

    Debug("Perfbase reporter initialized ($realm, $username, XXXXXX, $url, $platform)\n");

    1;
}

#--------------------------------------------------------------------------

sub Submit {
    my ($info, $entries) = @_;

    Debug("Perfbase reporter\n");

    foreach my $entry (@$entries) {
        my $phase = $entry->{phase};
        my $section = $entry->{section};
        my $report = $entry->{report};

        $report->{platform_id} = $platform;

        # JMS: Right now we're assuming two HTTP form fields:
        # value: the big old string
        # xml: the name of the xml file to use in perfbase
        # Need to coordinate with BA on this...
        my $form = {
            value => MTT::Reporter::MakeReportString($report),
            # totally bogus value
            xml => "compile.xml",
        };

        # Do the post and get the response.

        my $response = $ua->post($url, $form);
        if ($response->is_success()) {
            print "Success!\n";
            print $response->content;
        } else {
            print "Failure: " . $response->status_line . "\n";
        }
    }
}

1;
