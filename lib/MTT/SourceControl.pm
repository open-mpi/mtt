#!/usr/bin/env perl
#
# Copyright (c) 2007 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::SourceControl;
my ($package) = (__PACKAGE__ =~ m/(\w+)$/);

use strict;
use Cwd;
use File::Basename;
use POSIX qw(strftime);
use MTT::Messages;
use MTT::Values;
use MTT::Files;
use MTT::INI;
use MTT::DoCommand;
use MTT::FindProgram;
use Data::Dumper;

#--------------------------------------------------------------------------

# Process INI parameter functions for any Subverison-like versioning
# system. We default to SVN for backcompatibility and because SVN is 
# what the Open MPI community uses.
sub ProcessInputParameters {
    Debug(">> ProcessInputParameters\n");
    my ($ini, $section) = @_;

    my $ret;

    # See if we got a url in the ini section
    my $url = Value($ini, $section, &_prefix_parameter("url"));
    if (!$url) {
        $ret->{result_message} = "No URL specified in [$section]; skipping";
        Warning("$ret->{result_message}\n");
        return $ret;
    }
    Debug(">> $package: got url $url\n");

    # Process INI file parameters
    my $r                    = Value($ini, $section, &_prefix_parameter("r"));
    my $username             = Value($ini, $section, &_prefix_parameter("username"));
    my $password             = Value($ini, $section, &_prefix_parameter("password"));
    my $password_cache       = Value($ini, $section, &_prefix_parameter("password_cache"));
    my $export               = Value($ini, $section, &_prefix_parameter("export"));   # Deprecated
    my $checkout             = Value($ini, $section, &_prefix_parameter("checkout")); # Deprecated
    my $command              = Value($ini, $section, &_prefix_parameter("command"));
    my $command_arguments    = Value($ini, $section, &_prefix_parameter("command_arguments"));
    my $subcommand           = Value($ini, $section, &_prefix_parameter("subcommand"));
    my $subcommand_arguments = Value($ini, $section, &_prefix_parameter("subcommand_arguments"));
    my $delete_first         = Value($ini, $section, &_prefix_parameter("delete_first"));

    # Setup sub-command
    my $export;
    if ($export and $checkout) {
        Warning("export and checkout were both specified. Defaulting to export.\n");
        Warning("Both of these parameters are deprecated. Use \"*_subcommand = <subcommand>\" instead.\n");
        $subcommand = "export";
    } elsif ($checkout) {
        Warning("checkout is deprecated. Use \"*_subcommand = checkout\" instead.\n");
        $subcommand = "checkout";
    } elsif ($export) {
        Warning("export is deprecated. Use \"*_subcommand = export\" instead.\n");
        $subcommand = "export";
    } elsif (! $subcommand) {
        Debug("$package module is defaulting to \"export\".\n");
        $subcommand = "export";
    }

    # Append arguments to commands
    $command .= " ";
    $command .= "$command_arguments "   if ($command_arguments);
    $command .= "-r $r "                if ($r);
    $command .= "--username $username " if ($username);
    $command .= "--password $password " if ($password);
    $command .= "--no-auth-cache "      if ("0" eq $password_cache);

    $subcommand .= " $subcommand_arguments "
        if ($subcommand_arguments);

    # Default to overwriting an existing checkout
    if (! defined($delete_first)) {
        $delete_first = 1;
    }

    # Set the function pointer -- note that we just re-use the
    # copytree module, since that's all we have to do (i.e., copy a
    # local tree)
    $ret->{prepare_for_install} = "MTT::Common::Copytree::PrepareForInstall";
    $ret->{pre_copy}            = Value($ini, $section, &_prefix_parameter("pre_export"));
    $ret->{post_copy}           = Value($ini, $section, &_prefix_parameter("post_export"));
    $ret->{version}             = Value($ini, $section, &_prefix_parameter("version"));

    $ret->{delete_first}   = $delete_first;
    $ret->{command}        = $command;
    $ret->{subcommand}     = $subcommand;
    $ret->{url}            = $url;

    $ret->{simple_section} = GetSimpleSection($section);

    return $ret;
}

# Do a source code checkout
sub Checkout {
    my ($delete_first, $command, $subcommand, $url) = @_;

    Debug("Checkout: " . ($url ? $url : $command) . "\n");

    my $basename;
    my $dirname;
    my $cwd = cwd();

    # Some SCMs do not have a naked [SOURCE] argument.
    # E.g., teamware uses "-p [SOURCE]". In these cases,
    # we give the programmer the benefit of the doubt that
    # they've constructed a valid checkout command, but 
    # we also ignore the delete_first parameter
    if ($url) {
        $basename = basename($url);
        $dirname = "$cwd/$basename";
        MTT::DoCommand::Cmd(1, "rm -rf $basename")
            if ($delete_first);
    }

    my $cmd = "$command $subcommand $url $dirname";

    my $rev;
    if ($command =~ /\bsvn\b/) {
        $rev = _svn_checkout($cmd, $url);
    } elsif ($command =~ /\bhg\b/) {
        $rev = _hg_checkout($cmd, $url);
    } elsif ($command =~ /\bsvk\b/) {
        $rev = _svk_checkout($cmd, $url);
    } else {
        $rev = _unknown_checkout($cmd, $url);
    }

    return ($dirname, $rev);
}

# Try to do a Subversion checkout given the users list
# of proxies. This requires locking the
# ~/.subversion/servers file because Subversion does not
# have a --proxy command-line option.
sub _svn_checkout {
    my ($cmd, $url) = @_;

    my $scheme;
    if ($url =~ /^http:\/\//) {
        $scheme = "http";
    } elsif ($url =~ /^https:\/\//) {
        $scheme = "https";
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

    my $ret;
    foreach my $p (@{$proxies}) {

        # Skip "blank" proxies
        if (defined($p->{proxy}) and $p->{proxy} !~ /^\s*$/) {
            Debug("SVN checkout attempting proxy: $p->{proxy}\n");
            _substitute_proxy_in_servers_file($svnfile, $file_contents, $p->{host}, $p->{port});
        }

        my $x = MTT::DoCommand::Cmd(1, $cmd);

        next if (!MTT::DoCommand::wsuccess($x->{exit_status}));

        # Grab the SVN version
        if ($x->{result_stdout} =~ m/Exported revision (\d+)\.\n$/) {
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

# Do a Mercurial clone
sub _hg_checkout {
    my ($cmd, $url) = @_;

    my $ret = undef;

    my $x = MTT::DoCommand::Cmd(1, $cmd);

    return $ret
        if (!MTT::DoCommand::wsuccess($x->{exit_status}));

    $ret = hg_identify_n($url);

    return $ret;
}

# Do an SVK checkout
sub _svk_checkout {
    my ($cmd) = @_;

    my $ret = undef;

    my $x = MTT::DoCommand::Cmd(1, $cmd);

    return $ret
        if (!MTT::DoCommand::wsuccess($x->{exit_status}));

    # Grab the SVK version
    if ($x->{result_stdout} =~ m/Syncing\s+\S+\s+in\s+\S+\s+to\s+(\d+)/i) {
        $ret = $1;
    }

    return $ret;
}

sub _unknown_checkout {
    my ($cmd) = @_;

    my $ret = undef;

    my $x = MTT::DoCommand::Cmd(1, $cmd);

    return $ret
        if (!MTT::DoCommand::wsuccess($x->{exit_status}));

    Warning("MTT does not know how to get a version number from this output: $x->{result_stdout}");

    return "unknown";
}

# Replace the proxy host and port in the ~/.subversion/servers file
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

#--------------------------------------------------------------------------

# Return a list of parameters for Value
# that are prefixed by a valid versioning tool name
sub _prefix_parameter {
    my ($str) = @_;

    # Accept any of the below as INI parameter prefixes for an SVN section
    my @valid_versioning_tools = (
        "svn",
        "svk",
        "hg",
        "cvs",
        "rcs",
        "sccs",
        "teamware",
        "git",
    );

    return map { "${_}_$str" } @valid_versioning_tools;
}

# Return the "hg identify -n" value.
# Not to be used for web-served repositories.
sub hg_identify_n {
    my ($dir) = @_;

    my $funclet = '&' . FuncName((caller(0))[3]);
    Debug("$funclet: got @_\n");

    if (! FindProgram(qw(hg))) {
        Warning("$funclet() can not continue wihtout 'hg'.\n");
        return undef;
    }

	# Change into the Mercurial directory
    MTT::DoCommand::Pushdir($dir);

	# Run the "identify" command
    my $ret = `hg identify -n`;
    chomp $ret;

	# Return to the last directory
    MTT::DoCommand::Popdir();

    Debug("$funclet returning $ret\n");
    return $ret;
}

sub hg_check_previous_revision {
    my ($z, $url) = @_;

    my $ret = 0;

    # a la Subversion "checkout"
    my $checkout_cmd = "clone";

    my $function = '&' . FuncName((caller(0))[3]);
    Debug("$function: got @_\n");

    # Do an "hg pull" and see what happens ...
    MTT::DoCommand::Pushdir(basename($url));
    my $x = MTT::DoCommand::Cmd(1, "hg pull");
    MTT::DoCommand::Popdir();

    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        Warning("Can't check the repository: $x->{result_stdout}.\n\tGoing to assume we need a new $checkout_cmd\n");
        $ret = 1;
        return $ret;
    } else {

        # Two possible outcomes:

        # 1.
        # $ hg pull
        # pulling from /foo/bar
        # searching for changes
        # adding changesets
        # adding manifests
        # adding file changes
        # added 1 changesets with 0 changes to 0 files
        # (run 'hg update' to get a working copy)
        my $pattern_have_new = 'added \s+ \d+ \s+ changesets';

        # 2.
        # $ hg pull
        # pulling from /foo/bar
        # searching for changes
        # no changes found
        my $pattern_have_old = 'no \s+ changes \s+ found';

        # Check the output against the patterns
        if ($x->{result_stdout} =~ /$pattern_have_old/ixo) {
            Debug("Found the pattern: '$pattern_have_old' -- no need for new $checkout_cmd\n");
        } elsif ($x->{result_stdout} =~ /$pattern_have_new/ixo) {
            $ret = 1;
            Debug("Found the pattern: '$pattern_have_new' -- need new $checkout_cmd\n");
        }
    }

    Debug("$function returning $ret\n");
    return $ret;
}

# Returns one of the following:
#
#  1: We need new test sources (because the sources we have are old,
#     or we have never checked them out before, i.e., $previous_r is
#     undefined)
#  0: We have already tested this revision/url pair
#
sub svn_check_previous_revision {
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

1;
