#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2014 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007-2008 Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2007-2012 High Performance Computing Center Stuttgart, 
#                         University of Stuttgart.  All rights reserved.
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
use Socket;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use MTT::Messages;
use MTT::Values;
use MTT::Values::Functions;
use MTT::Timer;
use MTT::Mail;
use MTT::FindProgram;
use MTT::Files;
use Data::Dumper;
use File::Spec;
use Cwd;
use Benchmark;

#--------------------------------------------------------------------------

# Want to see what MTT *would* do?
our $no_execute;

# Exit status (i.e., return from waitpid()) from the last
# DoCommand::Cmd[Script]
our $last_exit_status;

#--------------------------------------------------------------------------

# Cache so that we don't re-calculate these every time
my $server_socket;
my $server_addr;
my $tcp_proto;

# Print command timings?
my $time_arg;

#--------------------------------------------------------------------------

sub DoCommand {
    ($time_arg, $no_execute) = @_;
}

# This function is called for killing both mpirun and each of its
# descendants.  We really only want to see verbose output for when we
# kill mpirun itself, so only show output when the caller provides us
# with a $argv0 value.
sub _kill_proc_one {
    my ($pid, $argv0) = @_;

    # How long to wait after each kill()
    my $wait_time = 5;

    # See if the proc is alive first
    my $num_alive = kill(0, $pid);
    return "$argv0 died right at end of timeout (MTT did not have to kill it)"
        if (0 == $num_alive);

    # Try an easy kill
    kill("TERM", $pid);
    Verbose("*** Killing $argv0 with SIGTERM\n")
        if (defined($argv0));
    # Give mpirun some time to cleanup before we try to reap it.
    my $kid;
    my $i = $wait_time;
    while ($i > 0) {
        sleep(1);
        $kid = waitpid($pid, WNOHANG);

        # This sub is only invoked to forcibly kill the process (i.e.,
        # it's over its timeout, so gotta kill it).  Hence, we don't
        # care what the return status is -- just return if a) the
        # process no longer exists (i.e., we get -1 back from
        # waitpid), or we successfully killed it (i.e., we got the PID
        # back from waitpid).
        return "MTT killed $argv0 via SIGTERM" if (0 != $kid);

        --$i;
    }
    Verbose("** Kill TERM (after $wait_time seconds) didn't work!\n")
        if (defined($argv0));

    # That didn't work either.  Try SIGINT;
    Verbose("*** Killing $argv0 with SIGINT\n")
        if (defined($argv0));
    kill("INT", $pid);
    my $i = $wait_time;
    while ($i > 0) {
        sleep(1);
        $kid = waitpid($pid, WNOHANG);
        return "MTT killed $argv0 via SIGINT" if (0 != $kid);
        --$i;
    }
    Verbose("** Kill INT (after $wait_time seconds) didn't work!\n")
        if (defined($argv0));

    # Ok, now we're mad.  Be violent.
    Verbose("*** Now I'm mad.  Killing $argv0 with SIGKILL\n")
        if (defined($argv0));
    my $count = 0;
    while (1) {
        kill("KILL", $pid);
        ++$count;
        $kid = waitpid($pid, WNOHANG);
        return "MTT killed $argv0 via $count SIGKILLs" if (0 != $kid);
        Verbose("** Kill KILL didn't work!  Sleeping and trying again...\n")
            if (defined($argv0));
        sleep(1);
    }
}


sub _kill_proc_tree {
    my ($pid, $argv0) = @_;

    # Find all descendent processes of the main PID
    my @children = descendant_processes($pid);

    # Kill the main PID.  Note that _kill_proc_one() will give the
    # process time to react/cleanup, so there's no need for an
    # additional delay after it returns.
    my $ret = _kill_proc_one($pid, $argv0);

    # Now kill all the processes that descended from the base PID.
    #
    # Note: when mpirun is working properly (which is one of the
    # biggest use cases for DoCommand), this is redundant -- all the
    # children will already be dead (because killing mpirun will
    # ensure that all descendant processes are also killed).
    #
    # That being said, a) DoCommand() is used to launch more than just
    # mpirun, b) mpirun breaks sometimes and doesn't clean up its
    # descendants, and c) it's safe to call _kill_proc_one() on a PID
    # that is already dead.
    foreach my $process (@children) {
        Debug("=== killing child proc: $process->{pid}, $process->{argv0}\n");

        # Ignore the return.  For example, we don't care if the child
        # is already dead
        _kill_proc_one($process->{pid});
    }

    return $ret;
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
        push(@tokens, split(/\s+/, $cmd));
    }

    # All done
    return \@tokens;
}

#--------------------------------------------------------------------------

# Add complete, \n-terminated lines to the output array.  If there's
# an incomplete last line (i.e., not \n-terminated), add it to the
# partial string.
#
# Then trim the array to be, at most, $max_lines long (as if one
# included the last, incomplete line).
sub _append {
    my ($data, $prefix, $max_lines, $array, $partial) = @_;

    # If there's no newline, add this line to the partial; we're done
    if ($data !~ /\n/) {
        $$partial .= $data;
        return;
    }

    # Prefix the data with the partial
    if (defined($$partial)) {
        $data = "$$partial$data";
        $$partial = undef;
    }

    # Grab the partial after the last \n in $data (for use with
    # comparisons, below)
    $data =~ m/\n(.*?)$/;
    $$partial = $1;

    # Split into individual lines
    my @lines = split(/\n/, $data);

    # Is the last line the same as the partial?  If so, remove it from
    # @lines (because it was an incomplete line).
    pop(@lines)
        if ($lines[$#lines] eq $$partial);

    # Now add all the (prefixed) @lines to the output array
    while (@lines) {
        my $l = shift(@lines);
        push(@{$array}, "$prefix$l\n");
    }

    # Now trim the output array to be, at most, $max_lines.  If we
    # have a partial last line, then decrement $max_lines by 1 to
    # make it seem like we have 1 more line.
    if ($max_lines > 0) {
        --$max_lines
            if (length($$partial) > 0);
        shift(@{$array})
            while ($#{$array} >= $max_lines);
    }
}

#--------------------------------------------------------------------------

# run a command and save the stdout / stderr
sub Cmd {
    my ($merge_output, $cmd, $timeout, 
        $max_stdout_lines, $max_stderr_lines, $print_timestamp) = @_;

    if($print_timestamp eq "y" || $print_timestamp eq "Y" || $print_timestamp eq "1") {
        $print_timestamp = 1;
    } else {
        $print_timestamp = 0;
    }
    my $ini = $MTT::Globals::Internals->{ini};
    my $pause_file = MTT::Values::Value( $ini, "MTT", 'docommand_pause_file' );
    my @pause_array = split(',', $pause_file);


    # If there are pipes, redirects, shell-bangs, or newlines
    # write them to a file and run it as a script. Otherwise,
    # use exec() for improved performance.
    if (_contains_shell_script_characters($cmd)) {
        return CmdScript(@_);
    }

    Debug("Running command: $cmd\n");

    # Return value

    my $ret;
    $ret->{timed_out} = 0;

    # Start the timer

    $ret->{start_benchmark} = &MTT::Timer::start();

    # Perl kills me here.  It does its own buffering of pipes which
    # interferes with trying to loop over select() and read() from
    # them (you can end up in a race condition where either select()
    # lies and the pipe is not ready to read() or the read() ends up
    # blocking, which pretty much defeats the point).  You also can't
    # set pipes to be O_NONBLOCK, so that's no good.  You're supposed
    # to use sysread() with select(), anyway, but sysread requires an
    # explicit number of bytes to read (which we don't know).  So
    # that's no good.

    # There are several other non-portable solutions to this (e.g.,
    # open2(), open3(), the Expect.pm, etc.), but they all require
    # additional perl items installed.  So just open a pair of tcp
    # sockets over loopback and do everything that way (because we can
    # set those to O_NONBLOCK and then select()/sysread() over that).
    # Sigh.
    
    # If we have not already, setup a listening socket

    if (!defined($server_addr)) {

        # This is cached for the client
        $tcp_proto = getprotobyname('tcp');

        # Open a TCP socket in the top-level global scope
        socket($server_socket, PF_INET, SOCK_STREAM, $tcp_proto) 
            || die "socket: $!";

        # Be gentle
        setsockopt($server_socket, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))
            || die "setsockopt: $!";

        # Bind it to a random port
        bind($server_socket, sockaddr_in(undef, INADDR_LOOPBACK))
            || die "bind: $!";

        # Cache the resulting address ([port,addr] tuple) for the
        # client
        $server_addr = getsockname($server_socket);

        # Start listening
        listen($server_socket, SOMAXCONN)
            || die "listen: $!";
    }

    # Turn shell-quoted words ("foo bar baz") into individual tokens

    my $tokens = _quote_escape($cmd);

    my $pid;
    if (! $no_execute) {

        # Child
        if (($pid = fork()) == 0) {
            close($server_socket);

            # Open socket(s) back up to the parent

            socket(OUTwrite, PF_INET, SOCK_STREAM, $tcp_proto)
                || die "socket: $!";
            connect(OUTwrite, $server_addr)
                || die "connect: $!";
            if (!$merge_output) {
                socket(ERRwrite, PF_INET, SOCK_STREAM, $tcp_proto)
                    || die "socket: $!";
                connect(ERRwrite, $server_addr)
                    || die "connect: $!";
            }

            if ($merge_output) {
                open STDERR, ">&OUTwrite" ||
                    die "Can't redirect stderr\n";
            } else {
                open STDERR, ">&ERRwrite" ||
                    die "Can't redirect stderr\n";
            }
            select STDERR;
            $| = 1;

            open STDOUT, ">&OUTwrite" || 
                die "Can't redirect stdout\n";
            select STDOUT;
            $| = 1;

            # Remove leading/trailing quotes, which
            # protects against a common funclet syntax error
            @$tokens[(@$tokens - 1)] =~ s/\"$//
                if (@$tokens[0] =~ s/^\"//);

            # Run it!

            if (! exec(@$tokens)) {
                my $die_msg;
                $die_msg .= "Can't execute command: $cmd\n";
                $die_msg .= "Error: $!\n";
                die $die_msg;
            }
        }

        # Return the pid
        $ret->{pid} = $pid;
        $MTT::DoCommand::pid = $pid;

    } else {
        # For no_execute, just print the command
        print join(" ", @$tokens) . "\n";

        $ret->{timed_out} = 0;
        $ret->{exit_status} = 0;
        $ret->{result_stdout} = "";
        $ret->{result_stderr} = "";
        return $ret;
    }

    # Accept two connections from the child

    accept(OUTread, $server_socket);
    accept(ERRread, $server_socket)
        if (!$merge_output);

    # Set the sockets to be non-blocking

    my $flags;
    $flags = fcntl(OUTread, F_GETFL, 0)
        or die "Can't get flags for the socket: $!\n";
    fcntl(OUTread, F_SETFL, $flags | O_NONBLOCK)
        or die "Can't set flags for the socket: $!\n";
    if (!$merge_output) {
        $flags = fcntl(ERRread, F_GETFL, 0)
            or die "Can't get flags for the socket: $!\n";
        fcntl(ERRread, F_SETFL, $flags | O_NONBLOCK)
            or die "Can't set flags for the socket: $!\n";
    }

    # Parent

    my (@out, @err);
    my ($backtrace, $got_backtrace);
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
        Debug("Timeout: $timeout - $end_time (vs. now: " . time() . ")\n");
    }
    my $last_over = 0;
    my $partial_out;
    my $partial_err;
    my $timeout_message;
    while ($done > 0) {
        if($pause_file) {
            my $paused_time = localtime();
            foreach my $item_pause_array (@pause_array) {
                while(-e $item_pause_array) {
                    print "found pause file: $item_pause_array\n";
                    print "paused since $paused_time\n";
                    sleep 2;
                }
            }
        }

        my $nfound = select($rout = $rin, undef, undef, $t);
        if (vec($rout, fileno(OUTread), 1) == 1) {
            # Cannot use normal <OUTread> here, per
            # http://perldoc.perl.org/functions/select.html.  Do a
            # sysread() with an arbitrarily large length (pipe is
            # set to non-blocking, so we're ok).
            my $data;
            my $len = sysread(OUTread, $data, 99999);
            if (0 == $len) {
                vec($rin, fileno(OUTread), 1) = 0;
                Debug("*** Child process stdout closed\n");
                --$done;
            } else {
                _append($data, $print_timestamp ? localtime() : "",
                        $max_stdout_lines, \@out, \$partial_out);
                Debug("$data");
            }
        }

        if (!$merge_output && vec($rout, fileno(ERRread), 1) == 1) {
            # See comment above - can't use <ERRread> here
            my $data;
            my $len = sysread(ERRread, $data, 99999);
            if (0 == $len) {
                vec($rin, fileno(ERRread), 1) = 0;
                Debug("*** Child process stderr closed\n");
                --$done;
            } else {
                _append($data, $print_timestamp ? localtime() : "",
                        $max_stderr_lines, \@err, \$partial_err);
                Debug("ERR:$data");
            }
        }

        # If we're running with a timeout, check to see if a) the
        # process is still running (i.e., stdout/stderr is still
        # open), and b) we're past the end time.
        if ($done > 0 && defined($end_time) && time() > $end_time) {
            my $over = time() - $end_time;

            # Note that we only want to backtrace/kill the process
            # *once*.  Consider: it is possible that we kill the
            # process tree, but then stdout/stderr are still draining,
            # and therefore we loop around here again *even though the
            # process tree is already dead*.  So put a little
            # do-this-only-once protection in here.
            if (!defined($timeout_message) && $over > $last_over) {
                Verbose("*** Past timeout of $timeout seconds by $over seconds\n");

                # Handle timeout file
                my $timeout_sentinel_file   = $MTT::Globals::Values->{docommand_timeout_notify_file};
                my $timeout_email_recipient = $MTT::Globals::Values->{docommand_timeout_notify_email};
                my $timeout_notify_timeout  = $MTT::Globals::Values->{docommand_timeout_notify_timeout};
                my $timeout_backtrace_program = $MTT::Globals::Values->{docommand_timeout_backtrace_program};
                my $timeout_before_backtrace_program = $MTT::Globals::Values->{docommand_timeout_before_each_backtrace_program};
                my $timeout_after_backtrace_program = $MTT::Globals::Values->{docommand_timeout_after_each_backtrace_program};
                my $pre_pernode = MTT::Values::Value($ini, "MTT", 'docommand_timeout_pernode_before_each_backtrace_program');
                my $sleep_time = MTT::Values::Value( $ini, "MTT", 'docommand_sleep' );
                if (!$sleep_time) {
                    $sleep_time = 120;
                }

                # If a backtrace program was specified, use it
                if (defined($timeout_backtrace_program) and !$got_backtrace) {
                    $backtrace = "";
                    if ( $timeout_before_backtrace_program ) {
                        foreach my $process (descendant_processes($pid)) {
                            my $p = $process->{pid};
                            my $c = $timeout_before_backtrace_program;
                            $c =~ s/%PID%/$p/g;
                            Debug("_pre_backtrace cmd: $c\n");
                            $backtrace .= "\n" . `$c` . "\n";
                        }
                    }

                    $backtrace .= _get_backtrace($timeout_backtrace_program, $pid, $pre_pernode);

                    if ( $timeout_after_backtrace_program ) {
                        foreach my $process (descendant_processes($pid)) {
                            my $p = $process->{pid};
                            my $c = $timeout_after_backtrace_program;
                            $c =~ s/%PID%/$p/g;
                            Debug("_post_backtrace cmd: $c\n");
                            $backtrace .= "\n" . `$c` . "\n";
                        }
                    }

                    # Do not collect a backtrace twice
                    $got_backtrace = 1;
                }

                if (defined($timeout_sentinel_file)) {

                    # Email someone, if an email address has been specified
                    _do_email_timeout_notification(
                        $cmd,
                        $pid,
                        $over,
                        $timeout_sentinel_file,
                        $timeout_email_recipient,
                        $timeout_notify_timeout,
                        $backtrace,
                        $sleep_time
                    );

                    $done = 0;
                }
                $timeout_message = _kill_proc_tree($pid, ${$tokens}[0]);

                # We don't care about the exit status if we timed out
                # -- fill it with a bogus value.
                $ret->{exit_status} = 0;

                # Set that we timed out.
                $ret->{timed_out} = 1;
            }
            $last_over = $over;

            # See if we're over the drain_timeout
            if ($over > $MTT::Globals::Values->{drain_timeout}) {
                Verbose("*** Past drain timeout; quitting\n");
                $done = 0;
            }
        }
    }
    Debug("*** Child process now dead\n");
    close OUTerr;
    close OUTread
        if (!$merge_output);

    # Process the last partial lines, if necessary
    if (defined($partial_out) && length($partial_out) > 0) {
        push(@out, $partial_out);
    }
    if (defined($partial_err) && length($partial_err) > 0) {
        push(@err, $partial_err);
    }

    # If we didn't timeout, we need to reap the process (timeouts will
    # have already been reaped).
    my $msg = "Command ";
    if (!$ret->{timed_out}) {
        waitpid($pid, 0);
        $ret->{exit_status} = $?;
        $msg .= "complete";
    } else {
        $ret->{exit_status} = 0;
        $msg .= "timed out";
        $msg .= " $timeout_message"
            if (defined($timeout_message));
    }
    $MTT::DoCommand::last_exit_status = $ret->{exit_status};

    # Was it signaled?
    if (wifsignaled($ret->{exit_status})) {
        my $s = wtermsig($ret->{exit_status});
        $msg .= ", signal $s";
        if (wcoredump($ret->{exit_status} & 128)) {
            if ($ret->{core_dump}) {
                $msg .= " (core dump)";
            }
        }
    }
    # No, it was not signaled
    else {
        my $s = wexitstatus($ret->{exit_status});
        $msg .= ", exit status: $s";
    }
    $msg .= "\n";
    Debug($msg);

    # Display timing info

    $ret->{stop_benchmark} = &MTT::Timer::stop();
    &MTT::Timer::print("Command: $cmd", $time_arg);
    ($ret->{elapsed_real}, 
     $ret->{elapsed_user},
     $ret->{elapsed_children_user},
     $ret->{elapsed_children_system},
     $ret->{elapsed_iters}) =
        @{timediff($ret->{stop_benchmark}, $ret->{start_benchmark})};

    # Return an anonymous hash containing the relevant data

    $ret->{result_stdout} = join('', @out);
    $ret->{result_stderr} = join('', @err),
        if (!$merge_output);

    # Tack on a backtrace, if we got one
    $ret->{result_stdout} .= $backtrace
        if ($got_backtrace);
    # Tack on timeout message, if we got one
    $ret->{result_stdout} .= $timeout_message
        if (defined($timeout_message));

    return $ret;
}

#--------------------------------------------------------------------------

# Send an email to notify of a hanging test
sub _do_email_timeout_notification {
    my ($cmd, $pid, $over, $timeout_sentinel_file, $timeout_email_recipient, $timeout_notify_timeout, $backtrace, $sleep_time) = @_;
    Debug("_do_email_timeout_notification got @_\n");

    my $timeout;
    my $end_time;
    if (defined($timeout_notify_timeout)) {
        $timeout = MTT::Util::parse_time_to_seconds($timeout_notify_timeout)
    }
    if (defined($timeout) && $timeout > 0) {
        $end_time = time() + $timeout;
    }

    my $username = getpwuid($<);
    my $hostname = MTT::Values::Functions::hostname();

    my $cmd_content = "";
    $cmd_content = MTT::Files::Slurp($cmd) if (-f $cmd);

    if (defined($timeout_email_recipient)) {

        my $from = "$username\@$hostname";
        my $subject = "An MTT command has exceeded the timeout limit *ACTION REQUIRED*";
        MTT::Mail::Send(
            $subject,
            $timeout_email_recipient,
            $from,
            "The following MTT command (pid $pid) is past the timeout of $timeout seconds by " .
               "$over seconds:" .
               "\n\t$cmd\n\n" .
               "\n\t$cmd_content\n\n" .

               "Here is a stack trace(s) from the forked a.out processes: " .
               "\n\t$backtrace\n\n" .

               "To force the MTT client to resume execution, remove the following file:" .
               "\n\t$timeout_sentinel_file\n\n"
        );
    }

    # Touch a sentinel file, and wait for the user to remove it
    my $duration = $end_time - time();
    open(TIMEOUT_SENTINEL_FILE, ">$timeout_sentinel_file");
    while (-e $timeout_sentinel_file) {
        Verbose("--> A timeout sentinel file was specified: $timeout_sentinel_file pid=$pid\n");
        Verbose("--> MTT will wait $duration seconds for the file to be removed or pid $pid to complete.\n")
            if ($duration > 0);

        my $pid_exists = kill 0, $pid;
        my $resume_tests = 0;

        if (!$pid_exists) {
            Verbose("--> Process completed somehow at " . localtime() . ", proceeding with tests\n");
            $resume_tests++;
        } else {
            my $matches = MTT::Files::Grep("zombie", "/proc/$pid/status");
            if (@$matches) {
                Verbose("--> Process become Zombie at " . localtime() . ", proceeding with tests\n");
                $resume_tests++;
            }
        }
        # Remove the timeout sentinel file, if a timeout notify timeout value is set
        if (defined($end_time) and time() > $end_time) {
            $resume_tests++;
        }

        if ($resume_tests) {
            unlink($timeout_sentinel_file);
            next;
        }

        my $now = localtime;
        Verbose("--> Sleeping for $sleep_time seconds ($now)...\n");
        sleep($sleep_time);
    }
    close(TIMEOUT_SENTINEL_FILE);
}

sub find_children {
    my ($pids, $start) = @_;

    my @ret;
    # Scan the PID list and see if any other PIDs list $start as their
    # PPID.  If so, save that PID and then recursively look for *that*
    # PID's children.
    foreach my $pid (sort(keys(%{$pids}))) {
        if ($pids->{$pid}->{ppid} == $start) {
            push(@ret, {
                pid => $pid,
                argv0 => $pids->{$pid}->{argv0},
                 });

            # Add this PID's descendants to the return array
            push(@ret, find_children($pids, $pid));
        }
    }

    return @ret;
}

sub descendant_processes {
    my ($base) = (@_, $$);
    open(PS, "ps -eo pid,ppid,cmd|") || die "Can't open ps";

    # Skip the title line
    <PS>;

    # Read all the data lines
    my $pids;
    while (<PS>) {
        # Grab the PID, PPID, and first token of the command
        $_ =~ m/(\d+)\s+(\d+)\s+(\S+)/;
        $pids->{$1} = {
            pid => $1,
            ppid => $2,
            argv0 => $3,
        };
    }
    close(PS);

    # Find all the descendants of the $base PID
    return find_children($pids, $base);
}

sub _get_backtrace {
    my ($program, $pid, $pre_pernode) = @_;
    Debug("_get_backtrace got: @_\n");

    my @valid_backtrace_programs = ("gdb", "padb", "gstack");

    my $ret;
    if ($program eq "gdb") {

        # Gather a GDB stack trace
        my $gdb_cmd;
        if (FindProgram(qw(gdb))) {

            # Create a temporary GDB command filename which will be
            # used to grab a stack trace in GDB batch mode
            my ($gdb_command_fh, $gdb_command_filename) = tempfile();
            print $gdb_command_fh "backtrace";
            close($gdb_command_fh);

            # Use ps -Af output to fetch the child pids,
            # and grab a stack trace from each one
            foreach my $process (descendant_processes($pid)) {
                my $p = $process->{pid};
                $gdb_cmd = "gdb - $p --command=$gdb_command_filename --batch";
                $ret .= "\n $gdb_cmd";
                $ret .= "\n" . `$gdb_cmd`;
            }

            # Remove the GDB batch command file
            unlink($gdb_command_filename);

        } else {
            Warning("MTT could not locate \"gdb\" to gather a backtrace\n");
        }

    } elsif ($program eq "padb") {

        if (FindProgram(qw(padb))) {

            my $padb_cmd = "padb --config-option rmgr=mpirun -X $pid";
            $ret .= "\n $padb_cmd";
            $ret .= "\n" . `$padb_cmd`;

        } else {
            Warning("MTT could not locate \"padb\" to gather a backtrace\n");
        }
    } elsif ($program eq "gstack") {
        if (FindProgram(qw(gstack))) {
            my @hosts = split(/,/,MTT::Values::Functions::env_hosts(2));
            my $return_basename = $MTT::Test::Run::test_executable_basename;
            foreach my $host (@hosts) {
                my $pids = `ssh $host pidof $return_basename`;
                if ( defined $pre_pernode ) {
                    $ret .= "\nnode=$host:\n";
                    $ret .= `ssh $host $pre_pernode`;
                }
                foreach my $pid  (split(' ',$pids)) {
                    $ret .= "\nnode=$host, pid=$pid:\n";
                    $ret .= `ssh $host gstack $pid`;
                }
            }
            Debug("Stacktrace: base name $return_basename\n");
            #foreach my $process (descendant_processes($pid))
            #{
            #    my $p = $process->{pid};
            #    my $gstack_cmd = "gstack $p";
            #    $ret .= "\n $gstack_cmd";
            #    $ret .= "\n" . `$gstack_cmd`;
            #}
        } else {
            Warning("MTT could not locate \"$program\" to gather a backtrace\n");
        }
        
    } else {
        Warning("MTT does not recognize \"$program\" as a backtrace program. " .
                "Please use one of the following: @valid_backtrace_programs");
    }

    Debug("_get_backtrace returning $ret\n");
    return $ret;
}

# run a Windows command and save the stdout / stderr

sub Win_Cmd {
    my ($merge_output, $cmd, $timeout, 
        $max_stdout_lines, $max_stderr_lines) = @_;

    Debug("Running Windows command: $cmd\n");

    # Return value

    my $ret;
    $ret->{timed_out} = 0;

    # Start the timer

    $ret->{start_benchmark} = &MTT::Timer::start();

    # Turn shell-quoted words ("foo bar baz") into individual tokens

    my $tokens = _quote_escape($cmd);

    my $pid;
    my @lines;
    if (! $no_execute) {

        if (($pid = fork()) == 0) {

            # Remove leading/trailing quotes, which
            # protects against a common funclet syntax error
            @$tokens[(@$tokens - 1)] =~ s/\"$//
                if (@$tokens[0] =~ s/^\"//);
            
            # Run it!

            print "running command: $cmd \n";

            if (! exec("@$tokens 1> stdout.txt 2> stderr.txt")) {
                my $die_msg;
                $die_msg .= "Can't execute command: $cmd\n";
                $die_msg .= "Error: $!\n";
                die $die_msg;
            }
        }

        # Return the pid
        $ret->{pid} = $pid;
    } else {
        # For no_execute, just print the command
        print join(" ", @$tokens) . "\n";

        $ret->{timed_out} = 0;
        $ret->{exit_status} = 0;
        $ret->{result_stdout} = "";
        $ret->{result_stderr} = "";
        return $ret;
    }

    # wait for the child processes to finish

    waitpid($pid, 0);
    
    open(OUTread, "<stdout.txt");
    open(ERRread, "<stderr.txt")
        if (!$merge_output);

    my (@out, @err);
    my $kid=0;

    my $t;
    my $end_time;
    if (defined($timeout) && $timeout > 0) {
        $t = 1;
        $end_time = time() + $timeout;
        Debug("Timeout: $timeout - $end_time (vs. now: " . time() . ")\n");
    }
    my $last_over = 0;

    while(<OUTread>) {
        if (($_ =~ /: error/) || ($_ =~ /: fatal error/)) {
            push(@out, $_);
            Debug($_);
        }
    }
    
    if (!$merge_output) {
        while(<ERRread>) {
            if (($_ =~ /: error/) || ($_ =~ /: fatal error/)) {
                push(@err, $_);
                Debug("ERR:$_");
            }
        }
    }

    close OUTerr;
    close OUTread
        if (!$merge_output);

    # If we didn't timeout, we need to reap the process (timeouts will
    # have already been reaped).
    my $msg = "Command ";
    if (!$ret->{timed_out}) {
        $ret->{exit_status} = $?;
        $msg .= "complete";
        print "return status: $ret->{exit_status}\n"
    } else {
        $ret->{exit_status} = 0;
        $msg .= "timed out";
        print "time out!"
    }
    $MTT::DoCommand::last_exit_status = $ret->{exit_status};

    # Was it signaled?
    if (wifsignaled($ret->{exit_status})) {
        my $s = wtermsig($ret->{exit_status});
        $msg .= ", signal $s";
        if (wcoredump($ret->{exit_status} & 128)) {
            if ($ret->{core_dump}) {
                $msg .= " (core dump)";
            }
        }
    }
    # No, it was not signaled
    else {
        my $s = wexitstatus($ret->{exit_status});
        $msg .= ", exit status: $s";
    }
    $msg .= "\n";
    Debug($msg);

    # Display timing info

    $ret->{stop_benchmark} = &MTT::Timer::stop();
    &MTT::Timer::print("Command: $cmd", $time_arg);
    ($ret->{elapsed_real}, 
     $ret->{elapsed_user},
     $ret->{elapsed_children_user},
     $ret->{elapsed_children_system},
     $ret->{elapsed_iters}) =
        @{timediff($ret->{stop_benchmark}, $ret->{start_benchmark})};

    # Return an anonymous hash containing the relevant data

    $ret->{result_stdout} = join('', @out);
    $ret->{result_stderr} = join('', @err),
        if (!$merge_output);

    return $ret;
}

# Return 1 if the string contains special shell characters
sub _contains_shell_script_characters {
    my ($cmd) = @_;
    return 1 if ($cmd =~ /^\s*\#\!|\>|\||\n/);
    return 0;
}

#--------------------------------------------------------------------------

sub CmdScript {
    my ($merge_output, $cmds, $timeout,
        $max_stdout_lines, $max_stderr_lines) = @_;

    Debug("Running command script: $cmds\n");

    my ($fh, $filename) = tempfile();

    # Remove leading/trailing quotes, which
    # protects against a common funclet syntax error.
    # We can safely do this since "foo" (literally, with
    # quotes included) would never be a valid shell command.
    $cmds =~ s/\"$// if ($cmds =~ s/^\"//);


	print $fh ":\n" if ($cmds !~ /^\s*\#\!/); # no shell specified - use default
    print $fh "$cmds\n";
    close($fh);
    chmod(0700, $filename);

    my $x = Cmd($merge_output, $filename, $timeout);
    unlink($filename);
    return $x;
}

#--------------------------------------------------------------------------

sub Chdir {

    # Translate ~ or * using the glob subroutine
    my($dir) = map { glob } @_;
    Debug("Chdir $dir\n");

    my $msg = "Can't chdir to $dir\n";
    if ($no_execute) {
        chdir $dir or warn $msg;
    } else {
        chdir $dir or die $msg;
    }
}

# Ensure to properly resolve a directory into its absolute name
sub ResolveDir {
    my ($dir) = @_;
    return File::Spec->rel2abs(glob($dir));
}

# Wrap Cwd::cwd() to ensure to check the return value properly (e.g.,
# if you're in a directory that was removed, cwd() returns "")
sub cwd {
    my $dir = Cwd::cwd();
    die "Current working directory does not exist!"
        if ($dir eq "");
    return $dir;
}

# Cached cwd's for Pushdir/Popdir
my @dir_stack;

# Just like the pushd shell command
sub Pushdir {
    my ($dir) = @_;

    # Translate ~ or * using the glob subroutine
    my $newdir = glob($dir);
    $dir = $newdir
        if ($newdir && $newdir ne $dir);
    Debug("Pushdir to $dir\n");

    my $cwd = ResolveDir(MTT::DoCommand::cwd());
    push(@dir_stack, $cwd);

    # In --no-execute mode, it is acceptable
    # if this chdir does not work
    if ($no_execute) {
        chdir $dir or warn "$dir: $!";
    } else {
        chdir $dir or die "$dir: $!";
    }
}

# Just like the popd shell command
sub Popdir {
    my $dir = pop(@dir_stack);
    Debug("Popdir to $dir\n");

    # In --no-execute mode, it is acceptable
    # if this chdir does not work
    if ($no_execute) {
        chdir $dir or warn "$dir: $!";
    } else {
        Error("Popdir: directory stack empty") if (! $dir);
        chdir $dir or die "$dir: $!";
    }
}

# Run a "pre" or "post" step before the main command of a given phase
sub RunStep {
    my ($force, $cmd, $timeout, $ini, $section, $step) = @_;

    my $timestamp_stdout = undef;
    if ($section and $ini) {
        $timestamp_stdout = Value($ini, $section, "print_timestamp");
        Debug "  print_timestamp=ON for $section\n";
    } else {
        Debug "  print_timestamp=OFF for $section\n";
    }


    # Prepare a return hash
    my $ret;
    $ret->{exit_status} = 0;

    # Steps can be code references
    if (ref($cmd) =~ /CODE/i) {

        my $x = &$cmd;
        if (!$x) {
            Verbose("  Warning: step $step FAILED\n");
            $ret->{exit_status} = 1;
        }

    # Steps can be MTT funclets
    } elsif ($cmd =~ /^\s*&/) {

        my $x = EvaluateString($cmd, $ini, $section);
        if (!$x) {
            Verbose("  Warning: step $step FAILED\n");
            $ret->{exit_status} = 1;
        }

    # Steps can be shell commands (or scripts)
    } else {
    
        # Do any needed @var@ expansions
        $cmd = EvaluateString($cmd, $ini, $section);

        Debug("Running step: $step: $cmd / timeout $timeout\n");
        $ret = MTT::DoCommand::Cmd($force, $cmd, $timeout,undef,undef,$timestamp_stdout);
    }

    return $ret;
}

#--------------------------------------------------------------------------

# See perlvar(1)
sub wifexited {
    return !wifsignaled(@_);
}

#--------------------------------------------------------------------------

# See perlvar(1)
sub wexitstatus {
    my ($val) = @_;
    return ($val >> 8);
}

#--------------------------------------------------------------------------

# See perlvar(1)
sub wifsignaled {
    my ($val) = @_;
    return (0 != ($val & 127)) ? 1 : 0;
}

#--------------------------------------------------------------------------

# See perlvar(1)
sub wtermsig {
    my ($val) = @_;
    return ($val & 127);
}

#--------------------------------------------------------------------------

# See perlvar(1)
sub wcoredump {
    my ($val) = @_;
    return (0 != ($val & 128)) ? 1 : 0;
}

#--------------------------------------------------------------------------

# See perlvar(1)
sub wsuccess {
    my ($val) = @_;
    return (1 == wifexited($val) && 0 == wexitstatus($val)) ? 1 : 0;
}

#--------------------------------------------------------------------------

# Simple wrapper to avoid the same "if" test all throughout the code base
sub exit_value {
    my ($val) = @_;
    return (wifexited($val) ? wexitstatus($val) : -1);
}

#--------------------------------------------------------------------------

# Simple wrapper to avoid the same "if" test all throughout the code base
sub exit_signal {
    my ($val) = @_;
    return (wifsignaled($val) ? wtermsig($val) : -1);
}

1;
