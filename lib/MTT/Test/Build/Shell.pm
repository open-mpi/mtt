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

package MTT::Test::Build::Shell;

use strict;
use Cwd;
use File::Temp qw(tempfile);
use MTT::Messages;
use MTT::DoCommand;
use MTT::Values;

#--------------------------------------------------------------------------

sub Build {
    my ($ini, $mpi_install, $config) = @_;
    my $ret;

    Debug("Building Shell\n");
    $ret->{success} = 0;

    # Now run that file -- remove it when done, regardless of the outcome
    my $cmd = Value($ini, $config->{section_name}, "build_command");
    my $x = MTT::DoCommand::CmdScript(!$config->{separate_stdout_stderr};
                                      $cmd);
    if ($x->{status} != 0) {
        $ret->{result_message} = "Shell: command failed \"$cmd\"\n";
        $ret->{stdout} = $x->{stdout};
        $ret->{stderr} = $x->{stderr}
            if ($x->{stderr});
        $ret->{result_message} = "Failed";
        return $ret;
    }

    # All done
    $ret->{stdout} = $x->{stdout};
    $ret->{stderr} = $x->{stderr};
    $ret->{success} = 1;
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
