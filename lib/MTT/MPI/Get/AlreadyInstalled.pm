#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::MPI::Get::AlreadyInstalled;

use strict;
use Cwd;
use File::Basename;
use Data::Dumper;
use MTT::Messages;
use MTT::Files;
use MTT::FindProgram;
use MTT::Values;
use MTT::FindProgram;
use File::Basename;

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $force) = @_;

    my $ret;
    my $data;
    $ret->{test_result} = MTT::Values::FAIL;

    # There are no sources retrieved by this module, so we
    # can always say "true" here
    $ret->{have_new} = 1;

    # (No need to fetch MPI sources here ...)

    # The user specifies the installed location
    my $installdir = Value($ini, $section, "alreadyinstalled_dir");

    # If they do not, search the user's PATH for an MPI
    if (! -e $installdir) {
        Warning("A non-existent \"installdir\" parameter was provided,\n" .
                "I will search your path for an MPI ...\n");

        my $program = FindProgram(qw(mpicc mpiexec mpirun));

        # Fail if we did not find an MPI
        if (! -e $program) {
            my $error = "I did not find an MPI in your PATH.\n";
            $ret->{result_message} = "Failed; $error";
            $ret->{test_result} = MTT::Values::FAIL;
            return $ret;
        }

        $installdir = dirname($program);
        $installdir =~ s/bin\/?$//;
    }
    Verbose("Using MPI in $installdir\n");

    $ret->{module_data}->{installdir} = $installdir;

    # Get a version string (E.g., Open MPI r#)
    my $version = _get_ompi_version($installdir);

    if (! $version) {
        Warning("Could not get an MPI version string, I'll create one based
                 on your installdir parameter.\n");
        $version = $installdir;
        $version =~ s/\//_/g;
    }
    $ret->{version} = $version;

    my $package = __PACKAGE__;

    # All done
    Debug(">> $package complete\n");
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";
    $ret->{prepare_for_install} = "${package}::PrepareForInstall";
    return $ret;
} 

#--------------------------------------------------------------------------

# NoOp
sub PrepareForInstall {
    return cwd();
}

# Get the OMPI version string from ompi_info
sub _get_ompi_version {
    my $installdir = shift;

    open INFO, "$installdir/bin/ompi_info --parsable|";

    while (<INFO>) {
        print;
        if (/ompi:version:full:(.*)$/) {
            Debug(">> " . (caller(0))[3] . " returning $1\n");
            return $1;
        }
    }
    return undef;
}

1;
