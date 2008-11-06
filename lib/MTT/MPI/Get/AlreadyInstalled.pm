#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2008 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007-2008 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::MPI::Get::AlreadyInstalled;

use strict;
use File::Basename;
use Data::Dumper;
use MTT::Messages;
use MTT::Files;
use MTT::FindProgram;
use MTT::Values;
use MTT::DoCommand;
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
                "I will search your path for an MPI ...\n")
            if (defined($installdir));

        my $program = FindProgram(qw(mpicc mpiexec mpirun));

        # Fail if we did not find an MPI
        if (! -e $program) {
            my $error = "I did not find an MPI in your PATH.\n";
            $ret->{result_message} = "Failed; $error";
            $ret->{test_result} = MTT::Values::FAIL;
            return $ret;
        }

        $installdir = dirname($program);

        # Protect against this common user error
        $installdir =~ s/bin\/?$//;
    }
    Verbose("   Using MPI in: $installdir\n");

    $ret->{module_data}->{installdir} = $installdir;

    my $mpi = Value($ini, $section, "alreadyinstalled_mpi_type");
    if (!defined($mpi)) {
        # by default lets guess that it is OMPI
        $mpi = "OMPI";
        Warning("alreadyinstalled_mpi_type was not specified, defaulting to \"$mpi\".\n");
    }
    # Get a version string (E.g., Open MPI r#)
    my $version = Value($ini, $section, "alreadyinstalled_version");
    if (!defined($version) && $mpi =~ /OMPI/i) {
        $version = MTT::Values::Functions::MPI::OMPI::get_version("$installdir/bin");
    }
    if (!defined($version) && $mpi =~ /MVAPICH/i) {
        $version = MTT::Values::Functions::MPI::MVAPICH::get_version("$installdir/bin");
    }
    if (!defined($version)) {
        Warning("Could not get an MPI version string, I'll create one based on your alreadyinstalled_dir parameter.\n");
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
    return MTT::DoCommand::cwd();
}

1;
