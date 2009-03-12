#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2008 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007-2008 Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2009      High Performance Computing Center Stuttgart, 
#                         University of Stuttgart.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::Common::Do_step;

use strict;
use Data::Dumper;
use MTT::DoCommand;
use MTT::Messages;
use MTT::FindProgram;
use MTT::Values;
use MTT::Files;

sub do_step {
    my ($config, $cmd, $mss, $dir) = @_;

    # Prepare return value. Start with an empty, but defined hash
    my $ret = {};
    my $result_stdout;
    my $result_stderr;

    # As long as this pattern is emitted during the step, keep
    # attempting to re-start the step ("restart_attempts" times)
    my $restart_on_pattern;
    my $restart_attempts_max = 500;
    my $restart_attempts = 0;
    if (defined($config->{restart_on_pattern})) {
        $restart_on_pattern = $config->{restart_on_pattern};
    } else {
        $restart_attempts_max = -1;
    }

    # Hash keys and INI params do not contain spaces. Change them to underscores.
    my $hash_key = $cmd;
    $hash_key =~ s/ /_/g;

    # Optional path for program
    if (defined($dir)) {
        $cmd = "$dir/$cmd";
    }

    my $arguments_key = "${hash_key}_arguments";
    my $stdout_key = "${hash_key}_stdout";
    my $stderr_key = "${hash_key}_stderr";
    my $skip_key = "skip_${hash_key}";
    my $before_cmd_key = "before_${hash_key}";
    my $after_cmd_key = "after_${hash_key}";

    if (defined($config->{$before_cmd_key})) {
        _run_step($config->{$before_cmd_key}, $before_cmd_key);
    }

    if (!$config->{$skip_key}) {

        my $i = 0;
        do {
            Debug("Restarting $cmd (restart attempt #$i\n") if ($i++ gt 0);
            $ret = MTT::DoCommand::Cmd($mss,
                        "$cmd $config->{$arguments_key}", -1,
                         $config->{stdout_save_lines},
                         $config->{stderr_save_lines});

            # Add header line to stdout
            if (defined($ret->{result_stdout}) &&
                $ret->{result_stdout} !~ /^\s*$/) {
                $result_stdout = "--- $cmd $config->{$arguments_key} result_stdout";
                $result_stdout .= "/result_stderr"
                    if ($mss);
                $result_stdout .= " ---\n$ret->{result_stdout}";
            }

            # Add header line to stderr
            if (!$mss && defined($ret->{result_stderr}) &&
                $ret->{result_stderr} !~ /^\s*$/) {
                $result_stderr = "--- $cmd $config->{$arguments_key} result_stderr ---\n$ret->{result_stderr}";
            }

        # Repeat *only* if $restart_on_pattern is defined
        } while (!MTT::DoCommand::wsuccess($ret->{exit_status}) and
                 (defined($restart_on_pattern) &&
                  ($ret->{result_stderr} =~ /$restart_on_pattern/i or
                   $ret->{result_stdout} =~ /$restart_on_pattern/i) and
                  $restart_attempts++ < $restart_attempts_max));

        # If fail, save the results in {result_stdout} and
        # {result_stderr}.
        if (!MTT::DoCommand::wsuccess($ret->{exit_status})) {
            $ret->{result_message} = "\"$cmd $config->{$arguments_key}\" failed -- skipping this build.";
            # Put the output of the failure into $ret so that it gets
            # reported
            $ret->{result_stdout} = $result_stdout
                if (defined($result_stdout));
            $ret->{result_stderr} = $result_stderr
                if (!$mss && defined($result_stderr));
            $ret->{exit_status} = $ret->{exit_status};
            $ret->{fail} = 1;
        }

        # If succeed, keep the stdout/stderr in their respective hash
        # keys for this step.
        else {
            if (defined($result_stdout)) {
                delete $ret->{result_stdout};
                $ret->{$stdout_key} = $result_stdout;
            }
            if (!$mss && defined($result_stderr)) {
                delete $ret->{result_stderr};
                $ret->{$stderr_key} = $result_stderr;
            }
        }
    } else {
        Debug("Skippping '$cmd' step.\n");
    }

    if (defined($config->{$after_cmd_key})) {
        _run_step($config->{$after_cmd_key}, $after_cmd_key);
    }

    return $ret;
}

sub _run_step {
    my ($cmd, $step) = @_;
    return MTT::DoCommand::RunStep(1, $cmd, 30, undef, undef, $step);
}

1;
