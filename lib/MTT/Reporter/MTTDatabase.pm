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

package MTT::Reporter::MTTDatabase;

use strict;
use Cwd;
use MTT::Messages;
use MTT::Values;
use MTT::Version;
use LWP::UserAgent;
use HTTP::Request::Common qw(POST);
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

# Serial per mtt client invocation
my $invocation_serial_name = "client_serial";
my $invocation_serial_value;

# Do we want debugging?
my $debug_filename;
my $debug_index;

#--------------------------------------------------------------------------

sub Init {
    my ($ini, $section) = @_;

    # Extract data from the ini fields

    $username = Value($ini, $section, "mttdatabase_username");
    $password = Value($ini, $section, "mttdatabase_password");
    $url = Value($ini, $section, "mttdatabase_url");
    $realm = Value($ini, $section, "mttdatabase_realm");
    $debug_filename = Value($ini, $section, "mttdatabase_debug_filename");
    $debug_index = 0;
    if (!$url) {
        Warning("Need URL in MTTDatabase Reporter section [$section]\n");
        return undef;
    }
    my $count = 0;
    ++$count if ($username);
    ++$count if ($password);
    ++$count if ($realm);
    if ($count > 0 && $count != 3) {
        Warning("MTTDatabase Reporter section [$section]: if password, username, or realm is specified, they all must be specified.\n");
        return undef;
    }
    $platform = Value($ini, $section, "mttdatabase_platform");

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
    } elsif  ($host =~ /(https:\/\/[-a-zA-Z0-9.]+):(\d+)\/(.*)$/) {
        $host = $1;
        $port = $2;
        $dir = $3;
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
    $ua->agent("MPI Test MTTDatabase Reporter");
    if ($realm && $username && $password) {
        Verbose("   Set HTTP credentials for realm \"$realm\"\n");
    }

    # Do a test ping to ensure that we can reach this URL

    Debug("MTTDatabase getting a client serial number...\n");
    my $form = {
        SERIAL => 1,
    };
    my $req = POST ($url, $form);
    $req->authorization_basic($username, $password);
    my $response = $ua->request($req);
    if (! $response->is_success()) {
        Warning(">> Failed test ping to MTTDatabase URL: $url\n");
        Warning(">> Error was: " . $response->status_line . "\n" . 
                $response->content);
        Error(">> Do not want to continue with possible bad submission URL -- aborting\n");
    }

    Debug("MTTDatabase got response: " . $response->content . "\n");
    if ($response->content =~ m/===\s+$invocation_serial_name\s+=\s+([0-9]+)\s+===/) {
        $invocation_serial_value = $1;
        Debug("MTTDatabase parsed invocation serial: $invocation_serial_value\n");
    } else {
        Warning("MTTDatabase did not get a serial\n");
    }
    
    # If we have a debug filename, make it an absolute filename,
    # because there's oodles of chdir()'s within the testing.  Whack
    # the file if it's already there.

    if ($debug_filename) {
        if ($debug_filename !~ /\//) {
            $debug_filename = cwd() . "/$debug_filename";
        }
        Debug("MTTDatabase reporter writing to debug file ($debug_filename)\n");
    }

    Debug("MTTDatabase reporter initialized ($realm, $username, XXXXXX, $url, $platform)\n");

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

    Debug("MTTDatabase reporter\n");

    my $successes = 0;
    my @success_outputs;
    my $fails = 0;
    my @fail_outputs;
    my $num_results = 0;

    # Get a bunch of information about this host
    my $id = MTT::Reporter::GetID();

    # Make a default form that will be used to seed all the forms that
    # will be sent
    my $default_form = {
        mtt_version_major => $MTT::Version::Major,
        mtt_version_minor => $MTT::Version::Minor,
    };
    my $phase_serials;
    my $serial_name = $invocation_serial_name;
    my $serial_value = $invocation_serial_value;

    foreach my $k (keys %{$id}) {
        $default_form->{$k} = $id->{$k};
    }

    # Now iterate through all the records that were given to submit
    foreach my $phase (keys(%$entries)) {
        my $phase_obj = $entries->{$phase};

        foreach my $section (keys(%$phase_obj)) {
            my $section_obj = $phase_obj->{$section};

            # Each section of a phase gets its own report to the
            # database.  Make a deep copy of the default form to start
            # with.
            my $form;
            %$form = %{$default_form};

            # Fill in the client serial number
            $form->{$serial_name} = $serial_value;

            # How many results are we submitting?
            $form->{number_of_results} = $#{$section_obj} + 1;
            $form->{platform_name} = $platform;

            # First, go through and union all the field names to come
            # up with a comprehensive list of fields that we're
            # submitting
            my $fields;
            foreach my $result (@$section_obj) {
                foreach my $key (keys(%$result)) {
                    $fields->{$key} = 1;
                }
            }
            $form->{fields} = join(',', sort(keys(%$fields)));
            # JMS: Current brokenness on the server's db scehema:
            # these fields are recorded per result rather than in the
            # "once" table.
            $form->{fields} .= ",start_run_timestamp,submit_test_timestamp";
            $form->{phase} = $phase;

            # Now go through and actually attach all the result to
            # fields in the form
            my $count = 1;
            foreach my $result (@$section_obj) {

                # Go through all the keys in the results
                foreach my $key (keys(%$result)) {

                    # Do not number serial fields (which by convention are
                    # named "name_id")
                    my $name = $key . ($key !~ /_id$/ ? "_" . $count : "");

                    # If the field that has the word "timestamp" in it,
                    # convert it to GMT ctime.
                    if ($key =~ /timestamp/ && $result->{$key} =~ /\d+/) {
                        $form->{$name} = gmtime($result->{$key});
                    } 

                    # We can skip the phase key because it's already
                    # in the top.  
                    elsif ($key eq "phase") {
                        next;
                    }

                    # mpi_name and mpi_version are currently submitted
                    # in the common block at the top of the form
                    # because they're currently in the "once" table on
                    # the server.  This will eventually be fixed.
                    elsif($key eq "mpi_name" || $key eq "mpi_version") {
                        $form->{$key} = $result->{$key};
                    }

                    # Otherwise, just add it unmodified to the form
                    else {
                        $form->{$name} = $result->{$key};
                    }
                }

                # Some other brokenness with the current schema on the
                # server: these fields are recorded with each entry
                # rather than in the once table.  This will also
                # someday be fixed.
                my $name = "start_run_timestamp_$count";
                $form->{$name} = $form->{start_run_timestamp};
                $name = "submit_test_timestamp_$count";
                $form->{$name} = $form->{submit_test_timestamp};

                # Increment and repeat for all results
                ++$count;
            }

            Debug("Submitting to MTTDatabase...\n");
            my $req = POST ($url, $form);
            $req->authorization_basic($username, $password);
            my $response = $ua->request($req);
            if ($response->is_success()) {
                ++$successes;
                push(@success_outputs, $response->content);
            } else {
                Verbose(">> Failed to report to MTTDatabase: " .
                        $response->status_line . "\n" . $response->content);
                ++$fails;
                push(@fail_outputs, $response->content);
            }

            Debug("MTTDatabase got response: " . $response->content . "\n");

            # The following parses the returned serial which will index either
            # an "MPI Install" or a "Test Build"
            if ($response->content =~ m/===\s+(\S+)\s+=\s+([0-9\,]+)\s+===/) {
                eval "\$phase_serials->{$1} = $2;";
                Debug("MTTDatabase parsed serial: $1 = $2\n");
            } else {
                Warning("MTTDatabase did not get a serial; " .
                        "phases will be isolated from each other in the reports\n");
            }

            $num_results += ($count - 1);
            Debug("MTTDatabase submit complete\n");
            
            if ($debug_filename) {
                # Write out what we *would* have sent via HTTP to a
                # file
                my $f = "$debug_filename.$debug_index.txt";
                ++$debug_index;
                Debug("Writing to MTTDatabase debug file: $f\n");
                open OUT, ">$f" || die "Could not open MTTDatabase debug output file";
                print OUT Dumper($form);
                close OUT;
                Debug("Debug MTTDatabase file write complete\n");
                
                push(@success_outputs, "Wrote to file $f\n");
            }
        }
    }

    Verbose(">> $successes successful submit" . plural($successes) . ", $fails failed submit" . plural($fails) . " (total of $num_results result" . plural($num_results) . ")\n");


    return $phase_serials;
}

sub plural {
    my $val = shift;
    ($val == 1) ? "" : "s";
}

1;
