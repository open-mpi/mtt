#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2006      Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Reporter::Perfbase;

use strict;
use Cwd;
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
my $port;

# platform common name
my $platform;

# LWP user agent
my $ua;

# Do we want debugging?
my $debug_filename;
my $debug_index;

#--------------------------------------------------------------------------

sub Init {
    my ($ini, $section) = @_;

    # Extract data from the ini fields

    $username = Value($ini, $section, "perfbase_username");
    $password = Value($ini, $section, "perfbase_password");
    $url = Value($ini, $section, "perfbase_url");
    $realm = Value($ini, $section, "perfbase_realm");
    $debug_filename = Value($ini, $section, "perfbase_debug_filename");
    $debug_index = 0;
    if (!$url) {
        Warning("Need URL in Perfbase Reporter section [$section]\n");
        return undef;
    }
    my $count = 0;
    ++$count if ($username);
    ++$count if ($password);
    ++$count if ($realm);
    if ($count > 0 && $count != 3) {
        Warning("Perfbase Reporter section [$section]: if password, username, or realm is specified, they all must be specified.\n");
        return undef;
    }
    $platform = Value($ini, $section, "perfbase_platform");

    # Extract the host and port from the URL.  Needed for the
    # credentials section.

    my $dir;
    my $host = $url;
    if ($host =~ /(http:\/\/[-a-zA-Z0-9.]+):(\d+)\/(.*)$/) {
        $host = $1;
        $port = $2;
        $dir = $3;
    } elsif ($host =~ /(http:\/\/[-a-zA-Z0-9.]+)\/(.*)$/) {
        $host = $1;
        $dir = $2;
        $port = 80;
    } elsif ($host =~ /(https:\/\/[-a-zA-Z0-9.]+)\/(.*)$/) {
        $host = $1;
        $dir = $2;
        $port = 443;
    } else {
        return undef;
    }
    $url = "$host:$port/$dir";

    # Look for the proxy server in the environment,
    # and take the first one we find
    my $proxy;
    foreach my $p (grep(/http_proxy/i, keys %ENV)) {
        if ($ENV{$p}) {
            $proxy = $ENV{$p};
            $proxy = "http://$proxy" if ($proxy !~ /https?:/);
            last;
        }
    }

    # Create the Perl LWP stuff to setup for HTTP PUT's later

    $ua = LWP::UserAgent->new();
    $ua->proxy(['http', 'ftp'], $proxy);
    $ua->agent("MPI Test Perfbase Reporter");
    if ($realm && $username && $password) {
        Verbose("   Set HTTP credentials for realm \"$realm\"\n");
        $ua->credentials("$host:$port", $realm, $username, $password);
    }

    # If we have a debug filename, make it an absolute filename,
    # because there's oodles of chdir()'s within the testing.  Whack
    # the file if it's already there.

    if ($debug_filename) {
        if ($debug_filename !~ /\//) {
            $debug_filename = cwd() . "/$debug_filename";
        }
        Debug("Perfbase reporter writing to debug file ($debug_filename)\n");
    }

    Debug("Perfbase reporter initialized ($realm, $username, XXXXXX, $url, $platform)\n");

    1;
}

#--------------------------------------------------------------------------

sub Finalize {
    undef $username;
    undef $password;
    undef $realm;
    undef $url;
    undef $platform;
    undef $ua;
    undef $debug_filename;
    undef $debug_index;
}

#--------------------------------------------------------------------------

sub Submit {
    my ($info, $entries) = @_;

    Debug("Perfbase reporter\n");

    my $successes = 0;
    my @success_outputs;
    my $fails = 0;
    my @fail_reasons;

    foreach my $phase (keys(%$entries)) {
        my $phase_obj = $entries->{$phase};

        foreach my $section (keys(%$phase_obj)) {
            my $section_obj = $phase_obj->{$section};

            foreach my $report_original (@$section_obj) {
                # Ensure to do a deep copy of the report (vs. just
                # copying the reference) because we want to locally
                # change some values
                my $report;
                %$report = %{$report_original};

                $report->{platform_id} = $platform;
                my $xml = $report->{perfbase_xml};
                if ($xml) {

                    # Add our version number into the report; saved
                    # for posterity with the results.

                    $report->{mtt_version_major} = $MTT::Version::Major;
                    $report->{mtt_version_minor} = $MTT::Version::Minor;

                    # Perbase doesn't seem to understand epoch
                    # timestamps.  So go find any field that has the
                    # word "timestamp" in it and convert it to GMT
                    # ctime.
                    foreach my $key (keys(%$report)) {
                        if ($key =~ /timestamp/ && $report->{$key} =~ /\d+/) {
                            $report->{$key} = gmtime($report->{$key});
                        }
                    }

                    # Make a big string.  We only need to escape the
                    # use of '.
                    my $str = MTT::Reporter::MakeReportString($report, ": ");
                    $str =~ s/'/\\'/g;

                    # Make the string to send, using ": " as the
                    # delimiter (this is important -- the server-side
                    # XML files are setup to use these ***2***
                    # characters as the delimiter # between the field
                    # and the data
                    my $form = {
                        # Version number is also submitted as part of
                        # the HTTP form so that the server can check
                        # it directly (without understanding the
                        # perfbase XML).

                        MTTVERSION_MAJOR => $MTT::Version::Major,
                        MTTVERSION_MINOR => $MTT::Version::Minor,
                        PBINPUT => $str,
                        PBXML => $xml,
                    };
                    
                    if ($url) {
                        # Do the post and get the response.
                        
                        Debug("Submitting to perfbase...\n");
                        my $response = $ua->post($url, $form);
                        if ($response->is_success()) {
                            ++$successes;
                            push(@success_outputs, $response->content);
                        } else {
                            Verbose(">> Failed to report to perfbase: " .
                                    $response->status_line . "\n" . $response->content);
                        }
                        Debug("Perfbase submit complete\n");
                    }

                    if ($debug_filename) {
                        # Write out what we *would* have sent via HTTP to a
                        # file
                        
                        my $f = "$debug_filename.$debug_index.txt";
                        ++$debug_index;
                        Debug("Writing to perfbase debug file: $f\n");
                        open OUT, ">$f" || die "Could not open Perfbase debug output file";
                        print OUT Dumper($form);
                        close OUT;
                        Debug("Debug perfbase file write complete\n");

                        ++$successes;
                        push(@success_outputs, "Wrote to file $f\n");
                    }
                } else {
                    Warning("No perfbase_xml field in the INI specification; skipping perfbase reporting!\n");
                }
            }
        }
    }

    if ($successes > 0) {
        if ($fails == 0) {
            Verbose(">> Reported $successes output(s) to perfbase\n");
            Debug(@success_outputs);
        }
    }
}

1;
