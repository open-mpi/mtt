#!/usr/bin/env perl
#
# Copyright (c) 2004-2005 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2004-2005 The Trustees of the University of Tennessee.
#                         All rights reserved.
# Copyright (c) 2004-2005 High Performance Computing Center Stuttgart, 
#                         University of Stuttgart.  All rights reserved.
# Copyright (c) 2004-2005 The Regents of the University of California.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Build::shell;

use strict;
use Cwd;
use File::Temp qw(tempfile);
use MTT::Messages;
use MTT::DoCommand;
use MTT::Values;

#--------------------------------------------------------------------------

sub Build {
    my ($ini, $section, $mpi, $config) = @_;
    my $ret;

    Debug("Building Shell: [$section]\n");
    $ret->{success} = 0;

    # Now run that file -- remove it when done, regardless of the outcome
    my $cmd = Value($ini, $section, "build_command");
    my $x = MTT::DoCommand::CmdScript(1, $cmd);
    if ($x->{status} != 0) {
        $ret->{result_message} = "Shell: command failed \"$cmd\"\n";
        $ret->{stdout} = $x->{stdout};
        return $ret;
    }

    # All done
    $ret->{stdout} = $x->{stdout};
    $ret->{success} = 1;
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
