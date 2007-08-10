#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2007 Cisco Systems, Inc.  All rights reserved.
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
use MTT::Globals;
use MTT::DoCommand;
use LWP::UserAgent;
use HTTP::Request::Common qw(POST);
use Data::Dumper;
use File::Basename;
use File::Temp qw(tempfile);

# http credentials
my $username;
my $password;
my $realm;
my $url;
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

    # Extract data from the ini fields

    $username = Value($ini, $section, "mttdatabase_username");
    $password = Value($ini, $section, "mttdatabase_password");
    $url = Value($ini, $section, "mttdatabase_url");
    $realm = Value($ini, $section, "mttdatabase_realm");
    $email = Value($ini, $section, "mttdatabase_email_errors_to");
    $debug_filename = Value($ini, $section, "mttdatabase_debug_filename");
    $debug_filename = "mttdatabase_debug" if (! $debug_filename);
    $keep_debug_files = Value($ini, $section, "mttdatabase_keep_debug_files");
    $debug_server = 1 if ($url =~ /\bdebug\b|\bverbose\b/);
    $hostname = Value($ini, $section, "mttdatabase_hostname");
    $local_username = Value($ini, "mtt", "local_username");

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

    # Setup proxies
    my $scheme = (80 == $port) ? "http" : "https";

    # Create the Perl LWP stuff to setup for HTTP requests later.
    # Make one for each proxy (we'll always have at least one proxy
    # entry, even if it's empty).
    my $proxies = \@{$MTT::Globals::Values->{proxies}->{$scheme}};
    foreach my $p (@{$proxies}) {
        my $ua = LWP::UserAgent->new({ env_proxy => 0 });
        
        # @#$@!$# LWP proxying for https *does not work*.  So
        # don't set $ua->proxy() for it.  Instead, we'll set #
        # $ENV{https_proxy} whenever we process requests that
        # require # SSL proxying, because that is obeyed deep down
        # in the # innards underneath LWP.
        $ua->proxy([$scheme], $p->{proxy})
            if ($p->{proxy} ne "" && $scheme ne "https");
        $ua->agent("MPI Test MTTDatabase Reporter");
        push(@lwps, {
            scheme => $scheme,
            agent => $ua,
            proxy => $p->{proxy},
            source => $p->{source},
        });
    }
    if ($realm && $username && $password) {
        Verbose("   Set HTTP credentials for realm \"$realm\"\n");
    }

    # Do a test ping to ensure that we can reach this URL.

    Debug("MTTDatabase getting a client serial number...\n");
    my $form = {
        SERIAL => 1,
    };
    my $req = POST ($url, $form);
    $req->authorization_basic($username, $password);
    my $response = _do_request($req);
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

    # If filename given is relative, branch it off the scratch tree
    if ($debug_filename !~ /\//) {
        $debug_filename = cwd() . "/mttdatabase-submit/$debug_filename";
    }
    MTT::Files::mkdir(dirname($debug_filename));
    Debug("MTTDatabase reporter writing to debug file ($debug_filename)\n");

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
    undef @lwps;
    undef $debug_filename;
    undef $debug_index;

    # Report number of server errors for entire MTT run
    if ($server_errors_total) {
        Warning(">> $server_errors_total total MTTDatabase server error" . 
                _plural($server_errors_total) . "\n" .
                "See the above output for more info.\n");
    }
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
    my $server_errors_count = 0;

    # Make a default form that will be used to seed all the forms that
    # will be sent
    my $default_form = {
        mtt_client_version => $MTT::Version::Combined,
    };
    my $phase_serials;
    my $serial_name = $invocation_serial_name;
    my $serial_value = $invocation_serial_value;

    if ($local_username) {
        $default_form->{local_username} = $local_username;
    } else {
        $default_form->{local_username} = getpwuid($<);
    }

    # Try to get a FQDN
    if (!defined($hostname) || "" eq $hostname) {
        $hostname = `hostname`;
        chomp($hostname);
    }
    Debug("Got hostname: $hostname\n");
    $default_form->{hostname} = $hostname;

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

            # Fill in the trial flag
            $form->{$trial_name} = $MTT::Globals::Values->{trial};

            # How many results are we submitting?
            $form->{number_of_results} = $#{$section_obj} + 1;
            $form->{platform_name} = $platform;
            $form->{email} = $email if ($email);

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

                    elsif($key eq "mpi_name" || $key eq "mpi_version") {
                        $form->{$key} = $result->{$key};
                    }

                    # Otherwise, just add it unmodified to the form
                    else {
                        $form->{$name} = $result->{$key};
                    }
                }

                # Increment and repeat for all results
                ++$count;
            }

            Debug("Submitting to MTTDatabase...\n");
            my ($req, $file) = _prepare_request(\$form);
            my $response = _do_request($$req);
            unlink($file);

            my $sql_error = 0;
            if ($response->is_success()) {
                ++$successes;
                push(@success_outputs, $response->content);
                $sql_error = _count_sql_errors($response->content);
                $server_errors_count += $sql_error;
                $server_errors_total += $server_errors_count;
                Warning($response->content . "\n") if ($sql_error);
                print("\n" . $response->content . "\n") if ($debug_server);
            } else {
                Warning(">> Failed to report to MTTDatabase: " .
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
            
            # Write out what we *would* have sent via HTTP to a
            # file
            my $f;
            if ($sql_error or $keep_debug_files) {
                
                $f = "$debug_filename.$debug_index" .
                        ($sql_error ? "." . time . "-error" : "") . ".txt";
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

    Verbose(">> Reported to MTTDatabase: $successes successful submit" . 
            _plural($successes) .  ", " .
            "$fails failed submit" . _plural($fails) . 
            " (total of $num_results result" . _plural($num_results) . ")\n");

    # Print a hairy warning if there was an SQL error
    if ($server_errors_count) {
        BigWarning("$server_errors_count MTTDatabase server error" .  _plural($server_errors_count),
                   "The data that failed to submit is in $debug_filename.*.txt.",
                   "See the above output for more info.");
    }

    return $phase_serials;
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
        $count++ if ($line =~ /mttdatabase server error/i);
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

    # Go through each ua and try to get a good connection.  If we get
    # connection refused from any of them, try another.
    my $response;
    foreach my $ua (@lwps) {
        Debug("MTTDatabase trying proxy: $ua->{proxy} / $ua->{source}\n");
        $ENV{https_proxy} = $ua->{proxy}
            if ("https" eq $ua->{scheme});

        # Do the HTTP request
        $response = $ua->{agent}->request($req);

        # If it succeeded, or if it failed with something other than
        # code 500, return (code 500 = can't connect)
        if ($response->is_success() ||
            $response->code() != 500) {
            %ENV = %ENV_SAVE;
            return $response;
        }

        # Otherwise, loop around and try again
        Debug("Proxy $ua->{proxy} failed code: " .
              $response->status_line . "\n");
    }

    # Sorry -- nothing got through...
    %ENV = %ENV_SAVE;
    return $response;
}

# Zip up the test results, and prepare the HTTP file upload
# request
sub _prepare_request {
    my $form = shift;

    # Write an anonymous PHP array to a file
    my ($fh, $filename) = tempfile();
    $filename .= ".inc";
    open(FILE, "> $filename");
    print FILE &_perl_arr_2_php_arr(Dumper($$form));
    close(FILE);

    # Zip it (force overwriting of output file)
    my $x = MTT::DoCommand::Cmd(1, "gzip --force $filename");
    $filename .= ".gz";

    # Create the "upload" POST request
    my $req = POST $url,
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

# For the submission hash of data, convert a Perl eval
# string into a PHP eval string
sub _perl_arr_2_php_arr {
    
    my $str = shift;
    my @lines = split /\n|\r/, $str;
    my @ret;

    foreach my $line (@lines) {
        $line =~ s/^\$VAR\d+ = {\s*$/array(/;
        $line =~ s/^\s*};\s*$/)/;

        push(@ret, $line);
    }

    return join("\n", @ret);
}

1;
