#!/usr/bin/env perl
#
# Copyright (c) 2007-2008 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Common::SCM::SVN;
my ($package) = (__PACKAGE__ =~ m/(\w+)$/);

use strict;
use MTT::Messages;
use MTT::Values;
use MTT::Files;
use MTT::DoCommand;
use Data::Dumper;

#--------------------------------------------------------------------------

sub Checkout {
    my ($params) = @_;

    my $scheme;
    if ($params->{url} =~ /^http:\/\//) {
        $scheme = "http";
    } elsif ($params->{url} =~ /^https:\/\//) {
        $scheme = "https";
    }

    # Using "r23" instead of "23" is an honest mistake
    $params->{rev} =~ s/^\s*r//g;

    # Assemble the command
    my $cmd = defined($params->{cmd}) ? $params->{cmd} : "svn";
    $cmd .= " " . $params->{command_arguments}
        if (defined($params->{command_arguments}));

    $cmd .= " " . 
        (defined($params->{subcommand}) ? $params->{subcommand} : "export");
    $cmd .= " " . $params->{subcommand_arguments}
        if (defined($params->{subcommand_arguments}));
    $cmd .= " --username " . $params->{username}
        if (defined($params->{username}));
    $cmd .= " --password " . $params->{password}
        if (defined($params->{username}));
    $cmd .= " --no-auth-cache"
        if (defined($params->{password_cache}) && !$params->{password_cache});
    $cmd .= " -r " . $params->{rev}
        if (defined($params->{rev}));
    $cmd .= " " . $params->{url} . " " . $params->{dirname};

    # If we're not using http or https (there's no need for proxies),
    # or if we're not using proxies, just do the checkout.
    my $ret;
    if (!defined($scheme) || 
        !defined(@{$MTT::Globals::Values->{proxies}->{$scheme}})) {
        $ret = MTT::DoCommand::Cmd(1, $cmd);
        if (!MTT::DoCommand::wsuccess($ret->{exit_status})) {
             Warning("SVN failure: " . Dumper($ret) . "\n");
             return undef;
        }
        return $ret;
    }

    # The rest of this section must be serialized because only one
    # process can modify the $HOME/.subversion/servers file at a time.
    # Blah!
    MTT::Lock::Lock($ENV{HOME} . "/.subversion/servers");

    # Read in the original $HOME/.subversion/servers file
    my $svnfile = "$ENV{HOME}/.subversion/servers";
    my $file_contents;
    mkdir("$ENV{HOME}/.subversion")
        if (! -d "$ENV{HOME}/.subversion");
    if (-r $svnfile) {
        $file_contents = MTT::Files::Slurp($svnfile);
    } else {
        $file_contents = "[global]
http-proxy-host = bogus
http-proxy-port = bogus\n";
    }

    # Save the original proxy
    my $save_host;
    my $save_port;
    if ($file_contents =~ /\nhttp-proxy-host\s*\=\s*(.*)/i) {
        $save_host = $1;
    }
    if ($file_contents =~ /\nhttp-proxy-port\s*\=\s*(\d+)/i) {
        $save_port = $1;
    }

    # Loop over proxies
    my $proxies = \@{$MTT::Globals::Values->{proxies}->{$scheme}};
    my %ENV_SAVE = %ENV;

    # In case a proxy was not specified, try to svn without one
    if (! @{$proxies}) {
        push(@{$proxies}, undef);
    }

    foreach my $p (@{$proxies}) {

        # Skip "blank" proxies
        if (defined($p->{proxy}) and $p->{proxy} !~ /^\s*$/) {
            Debug("SVN checkout attempting proxy: $p->{proxy}\n");
            _substitute_proxy_in_servers_file($svnfile, $file_contents, $p->{host}, $p->{port});
        }

        my $x = MTT::DoCommand::Cmd(1, $cmd);
        if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
            Warning("SVN failure: $x->{result_stdout}\n");
            next;
        }

        # Grab the SVN version
        if ($x->{result_stdout} =~ m/(?:Checked out|Exported) revision (\d+)\.\n$/i) {
            $ret = $1;
        }

        MTT::Lock::Unlock($ENV{HOME} . "/.subversion/servers");
        return $ret;
    }

    # Fall though means we didn't succeed.  Doh.

    # Restore the original proxy
    Debug("Restoring the proxy originally found in $svnfile: \"$save_host:$save_port\"\n");
    _substitute_proxy_in_servers_file($svnfile, $file_contents, $save_host, $save_port);

    # Reset the servers file to whatever it used to be (if it used to be!)
    MTT::Lock::Unlock($ENV{HOME} . "/.subversion/servers");
    return undef;
}

sub check_previous_revision {
    my ($previous_r, $url) = @_;

    my $function = '&' . FuncName((caller(0))[3]);
    Debug("$function: got @_\n");

    my $ret = 1;

    if ($previous_r) {

        my $x = MTT::DoCommand::Cmd(1, "svn log -r $previous_r:HEAD $url");
        if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
            Warning("Can't check repository properly; going to assume we need a new export\n");
            return $ret;
        } else {

            # There are two possibilities:

            # 1. one line of "-----", meaning that there have been no
            # commits in this directory of the repository since the
            # last R number.

            # 2. one or more entries of log messages.  In this case,
            # we need to look at the r number of the first entry
            # that comes along.  It may be the old r number (i.e.,
            # it's still the HEAD), in which case we don't need a
            # new checkout.  Or it may be a different r number, in
            # which case we need a new checkout.

            if ($x->{result_stdout} =~ /^-+\n$/) {
                Debug("Got one line of dashes -- no need for new export\n");
            } else {
                $x->{result_stdout} =~ m/^-+\nr(\d+)\s/;
                if ($1 eq $previous_r) {
                    Debug("Got old r number -- no need for new export\n");
                    $ret = 0;
                } else {
                    Debug("Got new r number ($1) -- need new export\n");
                }
            }
        }
    } else {
        Debug("$function no previous revision to check against.\n");
    }

    Debug("$function returning $ret\n");
    return $ret;
}

sub _substitute_proxy_in_servers_file {
    my ($file, $contents, $host, $port) = @_;

    # Write a new $HOME/.subversion/servers file with the
    # right proxy info
    if ($host) {
        $host =~ m@^.+://(.+):([0-9]+)/@;
        $contents =~ s/^\s*http-proxy-host\s*=.*$/http-proxy-host = $host/m;
        $contents =~ s/^\s*http-proxy-port\s*=.*$/http-proxy-port = $port/m;
    } else {
        $contents =~ s/^\s*http-proxy-host\s*=.*$//m;
        $contents =~ s/^\s*http-proxy-port\s*=.*$//m;
    }
    open(FILE, ">$file");
    print FILE $contents;
    close(FILE);
}

1;
