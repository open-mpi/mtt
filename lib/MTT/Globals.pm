#!/usr/bin/env perl
#
# Copyright (c) 2006-2008 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Globals;

use strict;

use MTT::Values;
use MTT::Messages;
use Data::Dumper;

# Global variable to hold [possibly] user-overridden values

our $Values;

# Global variable to hold internal values

our $Internals;

# Defaults that are reset on a per-ini-file basis

my $_defaults = {
    funclet_files => undef,

    hostfile => undef,
    hostlist => undef,
    max_np => undef,
    textwrap => 76,
    drain_timeout => 5,

    trim_save_successful => 0,
    trim_save_failed => 1,

    trial => 0,

    terminate_files => "&getenv(\"HOME\")/mtt-stop, &scratch_root()/mtt-stop",
    time_to_terminate => 0,
    pause_files => "&getenv(\"HOME\")/mtt-pause, &scratch_root()/mtt-pause",

    http_proxy => undef,
    https_proxy => undef,
    ftp_proxy => undef,
    proxies => undef,

    before_any_exec => undef,
    before_any_exec_timeout => 10,
    before_any_exec_pass => "&and(&cmd_wifexited(), &eq(&cmd_wexitstatus(), 0))",

    before_exec_exec => undef,
    before_exec_exec_timeout => 10,
    before_exec_exec_pass => "&and(&cmd_wifexited(), &eq(&cmd_wexitstatus(), 0))",

    after_each_exec => undef,
    after_each_exec_timeout => 10,
    after_each_exec_pass => "&and(&cmd_wifexited(), &eq(&cmd_wexitstatus(), 0))",

    after_all_exec => undef,
    after_all_exec_timeout => 10,
    after_all_exec_pass => "&and(&cmd_wifexited(), &eq(&cmd_wexitstatus(), 0))",

    min_disk_free => "5%",
    min_disk_free_wait => "60",

    delete_fast_scratch => 1,
    save_fast_scratch_files => "config.log",

    docommand_timeout_notify_file => undef,
    docommand_timeout_notify_email => undef,
    docommand_timeout_notify_timeout => undef,
};

#--------------------------------------------------------------------------

# Reset $Globals per a specific ini file

sub load {
    my ($scratch_root, $fast_scratch_root, $ini) = @_;

    %$Values = %$_defaults;
    $Values->{scratch_root} = $scratch_root;
    $Values->{fast_scratch_root} = $fast_scratch_root;

    # Are there funclet .pm files to load?  If so, do these first so
    # that the funclets can be used by the rest of the fields.


    my $val = MTT::Values::Value($ini, "MTT", "funclet_files");
    if (defined($val)) {
        foreach my $f (MTT::Util::split_comma_list($val)) {
            require $f;
        }
    }

    # Max_np (do before hostfile / hostlist) 

    # NOTE: We have to use the full name MTT::Values::Value() here
    # because this file includes MTT::Value which includes
    # MTT::Value::Functions, but MTT::Value::Functions includes this
    # file (i.e., a circular dependency).

    # Hostfile

    $val = MTT::Values::Value($ini, "MTT", "hostfile");
    if (defined($val)) {
        $Values->{hostfile} = $val;
        _parse_hostfile($val);
    }

    # Hostlist

    $val = MTT::Values::Value($ini, "MTT", "hostlist");
    if (defined($val)) {
        $Values->{hostlist} = $val;
        _parse_hostlist($val);
    }

    # Simple parameters

    my @names = qw/max_np textwrap drain_timeout trim_save_successful trim_save_failed trial http_proxy https_proxy ftp_proxy terminate_files pause_files min_disk_free min_disk_free_wait delete_fast_scratch save_fast_scratch_files docommand_timeout_notify_file docommand_timeout_notify_email docommand_timeout_notify_timeout/;
    foreach my $t (qw/before after/) {
        foreach my $a (qw/all each/) {
            push(@names, $t . "_" . $a . "_exec");
            push(@names, $t . "_" . $a . "_exec_timeout");
            push(@names, $t . "_" . $a . "_exec_pass");
        }
    }
    foreach my $name (@names) {
        $val = MTT::Values::Value($ini, "MTT", $name);
        $Values->{$name} = $val
            if (defined($val));
    }

    # Parse the list of terminate_files into an array

    if (defined($Values->{terminate_files})) {
        my @names = split(/[,\s]+/, $Values->{terminate_files});
        my @save;
        foreach my $n (@names) {
            push(@save, $n)
                if ($n);
        }
        $Values->{terminate_files} = \@save;
    }

    # Parse the list of pause_files into an array

    if (defined($Values->{pause_files})) {
        my @names = split(/[,\s]+/, $Values->{pause_files});
        my @save;
        foreach my $n (@names) {
            push(@save, $n)
                if ($n);
        }
        $Values->{pause_files} = \@save;
    }

    # Proxies

    _setup_proxy("http");
    _setup_proxy("https");
    _setup_proxy("ftp");
}

#--------------------------------------------------------------------------

#
# Test that a hostfile is good, and if we don't have one already,
# generate a max_np value.
#
sub _parse_hostfile {
    my ($file) = @_;

    # Check that the file exists, is readable, and we can open it

    if ($file =~ /^\s*$/) {
        delete $Values->{hostfile};
        return;
    }

    my $bad = 0;
    if (! -r $file) {
        $bad = 1;
    } else {
        open(FILE, $file) || ($bad = 1);
    }

    if ($bad) {
        MTT::Messages::Warning("Unable to read hostfile: $file -- ignoring\n");
        delete $Values->{hostfile};
        return;
    }

    # Here's how we calculte max_np
    #
    # - If the hostname (first token) is of the form "name:X", add X
    #   to $max_np and continue to the next line
    # - If any of the remaining tokens are "slots=X", add X to $max_np
    #   and continue to the next line
    # - If any of the remaining tokens are "max[_-]slots=X", add X to
    #   $max_np and continue to the next line
    # - Add 1 to $max_np

    my $max_np = 0;
    while (<FILE>) {
        # Skip comment lines
        next
            if (/^\s*\#/ ||
                /^\s*\n/);

        # We got a good line; so split it up into tokens
        my @tokens = split(/\s+/);

        # The first token is the hostname
        shift @tokens;
        if (/:(\d+)$/) {
            Debug(">> Hostfile: Found :X = $1\n");
            $max_np += $1;
            next;
        }

        # Go through the rest of them looking for "slots=X"
        my $found = 0;
        foreach (@tokens) {
            if (/^slots=(\d+)/) {
                Debug(">> Hostfile: Found slots = $1\n");
                $max_np += $1;
                $found = 1;
                last;
            }
        }
        next
            if ($found);

        # Go through the rest of them looking for "max[-_]slots=X"
        foreach (@tokens) {
            if (/^max[_-]slots=(\d+)/) {
                Debug(">> Hostfile: Found max_slots = $1\n");
                $max_np += $1;
                $found = 1;
                last;
            }
        }
        next
            if ($found);

        # Didn't find anything.  So just add 1 to $max_np;
        ++$max_np;
    }
    $Values->{hostfile_max_np} = $max_np;
    Debug(">> Got default hostfile: $file, max_np: $max_np\n");
    
    close(FILE);
}

#--------------------------------------------------------------------------

#
# Test that a hostlist is good, and if we don't have one already,
# generate a max_np value.
#
sub _parse_hostlist {
    my ($str) = @_;

    # If it's empty, do nothing

    if ($str =~ /^\s*$/) {
        delete $Values->{hostlist};
        return;
    }

    # Made a hostlist suitable for mpiexec and count the max procs

    my @vals = split(/\s+/, $str);
    my $hostlist;
    my $max_np;
    foreach (@vals) {
        my ($name, $count) = split(/:/);
        $count = 1
            if (! $count);
        $max_np += $count;
        while ($count > 0) {
            $hostlist .= ","
                if ($hostlist);
            $hostlist .= $name;
            --$count;
        }
    }
    
    # Save the final values
    
    $Values->{hostlist} = $hostlist;
    $Values->{hostlist_max_np} = $max_np;
    Debug(">> Got default hostlist: $hostlist, max_np: $max_np\n");
}

#--------------------------------------------------------------------------

#
# Parse proxy lists out
#
sub _setup_proxy {
    my $scheme = shift;

    my $uniq;
    my @proxies;

    # Check for values from the INI file
    if (defined($Values->{$scheme . "_proxy"})) {
        foreach my $p (split(",", $Values->{$scheme . "_proxy"})) {
            # Strip whitespace off front and back
            $p =~ s/^\s*(\S+)\s*$/\1/;
            # Check for uniqueness among the list so far
            if (!exists($uniq->{$p})) {
                # Enforce that you have to set a "<foo>://" at the
                # beginning of the proxy
                if ($p !~ /^https?:\/\//) {
                    Warning("Skipping mal-formed proxy: $p\n");
                    next;
                }

                # Extract the host and port; other places in MTT use it
                $p =~ m@^.+://(.+):([0-9]+)@;
                my $host = $1;
                my $port = $2;
                
                # Ok, it was good -- save it.
                $uniq->{$p} = "";
                push(@proxies, { 
                    proxy => $p, 
                    host => $host,
                    port => $port,
                    source => "INI file",
                });
            }
        }
    }

    # Otherwise, look in the environment
    elsif (exists($ENV{$scheme . "_proxy"})) {
        # If it doesn't have $scheme at the front of the value,
        # prepend it

        my $p = $ENV{$scheme . "_proxy"};
        $p = "$scheme://$p"
            if ($p !~ /^https?:\/\//);
        push(@proxies, { proxy => $p, source => "Environment" });
    }

    # Otherwise, put a blank entry there

    else {
        push(@proxies, { proxy => "", source => "Default (none)"});
    }

    # Save it
    $Values->{proxies}->{$scheme} = \@proxies;
    delete $Values->{$scheme . "_proxy"};

    # MTT must control all proxies (because underlying perl constructs
    # are inconsistent on how they look for proxies -- LWP for SSL,
    # for example, will automatically look at HTTPS_PROXY/http_proxy),
    # so clean the environment.  MTT will reset the environment as
    # necessary.
    delete $ENV{$scheme . "_proxy"};
    $scheme = uc($scheme);
    delete $ENV{$scheme . "_PROXY"};
}

1;
