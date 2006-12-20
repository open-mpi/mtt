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

    # Rebuild the refcounts
    foreach my $get_key (keys(%{$MTT::MPI::sources})) {
        my $get = $MTT::MPI::sources->{$get_key};

        foreach my $version_key (keys(%{$get})) {
            my $version = $get->{$version_key};
            # Set this refcount to 0, because no one is using it yet.
            $version->{refcount} = 0;
        }
    }
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

    # Rebuild the refcounts
    foreach my $get_key (keys(%{$MTT::MPI::installs})) {
        my $get = $MTT::MPI::installs->{$get_key};

        foreach my $version_key (keys(%{$get})) {
            my $version = $get->{$version_key};

            foreach my $install_key (keys(%{$version})) {
                my $install = $version->{$install_key};
                # Set the refcount of this MPI install to 0.
                $install->{refcount} = 0;

                # Bump the refcount of the corresponding MPI get.
                if (exists($MTT::MPI::sources->{$get_key}) &&
                    exists($MTT::MPI::sources->{$get_key}->{$version_key})) {
                    ++$MTT::MPI::sources->{$get_key}->{$version_key}->{refcount};
                }
            }
        }
    }
}

#--------------------------------------------------------------------------

sub SaveInstalls {
    my ($dir) = @_;

    MTT::Files::save_dumpfile("$dir/$installs_data_filename", 
                              $MTT::MPI::installs);
}

1;
