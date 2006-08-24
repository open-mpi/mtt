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

package MTT::DoCommand;

use strict;
use POSIX ":sys_wait_h";
use File::Temp qw(tempfile);
use MTT::Messages;
use Data::Dumper;

#--------------------------------------------------------------------------

sub _kill_proc {
    my ($pid) = @_;

    # Try an easy kill
    my $kid;
    kill("HUP", $pid);
    $kid = waitpid($pid, WNOHANG);
    if ($kid != 0) {
        return $?;
    }

    # Nope, that didn't work.  Sleep a few seconds and try again.
    sleep(2);
    $kid = waitpid($pid, WNOHANG);
    if ($kid != 0) {
        return $?;
    }

    # That didn't work either.  Try SIGINT;
    kill("INT", $pid);
    $kid = waitpid($pid, WNOHANG);
    if ($kid != 0) {
        return $?;
    }

    # Nope, that didn't work.  Sleep a few seconds and try again.
    sleep(2);
    $kid = waitpid($pid, WNOHANG);
    if ($kid != 0) {
        return $?;
    }

    # Ok, now we're mad.  Be violent.
    while (1) {
        kill("KILL", $pid);
        $kid = waitpid($pid, WNOHANG);
        if ($kid != 0) {
            return $?;
        }
        sleep(2);
    }
}

#--------------------------------------------------------------------------

sub _quote_escape {
    my $cmd = shift;

    my @tokens;

    # Convert \n, \r, and \\n, and \\r to " "
    $cmd =~ s/\s*\\?\s*[\n\r]\s*/ /g;
    # Trim leading and trailing whitespace
    $cmd =~ /^(\s*)(.*)(\s*)$/;
    $cmd = $2;

    # If we find some quote pairs, go off and handle them.  Assume
    # that we will not have nested quotes.
    if ($cmd =~ /\"[^\"]*\"/) {
        # Grab the first pair of inner-most quotes
        $cmd =~ /(.*?)\"([^\"]*)\"(.*)/;

        my $prefix = $1;
        my $middle = $2;
        my $suffix = $3;

        # If we have a prefix, go quote escape it and get a bunch of
        # tokens back for it.  Save all of those tokens in our list of
        # tokens.
        if ($prefix) {
            my $prefix_tokens = _quote_escape($prefix);
            foreach my $token (@$prefix_tokens) {
                push(@tokens, $token);
            }
        }

        if ($middle) {

            # If the $prefix ended in whitespace (or if there was no
            # $prefix), then push the $middle in as its own token.  If
            # the $prefix did not end in whitespace, then append the
            # $middle to the last token from the $prefix.

            if (($prefix && ($prefix =~ /\s$/)) ||
                !$prefix) {
                push(@tokens, $middle);
            } else {
                $tokens[$#tokens] .= $middle;
            }
        } else {
            push(@tokens, "");
        }

        # If the $suffix starts with whitespace, then the $middle
        # concluded the token.  If not, then the first token in the
        # $suffix is part of the same token as the first token in
        # $middle.
        if ($suffix) {
            my $suffix_tokens = _quote_escape($suffix);
            if ($suffix =~ /^[^\s]/) {
                $tokens[$#tokens] .= $$suffix_tokens[0];
                shift @$suffix_tokens;
            }
            foreach my $token (@$suffix_tokens) {
                push(@tokens, $token);
            }
        }
    }

    # Otherwise, if there were no quote pairs, do the simple thing
    elsif ($cmd) {
        push(@tokens, split(/\s/, $cmd));
    }

    # All done
    return \@tokens;
}

#--------------------------------------------------------------------------

# run a command and save the stdout / stderr
sub Cmd {
    my ($merge_output, $cmd, $timeout) = @_;

    Debug("Running command: $cmd\n");
    pipe OUTread, OUTwrite;
    pipe ERRread, ERRwrite
        if (!$merge_output);

    # Child

    my $pid;
    if (($pid = fork()) == 0) {
        close OUTread;
        close ERRread
            if (!$merge_output);

        close(STDERR);
        if ($merge_output) {
            open STDERR, ">&OUTwrite" ||
                die "Can't redirect stderr\n";
        } else {
            open STDERR, ">&ERRwrite" ||
                die "Can't redirect stderr\n";
        }
        select STDERR;
        $| = 1;

        close(STDOUT);
        open STDOUT, ">&OUTwrite" || 
            die "Can't redirect stdout\n";
        select STDOUT;
        $| = 1;

        # Turn shell-quoted words ("foo bar baz") into individual tokens

        my $tokens = _quote_escape($cmd);

        # Run it!

        exec(@$tokens) ||
            die "Can't execute command: $cmd\n";
    }
    close OUTwrite;
    close ERRwrite
        if (!$merge_output);

    # Parent

    my (@out, @err);
    my ($rin, $rout);
    my $done = $merge_output ? 1 : 2;

    # Keep watching over the pipe(s)

    $rin = '';
    vec($rin, fileno(OUTread), 1) = 1;
    vec($rin, fileno(ERRread), 1) = 1
        if (!$merge_output);

    my $t;
    my $end_time;
    if (defined($timeout) && $timeout > 0) {
        $t = 1;
        $end_time = time() + $timeout;
        Debug("Timeout: $t - $end_time (vs. now: " . time() . ")\n");
    }
    my $killed_status;
    while ($done > 0) {
        my $nfound = select($rout = $rin, undef, undef, $t);
        if (vec($rout, fileno(OUTread), 1) == 1) {
            my $data = <OUTread>;
            if (!defined($data)) {
                vec($rin, fileno(OUTread), 1) = 0;
                --$done;
            } else {
                push(@out, $data);
                Debug("OUT:$data");
            }
        }

        if (!$merge_output && vec($rout, fileno(ERRread), 1) == 1) {
            my $data = <ERRread>;
            if (!defined($data)) {
                vec($rin, fileno(ERRread), 1) = 0;
                --$done;
            } else {
                push(@err, $data);
                Debug("ERR:$data");
            }
        }

        # If we're running with a timeout, bail if we're past the end
        # time
        if (defined($end_time) && time() > $end_time) {
            Debug("Past timeout! $end_time < " . time() . "\n");
            $killed_status = _kill_proc($pid);
        }
    }
    close OUTerr;
    close OUTread
        if (!$merge_output);

    # The pipes are closed, so the process should be dead.  Reap it.

    waitpid($pid, 0);
    my $status = $?;
    Debug("Command complete, exit status: $status\n");

    # Return an anonymous hash containing the relevant data

    my $ret = {
        stdout => join('', @out),
        status => $status
        };

    # If we had stderr, return that, too

    $ret->{stderr} = join('', @err),
        if (!$merge_output);
    return $ret;
}

#--------------------------------------------------------------------------

sub CmdScript {
    my ($merge_output, $cmds, $timeout) = @_;

    my ($fh, $filename) = tempfile();
    print $fh ":\n$cmds\n";
    close($fh);
    chmod(0700, $filename);

    my $x = Cmd($merge_output, $filename, $timeout);
    unlink($filename);
    return $x;
}

1;
