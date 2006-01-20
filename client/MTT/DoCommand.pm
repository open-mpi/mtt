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

        my @tokens;
        while ($cmd =~ /\".*\"/) {
            my $prefix;
            my $middle;
            my $suffix;
            
            $cmd =~ /(.*?)\"(.*?)\"(.*)/;
            $prefix = $1;
            $middle = $2;
            $suffix = $3;
            
            if ($prefix) {
                foreach my $token (split(' ', $prefix)) {
                    push(@tokens, $token);
                }
            }
            if ($middle) {
                push(@tokens, $middle);
            } else {
                push(@tokens, "");
            }
            $cmd = $suffix;
        }
        if ($cmd) {
            push(@tokens, split(' ', $cmd));
        }

        # Run it!

        exec(@tokens) ||
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
    my ($merge_output, $cmds) = @_;

    my ($fh, $filename) = tempfile();
    print $fh ":\n$cmds\n";
    close($fh);
    chmod(0700, $filename);

    my $x = Cmd($merge_output, $filename);
    unlink($filename);
    return $x;
}

1;
