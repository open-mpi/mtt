#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Trim;

use strict;

use Config::IniFiles;
use Data::Dumper;
use File::Basename;
use MTT::Messages;
use MTT::Values;
use MTT::Globals;
use MTT::Test;
use MTT::MPI;

#--------------------------------------------------------------------------

# Exported constant
use constant {
    TRIM_KEY => "TO_BE_TRIMMED",
};

#--------------------------------------------------------------------------

# Trim old trees after a run
sub Trim {
    my ($ini, $source_dir, $install_dir) = @_;

    Verbose("*** Trim phase starting\n");

    # Go in "reverse" order:
    #
    # - delete expired failed test runs
    # - delete expired successful test runs
    # - delete expired failed test builds
    # - delete expired successful test builds
    # - delete expired failed MPI installs
    # - delete expired successful MPI installs
    # - delete expired failed MPI gets
    # - delete expired successful MPI gets
    #
    # Do it in this order because deleting, for example, test runs may
    # orphan some test builds, MPI installs, and MPI gets.  If we did
    # the deleting the other way around, then we'd have to go back and
    # look for the orphans to delete them.

    _trim_test_runs($install_dir);
    _trim_test_builds($install_dir);
    _trim_test_gets($source_dir);
    _trim_mpi_installs($install_dir);
    _trim_mpi_gets($source_dir);

    Verbose("*** Trim phase complete\n");
}

#--------------------------------------------------------------------------

sub _trim_test_runs {
    my $install_dir = shift;
}

#--------------------------------------------------------------------------

sub _trim_test_builds {
    my $install_dir = shift;
}

#--------------------------------------------------------------------------

sub _trim_test_gets {
    my $source_dir = shift;
}

#--------------------------------------------------------------------------

sub _trim_mpi_installs {
    my $install_dir = shift;
}

#--------------------------------------------------------------------------

sub _trim_mpi_gets {
    my $source_dir = shift;
}

#--------------------------------------------------------------------------

sub _timestamp_compare {
    my ($a, $b) = @_;
    return ($a->{timestamp} - $b->{timestamp});
}

1;
