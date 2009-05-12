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

package MTT::Common::Cmake;
my $package = ModuleName(__PACKAGE__);

use strict;
use MTT::Messages;
use MTT::Values;
use MTT::Common::Do_step;

#--------------------------------------------------------------------------

# Do the following steps:
#   [ ] cmake -G "generator" -D configure_arguments source_path
#   [ ] devenv OpenMPI.sln /build
sub Install {
    my ($config) = @_;

    my $x;
    my $result_stdout;
    my $result_stderr;

    # Prepare $ret
    my $ret;
    $ret->{test_result} = MTT::Values::FAIL;
    $ret->{exit_status} = 0;

    # On windows, do the following steps:

    # prepare the windows style prefix.
    # replace '/cygdrive/x/' with 'x:/'
    my $win_prefix = substr ($config->{installdir},10,1) . ":" . substr ($config->{installdir},11);

    # generate Visual Studio solution files
    # use 'script' to redirect MS command output
    $x = MTT::Common::Do_step::do_step($config,
                                        "cmake $config->{configure_arguments} -D CMAKE_INSTALL_PREFIX:PATH=$win_prefix . ", 
                                        $config->{merge_stdout_stderr});

    # Overlapping keys in $x override $ret
    %$ret = (%$ret, %$x);
    return $ret if (!MTT::DoCommand::wsuccess($ret->{exit_status}));

    # compile the whole solution
    $x = MTT::Common::Do_step::do_step($config, "devenv.com *.sln /build debug ",
                                        $config->{merge_stdout_stderr});
    %$ret = (%$ret, %$x);
    return $ret if (!MTT::DoCommand::wsuccess($ret->{exit_status}));

    # install to the prefix dir
    $x = MTT::Common::Do_step::do_step($config, "devenv.com *.sln /project INSTALL.vcproj /build ",
                                        $config->{merge_stdout_stderr});
    %$ret = (%$ret, %$x);
    return $ret if (!MTT::DoCommand::wsuccess($ret->{exit_status}));

    # All done!
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";
    Debug("Build was a success\n");

    return $ret;
}

1;
