#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2007 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Build::Shell;

use strict;
use Cwd;
use File::Temp qw(tempfile);
use MTT::Messages;
use MTT::DoCommand;
use MTT::Values;
use Data::Dumper;

#--------------------------------------------------------------------------

sub Build {
    my ($ini, $mpi_install, $config) = @_;
    my $ret;

    Debug("Building Shell\n");
    $ret->{test_result} = MTT::Values::FAIL;

    # Now run that file -- remove it when done, regardless of the outcome
    my $cmd = Value($ini, $config->{full_section_name}, "shell_build_command");
    my $x = MTT::DoCommand::CmdScript(!$config->{separate_stdout_stderr},
                                      $cmd, -1,
                                      $config->{stdout_save_lines},
                                      $config->{stderr_save_lines});
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        $ret->{result_message} = "Shell: command failed \"$cmd\"";
        $ret->{result_message} .= " (timed out)"
            if ($x->{timed_out});
        $ret->{exit_status} = $x->{exit_status};
        $ret->{result_stdout} = $x->{result_stdout};
        $ret->{result_stderr} = $x->{result_stderr}
            if ($x->{result_stderr});
        return $ret;
    }

    # All done
    $ret->{result_stdout} = $x->{result_stdout};
    $ret->{result_stderr} = $x->{result_stderr};
    $ret->{exit_status} = 0;
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
