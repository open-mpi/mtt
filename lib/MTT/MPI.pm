#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2010 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

########################################################################

package MTT::MPI;

use strict;
use MTT::Files;
use MTT::Messages;
use MTT::Util;

#--------------------------------------------------------------------------

# Exported MPI sources handle
our $sources;

# Exported MPI install handle
our $installs;

#--------------------------------------------------------------------------

# Filename where list of MPI sources is kept
my $sources_data_filename = "mpi_sources";

# Filename where list of MPI installs is kept
my $installs_data_filename = "mpi_installs";

# Filename extension for all the Dumper data files
my $data_filename_extension = "dump";

#--------------------------------------------------------------------------

use Data::Dumper;
sub LoadSources {
    my ($dir) = @_;

    # Explicitly delete/replace anything that was there
    $MTT::MPI::sources = 
        MTT::Files::load_dumpfiles(2, glob("$dir/$sources_data_filename-*.$data_filename_extension"));

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
    my ($dir, $key, $name) = @_;

    # We write individual dump files for each section so that multiple
    # readers / writers can be active in the scratch tree
    # simultaneously.  So write *just the desired section* to the dump
    # file.
    my $d;
    $d->{$key} = $MTT::MPI::sources->{$key};

    my $file = "$dir/$sources_data_filename-$name.$data_filename_extension";
    MTT::Files::save_dumpfile($file, $d);
}

#--------------------------------------------------------------------------

sub LoadInstalls {
    my ($dir) = @_;

    # Explicitly delete/replace anything that was there
    $MTT::MPI::installs = 
        MTT::Files::load_dumpfiles(3, glob("$dir/$installs_data_filename-*.$data_filename_extension"));

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
    my ($dir, $mpi_name, $mpi_version, $install_name) = @_;

    # We write individual dump files for each section so that multiple
    # readers / writers can be active in the scratch tree
    # simultaneously.  So write *just the desired section* to the dump
    # file.
    my $d;
    $d->{$mpi_name}->{$mpi_version}->{$install_name} = 
        $MTT::MPI::installs->{$mpi_name}->{$mpi_version}->{$install_name};

    my $f = "$mpi_name.$mpi_version.$install_name";
    my $file = "$dir/$installs_data_filename-$f.$data_filename_extension";
    MTT::Files::save_dumpfile($file, $d);
}

1;
