#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2008 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2006-2008 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::Reporter::MTTStorage;

use strict;
use MTT::Messages;
use MTT::Values;
use MTT::Version;
use MTT::Globals;
use MTT::DoCommand;
use LWP::UserAgent;
use HTTP::Request::Common qw(POST);
use Data::Dumper;
use File::Basename;
use File::Temp qw(tempfile);

use Data::Dumper;
use JSON;

# http credentials
my $username;
my $password;
my $realm;
my $url;
my $submit_url;
my $status_url;
my $port;

# platform common name
my $platform;

# LWP user agents (one per proxy)
my @lwps;

# Serial per mtt client invocation
my $invocation_serial_name = "client_serial";
my $invocation_serial_value;

# Field for the server; "trial" flag
my $trial_name = "trial";

# Do we want debugging?
my $debug_filename;
my $debug_index;
my $keep_debug_files;
my $debug_server;

# Keep track of SQL errors coming from the server
my $server_errors_total = 0;

# Send SQL errors to this address
my $email;

# Hostname string to report
my $hostname;

# User ID (can be overridden in the INI)
my $local_username;

#--------------------------------------------------------------------------

sub Init {
    my ($ini, $section) = @_;

    # Have we been initialized already?  If so, error -- per #261,
    # this module can currently only handle submitting to one database
    # in a given run.

    if (defined($username)) {
        Error("The MTTStorage plugin can only be used once in an INI file.\n");
    }

    # Extract data from the ini fields

    $username = Value($ini, $section, "mttstorage_username");
    $password = Value($ini, $section, "mttstorage_password");
    $url = Value($ini, $section, "mttstorage_url");
    $realm = Value($ini, $section, "mttstorage_realm");
    $email = Value($ini, $section, "mttstorage_email_errors_to");
    $debug_filename = Value($ini, $section, "mttstorage_debug_filename");
    $debug_filename = "mttstorage_debug" if (! $debug_filename);
    $keep_debug_files = Value($ini, $section, "mttstorage_keep_debug_files");
    $debug_server = 1 if ($url =~ /\bdebug\b|\bverbose\b/);
    $debug_server = Logical($ini, $section, "mttstorage_debug_server")
        if (1 != $debug_server);
    $hostname = Value($ini, $section, "mttstorage_hostname");
    $local_username = Value($ini, "mtt", "local_username");

    $debug_index = 0;
    if (!$url) {
        Warning("Need URL in MTTStorage Reporter section [$section]\n");
        return undef;
    }

    my $count = 0;
    ++$count if ($username);
    ++$count if ($password);
    ++$count if ($realm);
    if ($count > 0 && $count != 3) {
        Warning("MTTStorage Reporter section [$section]: if password, username, or realm is specified, they all must be specified.\n");
        return undef;
    }
    $platform = Value($ini, $section, "mttstorage_platform");

    # Extract the host and port from the URL.  Needed for the
    # credentials section.

    my $dir;
    my $host = $url;
    if ($host =~ /(http:\/\/[-a-zA-Z0-9.]+):(\d+)\/?(.*)?$/) {
        $host = $1;
        $port = $2;
        $dir = $3;
    } elsif ($host =~ /(http:\/\/[-a-zA-Z0-9.]+)\/?(.*)?$/) {
        $host = $1;
        $dir = $2;
        $port = 80;
    } elsif ($host =~ /(https:\/\/[-a-zA-Z0-9.]+)\/?(.*)?$/) {
        $host = $1;
        $dir = $2;
        $port = 443;
    } elsif ($host =~ /(https:\/\/[-a-zA-Z0-9.]+):(\d+)\/?(.*)?$/) {
        $host = $1;
        $port = $2;
        $dir = $3;
    } else {
        Warning("MTTStorage Reporter did not get a valid url: $url .\n");
        return undef;
    }
    $url = "$host:$port/$dir";

    $submit_url = $url . "/submit";
    $status_url = $url . "/serial";

    # Setup proxies
    my $scheme = (80 == $port) ? "http" : "https";

    # Create the Perl LWP stuff to setup for HTTP requests later.
    # Make one for each proxy (we'll always have at least one proxy
    # entry, even if it's empty).
    my $proxies = \@{$MTT::Globals::Values->{proxies}->{$scheme}};
    if (defined($proxies)) {
        foreach my $p (@{$proxies}) {
            my %params = { env_proxy => 0 };
            my $ua = LWP::UserAgent->new(%params);

            # @#$@!$# LWP proxying for https *does not work*.  So
            # don't set $ua->proxy() for it.  Instead, we'll set
            # $ENV{https_proxy} whenever we process requests that
            # require SSL proxying, because that is obeyed deep down
            # in the innards underneath LWP.
            $ua->proxy([$scheme], $p->{proxy})
                if ($p->{proxy} ne "" && $scheme ne "https");
            $ua->agent("MPI Test MTTStorage Reporter");
            push(@lwps, {
                scheme => $scheme,
                agent => $ua,
                proxy => $p->{proxy},
                source => $p->{source},
                 });
        }
    } else {
        my %params = { env_proxy => 0 };
        my $ua = LWP::UserAgent->new(%params);
        push(@lwps, {
            scheme => $scheme,
            agent => $ua,
             });
    }
    if ($realm && $username && $password) {
        Verbose("   Set HTTP credentials for realm \"$realm\"\n");
    }

    # Do a test ping to ensure that we can reach this URL.

    Debug("MTTStorage client getting a client serial number...\n");
    $invocation_serial_value = _get_client_serial();

    # If we have a debug filename, make it an absolute filename,
    # because there's oodles of chdir()'s within the testing.  Whack
    # the file if it's already there.

    # If filename given is relative, branch it off the scratch tree
    if ($debug_filename !~ /\//) {
        $debug_filename = MTT::DoCommand::cwd() .
            "/mttstorage-submit/$debug_filename";
    }
    MTT::Files::mkdir(dirname($debug_filename));
    Debug("MTTStorage reporter writing to debug file ($debug_filename)\n");

    Debug("MTTStorage reporter initialized ($realm, $username, XXXXXX, $url, $platform)\n");

    return 1;
}

#--------------------------------------------------------------------------

sub Finalize {
    undef $username;
    undef $password;
    undef $realm;
    undef $url;
    undef $submit_url;
    undef $status_url;
    undef $platform;
    undef @lwps;
    undef $debug_filename;
    undef $debug_index;

    # Report number of server errors for entire MTT run
    if ($server_errors_total) {
        Warning(">> $server_errors_total total MTTStorage server error" .
                _plural($server_errors_total) . "\n" .
                "See the above output for more info.\n");
    }
}

#--------------------------------------------------------------------------

sub Submit {
    my ($info, $entries) = @_;

    Debug("MTTStorage reporter submit\n");

    my $successes = 0;
    my @success_outputs;
    my $fails = 0;
    my @fail_outputs;
    my $num_results = 0;
    my $server_errors_count = 0;

    # Make a default form that will be used to seed all the forms that
    # will be sent
    my $default_form = {
        metadata => {
            mtt_client_version => $MTT::Version::Combined,
        }
    };
    my $phase_serials;
    my $serial_name = $invocation_serial_name;
    my $serial_value = $invocation_serial_value;

    if ($local_username) {
        $default_form->{metadata}->{local_username} = $local_username;
    } else {
        $default_form->{metadata}->{local_username} = getpwuid($<);
    }

    # Try to get a FQDN
    if (!defined($hostname) || "" eq $hostname) {
        $hostname = `hostname`;
        chomp($hostname);
    }
    Debug("Got hostname: $hostname\n");
    $default_form->{metadata}->{hostname} = $hostname;

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
            $form->{metadata}->{$serial_name} = $serial_value;

            # Fill in the trial flag
            $form->{metadata}->{$trial_name} = $MTT::Globals::Values->{trial};

            # How many results are we submitting?
            $form->{metadata}->{platform_name} = $platform;
            $form->{metadata}->{email} = $email if ($email);
            $form->{metadata}->{phase} = $phase;

            # Now go through and actually attach all the result to
            # fields in the form
            my $count = 1;
            # print "-"x70 . "\n";
            # print Dumper(@$section_obj);
            # print "-"x70 . "\n";
            # print Dumper( JSON->new->pretty->encode($section_obj) );
            # print "-"x70 . "\n";

            #
            # Cleanup the data before submitting
            #
            my @all_data = ();
            my $submit_id = -1;
            foreach my $result (@$section_obj) {

                my $data;
                # Go through all the keys in the results
                foreach my $key (keys(%$result)) {

                    # Do not number serial fields (which by convention are
                    # named "name_id")
                    my $name = $key;

                    # If the field that has the word "timestamp" in it,
                    # convert it to GMT ctime.
                    if ($key =~ /timestamp/) {

                        # If we have an epoch timestamp (raw seconds from 1970-01-01)
                        # convert to MTTStorage format (e.g., Postgres)
                        if ($result->{$key} =~ /^\s*\d+\s*$/) {
                            $data->{$name} = gmtime($result->{$key});
                            # Otherwise, assume the timestamp is already in MTTStorage format
                        } else {
                            $data->{$name} = $result->{$key};
                        }
                    }

                    # If we want to skip this 'key' (internal, unused keys)
                    elsif ( if_exclude_key($key) == 1 ) {
                        next;
                    }

                    # If this key's value is really an integer
                    elsif ( if_is_int($key) == 1 ) {
                        $data->{$key} = int($result->{$key});
                        next;
                    }

                    # If this is the submit_id, then we put it in the metadata
                    elsif ($key eq "submit_id") {
                        $submit_id = int($result->{$key});
                        next;
                    }

                    # Stringify any array references
                    elsif (ref($result->{$key}) =~ /array/i) {
                        #$data->{$key} = join("\n\n---\n\n", @{$result->{$key}});
                        $data->{$key} = $result->{$key};
                    }

                    # Stringify any hash references
                    elsif (ref($result->{$key}) =~ /hash/i) {
                        #my $str = Dumper($result->{$key});
                        #$str =~ s/\$VAR1 = /        /;
                        #$data->{$key} = $str;
                        $data->{$key} = $result->{$key};
                    }

                    # Otherwise, just add it unmodified to the form
                    else {
                        $data->{$name} = $result->{$key};
                    }
                }
                push(@all_data, $data);
            }

            if( $submit_id > 0 ) {
                $form->{metadata}->{submit_id} = $submit_id;
            }

            $form->{data} = \@all_data;
            #print Dumper( JSON->new->pretty->encode($form) );

            _debug("Submitting to MTTStorage...\n");

            my ($req, $file) = _prepare_request(\$form);
            my $response = _do_request($$req);
            if( 0 != length($file) ) {
                unlink($file);
            }

            my $sql_error = 0;
            if ($response->is_success()) {
                _debug("MTTStorage response is a success\n");
                ++$successes;

                push(@success_outputs, $response->content);

                _debug("MTTStorage client got response: \n");
                _debug("RAW: " . $response->content . "\n");
                Debug(Dumper(JSON->new->pretty->decode( $response->content )));
            } else {
                Warning(">> Failed to report to MTTStorage: " .
                        $response->status_line . "\n" .
                        ">> Content: " . $response->content);
                ++$fails;
                push(@fail_outputs, $response->content);
            }

            my $resp = JSON->new->decode( $response->content );

            if( $resp->{status} != 0 ) {
                _debug("MTTStorage: Returned error code ".$resp->{status}."\n");
                _debug("MTTStorage: Error Message: ".$resp->{status_message}."\n");
                Error(">> Server failed to process the message -- aborting\n");
            }

            # The following parses the returned serial which will index either
            # an "MPI Install" or a "Test Build"
            my $key_id = "submit_id";
            $phase_serials->{$key_id} = $resp->{$key_id};
            _debug("MTTStorage client parsed serial: (".$key_id.") = (".$phase_serials->{$key_id}.")\n");

            my %hids = %{ @{ $resp->{ids} }[0] };
            my $key_id = (keys(%hids))[0];
            $phase_serials->{$key_id} = $resp->{ids}[0]{$key_id};
            _debug("MTTStorage client parsed serial: (".$key_id.") = (".$phase_serials->{$key_id}.")\n");


            $num_results += ($count - 1);
            _debug("MTTStorage client submit complete\n");

            # Write out what we *would* have sent via HTTP to a
            # file
            my $f;
            if ($sql_error or $keep_debug_files) {

                $f = "$debug_filename.$debug_index" .
                    ($sql_error ? "." . time . "-error" : "") . ".txt";
                ++$debug_index;
                Debug("Writing to MTTStorage client debug file: $f\n");
                open OUT, ">$f" || die "Could not open MTTStorage client debug output file";
                print OUT Dumper($form);
                close OUT;
                Debug("Debug MTTStorage client file write complete\n");

                push(@success_outputs, "Wrote to file $f\n");
            }
        }
    }

    Verbose(">> Reported to MTTStorage client: $successes successful submit" .
            _plural($successes) .  ", " .
            "$fails failed submit" . _plural($fails) .
            " (total of $num_results result" . _plural($num_results) . ")\n");

    # Print a hairy warning if there was an SQL error
    if ($server_errors_count) {
        BigWarning("$server_errors_count MTTStorage server error" .  _plural($server_errors_count),
                   "The data that failed to submit is in $debug_filename.*.txt.",
                   "See the above output for more info.");
    }

    return $phase_serials;
}

sub if_exclude_key {
    my $key = shift;
    my @exclude_list = ("phase",
                        "already_saved_to",
                        "variant");
    foreach my $k (@exclude_list) {
        if( $key eq $k ) {
            return 1;
        }
    }

    return 0;
}

sub if_is_int {
    my $key = shift;
    my @exclude_list = ("bitness",
                        "endian",
                        "merge_stdout_stderr",
                        "vpath_mode",
                        "test_result",
                        "submit_id",
                        "mpi_install_id",
                        "test_build_id",
                        "test_run_id",
                        "exit_signal",
                        "exit_value");
    foreach my $k (@exclude_list) {
        if( $key eq $k ) {
            return 1;
        }
    }

    return 0;
}

sub _plural {
    my $val = shift;
    ($val == 1) ? "" : "s";
}

# Count the number of database server errors
sub _count_sql_errors {
    my($str) = @_;
    my @lines = split(/\n|\r/, $str);
    my $line;
    my $count = 0;

    while (defined($line = shift @lines)) {
        $count++ if ($line =~ /mttstorage server error/i);
    }
    return $count;
}

#--------------------------------------------------------------------------

sub _do_request {
    my $req = shift;

    # Ensure that the environment is clean so that nothing happens
    # that we're unaware of.
    my %ENV_SAVE = %ENV;
    delete $ENV{http_proxy};
    delete $ENV{https_proxy};
    delete $ENV{HTTP_PROXY};
    delete $ENV{HTTPS_PROXY};

    # Go through each ua and try to get a good connection.
    # If we get connection refused from any of them, try another.
    my $response;
    my $num_retries = 0;
    while ( $num_retries <= 16 ) {
        foreach my $ua (@lwps) {
            _debug("MTTStorage client trying proxy: $ua->{proxy} / $ua->{source}\n");
            $ENV{https_proxy} = $ua->{proxy}
            if ("https" eq $ua->{scheme});

            # Do the HTTP request
            $response = $ua->{agent}->request($req);

            # If it succeeded, or if it failed with something other than
            # code 500, return (code 500 = can't connect)
            if ($response->is_success() ||
                $response->code() != 500) {
                _debug("MTTStorage proxy successful / not 500\n");
                %ENV = %ENV_SAVE;
                return $response;
            }
            _debug("MTTStorage proxy unsuccessful -- trying next\n");

            # Otherwise, loop around and try again
            Debug("Proxy $ua->{proxy} failed code: " .
                  $response->status_line . "\n");
        }
        # If all failed, retry them all a few times with increasing sleep
        # before giving up for good.
        Warning(">> Failed to submit results... retrying...");
        $num_retries++;
        sleep (4 * $num_retries);
    }
    # Sorry -- nothing got through...
    _debug("MTTStorage proxy totally unsuccessful\n");
    %ENV = %ENV_SAVE;
    return $response;
}

#--------------------------------------------------------------------------

sub _prepare_request {
    my $form = shift;

    # Create the "upload" POST request
    my $req = POST $submit_url;

    $req->header( 'Content_Type' => 'application/json' );
    $req->content( JSON->new->pretty->encode($$form) );
    $req->authorization_basic($username, $password);

    my $filename = "none";

    return (\$req, $filename);
}

# Zip up the test results, and prepare the HTTP file upload
# request
sub _prepare_request_zip {
    my $form = shift;

    # Find a temporary directory for the .inc files
    my $tmpdir;
    if (defined($ENV{TMPDIR})) {
        $tmpdir = $ENV{TMPDIR};
    } else {
        $tmpdir = "/tmp";
    }
    MTT::Files::mkdir($tmpdir);

    # Write an anonymous PHP array to a file
    my ($fh, $filename) = tempfile(
        DIR    => $tmpdir,
        SUFFIX => "-mttstorage-submission.inc"
        );
    open(FILE, "> $filename");
    print FILE &_perl_arr_2_php_arr(Dumper($$form));
    close(FILE);

    # Zip it (force overwriting of output file)
    my $x = MTT::DoCommand::Cmd(1, "gzip --force $filename");
    $filename .= ".gz";

    # Create the "upload" POST request
    my $req = POST $submit_url,
    Content_Type => 'form-data',
    Content => [
        pageAction     => 'upload',
        userfile       => [$filename],
        newTitle       => $filename,
        newCategory    => 'Open MPI',
        newDescription => 'MTT Results Submission'
        ];

    $req->authorization_basic($username, $password);

    return (\$req, $filename);
}

#--------------------------------------------------------------------------

# For the submission hash of data, convert a Perl eval
# string into a PHP eval string
sub _perl_arr_2_php_arr {

    my $str = shift;
    my @lines = split /\n|\r/, $str;
    my @ret;

    foreach my $line (@lines) {
        $line =~ s/^\$VAR\d+ = \{\s*$/array(/;
        $line =~ s/^\s*\};\s*$/)/;

        push(@ret, $line);
    }

    return join("\n", @ret);
}

#--------------------------------------------------------------------------

sub _debug {
    $debug_server ? Verbose(@_) : Debug(@_);
}

#--------------------------------------------------------------------------

sub _get_client_serial() {
    my $serial_value;

    #
    # GET SERIAL
    #
    my $form = { SERIAL => 1 };
    my $req = POST $status_url;

    $req->header( 'Content_Type' => 'application/json' );
    $req->content( JSON->new->pretty->encode($form) );
    $req->authorization_basic($username, $password);

    my $response = _do_request($req);
    if (! $response->is_success()) {
        Warning(">> Failed test ping to MTTStorage URL: $url\n");
        Warning(">> Error was: " . $response->status_line . "\n" .
                $response->content);
        Error(">> Do not want to continue with possible bad submission URL -- aborting\n");
        # Does not reach here
    }

    #
    # Parse response
    #
    Debug("MTTStorage client got response: \n");
    Debug("RAW: " . $response->content . "\n");
    Debug(Dumper(JSON->new->pretty->decode( $response->content )));

    my $json_packet = JSON->new->pretty->decode( $response->content );
    my $serial = $json_packet->{client_serial};
    Debug("MTTStorage serial = (".$serial.")\n");
    $serial_value = int($serial);

    #
    # Done
    #
    return $serial_value;
}
1;
