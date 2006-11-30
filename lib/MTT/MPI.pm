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

########################################################################

package MTT::MPI;

use strict;
use MTT::MPI::Get;
use MTT::MPI::Install;
use MTT::Files;

#--------------------------------------------------------------------------

# Exported MPI sources handle
our $sources;

# Exported MPI install handle
our $installs;

#--------------------------------------------------------------------------

# Filename where list of MPI sources is kept
my $sources_data_filename = "mpi_sources.dump";

# Filename where list of MPI installs is kept
my $installs_data_filename = "mpi_installs.dump";

#--------------------------------------------------------------------------

# This function exists solely so that we don't have to invoke
# MTT::MPI::Get::Get in the top level
sub Get {
    return MTT::MPI::Get::Get(@_);
}

#--------------------------------------------------------------------------

# This function exists solely so that we don't have to invoke
# MTT::MPI::Install::Install in the top level
sub Install {
    return MTT::MPI::Install::Install(@_);
}

#--------------------------------------------------------------------------

use Data::Dumper;
sub LoadSources {
    my ($dir) = @_;

    # Explicitly delete anything that was there
    $MTT::MPI::sources = undef;

    # If the file exists, read it in
    my $data;
    MTT::Files::load_dumpfile("$dir/$sources_data_filename", \$data);
    $MTT::MPI::sources = $data->{VAR1};
}

#--------------------------------------------------------------------------

sub SaveSources {
    my ($dir) = @_;

    MTT::Files::save_dumpfile("$dir/$sources_data_filename", 
                              $MTT::MPI::sources);
}

#--------------------------------------------------------------------------

sub LoadInstalls {
    my ($dir) = @_;

    # Explicitly delete anything that was there
    $MTT::MPI::installs = undef;

    # If the file exists, read it in
    my $data;
    MTT::Files::load_dumpfile("$dir/$installs_data_filename", \$data);
    $MTT::MPI::installs = $data->{VAR1};
}

#--------------------------------------------------------------------------

sub SaveInstalls {
    my ($dir) = @_;

    MTT::Files::save_dumpfile("$dir/$installs_data_filename", 
                              $MTT::MPI::installs);
}

1;
