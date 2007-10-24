#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2007 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Common::GNU_Install;

use strict;
use Cwd;
use Data::Dumper;
use MTT::DoCommand;
use MTT::Messages;
use MTT::FindProgram;
use MTT::Values;
use MTT::Files;

#--------------------------------------------------------------------------

sub Install {
    my ($config) = @_;

    my $x;
    my $result_stdout;
    my $result_stderr;

    # Prepare $ret

    my $ret;
    $ret->{test_result} = MTT::Values::FAIL;
    $ret->{exit_status} = 0;

    # Run configure

    if (!$config->{skip_configure}) {
        $x = MTT::DoCommand::Cmd(1, "$config->{configdir}/configure $config->{configure_arguments} --prefix=$config->{installdir}", -1, $config->{stdout_save_lines}, $config->{stderr_save_lines});
        $result_stdout = $x->{result_stdout} ? "--- Configure result_stdout/result_stderr ---\n$x->{result_stdout}" :
            undef;
        if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
            $ret->{result_message} = "Configure failed -- skipping this build";
            # Put the output of the failure into $ret so that it gets
            # reported (result_stdout/result_stderr was combined into just result_stdout)
            $ret->{result_stdout} = $result_stdout;
            $ret->{exit_status} = $x->{exit_status};
            $ret->{fail} = 1;
            return $ret;
        }
        # We don't need this in the main result_stdout
        $ret->{configure_stdout} = $result_stdout;
    }

    # Build it

    my $all_target = "all";
    $all_target = ""
        if (!$config->{use_all_target});

    # Do "make clean" (only needed for multi-lib builds)
    $x = MTT::DoCommand::Cmd($config->{merge_stdout_stderr}, "make clean", -1, 0) if ($config->{make_clean});

    # As long as this pattern is emitted during the build, keep
    # attempting to re-make ("restart_attempts" times)
    my $restart_on_pattern;
    my $restart_attempts_max = 500;
    my $restart_attempts = 0;
    if (defined($config->{restart_on_pattern})) {
        $restart_on_pattern = $config->{restart_on_pattern};
    } else {
        $restart_attempts_max = -1;
    }

    my $i = 0;
    my $target = $all_target;
    do {
        # Do "make all"
        Debug("Restarting make $target (restart attempt #$i\n") if ($i++ gt 0);
        $x = MTT::DoCommand::Cmd($config->{merge_stdout_stderr}, "make $config->{make_all_arguments} $all_target", -1, $config->{stdout_save_lines});
    } while (!MTT::DoCommand::wsuccess($x->{exit_status}) and 
            ($x->{result_stderr} =~ /$restart_on_pattern/i or 
             $x->{result_stdout} =~ /$restart_on_pattern/i) and 
             $restart_attempts++ < $restart_attempts_max);

    $result_stdout = undef;
    if ($x->{result_stdout}) {
        $result_stdout = "--- \"make $all_target ";
        $result_stdout .= "result_stdout"
            if ($x->{result_stdout});
        $result_stdout .= "/result_stderr"
            if ($config->{merge_stdout_stderr});
        $result_stdout .= " ---\n$x->{result_stdout}";
    }
    $result_stderr = $x->{result_stderr} ? 
        "--- \"make $all_target\" result_stderr ---\n$x->{result_stderr}" : 
        undef;

    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        $ret->{result_message} = "Failed to build: make $config->{make_all_arguments} $all_target";
        # Put the output of the failure into $ret so that it gets
        # reported (result_stdout/result_stderr *may* be separated, so assign them
        # both -- if they were combined, then $result_stderr will be empty)
        $ret->{result_stdout} = $result_stdout;
        $ret->{result_stderr} = $result_stderr;
        $ret->{exit_status} = $x->{exit_status};
        $ret->{fail} = 1;
        return $ret;
    }
    $ret->{make_all_stdout} = $result_stdout;
    $ret->{make_all_stderr} = $result_stderr;

    # Do we want to run "make check"?  If so, make sure a valid TMPDIR
    # exists.  Also, merge the result_stdout/result_stderr because we really only
    # want to see it if something fails (i.e., it's common to display
    # junk to result_stderr during "make check"'s normal execution).

    if ($config->{make_check} == 1) {
        my %ENV_SAVE = %ENV;
        $ENV{TMPDIR} = "$config->{installdir}/tmp";
        mkdir($ENV{TMPDIR}, 0777);
        # The intent here is just to ensure that the LD_LIBRARY_PATH
        # in the environment does not point to shared libraries
        # outside of MTT's scope that would interfere with "make
        # check" (e.g., another libmpi.so outside of MTT).  Just
        # prepend our own $libdir to LD_LIBRARY_PATH and hope that
        # that's Good Enough.  :-)
        if (exists($ENV{LD_LIBRARY_PATH})) {
            $ENV{LD_LIBRARY_PATH} = "$config->{libdir}:$ENV{LD_LIBRARY_PATH}";
        } else {
            $ENV{LD_LIBRARY_PATH} = "$config->{libdir}";
        }

        $i = 0;
        $target = "check";
        Debug("Running make $target\n");
        do {
            Debug("Restarting make $target (restart attempt #$i\n") if ($i++ gt 0);
            $x = MTT::DoCommand::Cmd(1, "make $target", -1, $config->{stdout_save_lines}, $config->{stderr_save_lines});
        } while (!MTT::DoCommand::wsuccess($x->{exit_status}) and 
                ($x->{result_stderr} =~ /$restart_on_pattern/i or 
                 $x->{result_stdout} =~ /$restart_on_pattern/i) and 
                 $restart_attempts++ < $restart_attempts_max);

        %ENV = %ENV_SAVE;

        $result_stdout = "--- \"make check\" result_stdout ---\n$x->{result_stdout}"
            if ($x->{result_stdout});
        if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
            $ret->{result_message} = "Failed to make check";
            # Put the output of the failure into $ret so that it gets
            # reported (result_stdout/result_stderr were combined)
            $ret->{result_stdout} = $x->{result_stdout};
            $ret->{exit_status} = $x->{exit_status};
            $ret->{fail} = 1;
            return $ret;
        }
        $ret->{make_check_stdout} = $result_stdout;
    } else {
        Debug("Not running make check\n");
    }

    # Install it.  Merge the result_stdout/result_stderr because we
    # really only want to see the output if something went wrong.
    # Things sent to result_stderr are common during "make install"
    # (e.g., notices about re-linking libraries when they are
    # installed)

    $i = 0;
    $target = "install";
    do {
        Debug("Restarting make $target (restart attempt #$i\n") if ($i++ gt 0);
        $x = MTT::DoCommand::Cmd(1, "make $target", -1, $config->{stdout_save_lines}, $config->{stderr_save_lines});
    } while (!MTT::DoCommand::wsuccess($x->{exit_status}) and 
            ($x->{result_stderr} =~ /$restart_on_pattern/i or 
             $x->{result_stdout} =~ /$restart_on_pattern/i) and 
             $restart_attempts++ < $restart_attempts_max);

    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        $ret->{result_stdout} .= "--- \"make $target\" result_stdout ---\n$x->{result_stdout}"
            if ($x->{result_stdout});
        $ret->{result_message} = "Failed to make $target";
        # Put the output of the failure into $ret so that it gets
        # reported (result_stdout/result_stderr were combined)
        $ret->{result_stdout} = $x->{result_stdout};
        $ret->{exit_status} = $x->{exit_status};
        $ret->{fail} = 1;
        return $ret;
    }
    $ret->{make_install_stdout} = $result_stdout;

    # All done!

    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";
    $ret->{exit_status} = $x->{exit_status};
    Debug("Build was a success\n");

    return $ret;
}

1;
