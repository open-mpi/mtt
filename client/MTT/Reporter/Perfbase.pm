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
use MTT::Version;
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

    my $successes = 0;
    my @success_outputs;
    my $fails = 0;
    my @fail_reasons;
    foreach my $entry (@$entries) {
        my $phase = $entry->{phase};
        my $section = $entry->{section};
        my $report = $entry->{report};

        $report->{platform_id} = $platform;
        my $xml = $report->{perfbase_xml};
        if ($xml) {

            # Add our version number into the report; saved for
            # posterity with the results.

            $report->{mtt_version_major} = $MTT::Version::Major;
            $report->{mtt_version_minor} = $MTT::Version::Minor;

            # Make the string to send, using ": " as the delimiter
            # (this is important -- the server-side XML files are
            # setup to use these ***2*** characters as the delimiter
            # between the field and the data

            my $form = {
                # Version number is also submitted as part of the HTTP
                # form so that the server can check it directly
                # (without understanding the perfbase XML).
                MTTVERSION_MAJOR => $MTT::Version::Major,
                MTTVERSION_MINOR => $MTT::Version::Minor,
                PBINPUT => MTT::Reporter::MakeReportString($report, ": "),
                PBXML => $xml,
            };

            # Do the post and get the response.

            my $response = $ua->post($url, $form);
            if ($response->is_success()) {
                ++$successes;
                push(@success_outputs, $response->content);
            } else {
                Verbose(">> Failed to report to perfbase: " .
                        $response->status_line . "\n");
            }
        }
    }

    if ($successes > 0) {
        if ($fails == 0) {
            Verbose(">> Reported $successes outputs to perfbase\n");
            Debug(@success_outputs);
        }
    }
}

1;
