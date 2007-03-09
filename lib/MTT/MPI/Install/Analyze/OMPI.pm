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

package MTT::MPI::Install::Analyze::OMPI;

use strict;
use Cwd;
use Data::Dumper;
use MTT::DoCommand;
use MTT::Messages;
use MTT::FindProgram;
use MTT::Values;
use MTT::Files;

#--------------------------------------------------------------------------

sub _find_bindings {
    my ($bindir, $libdir, $lang) = @_;

    my %ENV_SAVE = %ENV;
    if (exists($ENV{LD_LIBRARY_PATH})) {
        $ENV{LD_LIBRARY_PATH} = "$libdir:$ENV{LD_LIBRARY_PATH}";
    } else {
        $ENV{LD_LIBRARY_PATH} = "$libdir";
    }

    open INFO, "$bindir/ompi_info --parsable|";
    my @have = grep { /^bindings:$lang:/ } <INFO>;
    chomp @have;
    close INFO;

    %ENV = %ENV_SAVE;

    return ($have[0] =~ /^bindings:${lang}:yes/) ? "1" : "0";
}

#--------------------------------------------------------------------------

sub Install {
    my ($ini, $section, $config) = @_;
    my $x;
    my $result_stdout;
    my $result_stderr;

    # Prepare $ret

    my $ret;
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{exit_status} = 0;

    # Grab installdir parameter

    $ret->{installdir} = $config->{module_data}->{installdir};
    $ret->{bindir} = "$ret->{installdir}/bin";
    $ret->{libdir} = "$ret->{installdir}/lib";

    # Set which bindings were compiled

    $ret->{c_bindings} = 1;
    Debug("Have C bindings: 1\n");
    $ret->{cxx_bindings} = _find_bindings($ret->{bindir},
                                          $ret->{libdir}, "cxx");
    Debug("Have C++ bindings: $ret->{cxx_bindings}\n"); 
    $ret->{f77_bindings} = _find_bindings($ret->{bindir},
                                          $ret->{libdir}, "f77");
    Debug("Have F77 bindings: $ret->{f77_bindings}\n"); 
    $ret->{f90_bindings} = _find_bindings($ret->{bindir},
                                          $ret->{libdir}, "f90");
    Debug("Have F90 bindings: $ret->{f90_bindings}\n"); 

    return $ret;
}

1;
