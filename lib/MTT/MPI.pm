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

    # Explicitly delete anything that was there
    $MTT::MPI::sources = undef;

    my @dumpfiles = glob("$dir/$sources_data_filename-*.$data_filename_extension");
    foreach my $dumpfile (@dumpfiles) {

        # If the file exists, read it in
        my $data;
        MTT::Files::load_dumpfile($dumpfile, \$data);
        $MTT::MPI::sources = MTT::Util::merge_hashes($MTT::MPI::sources, $data->{VAR1});

    }

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
    my ($dir, $name) = @_;

    # We write the entire MPI::sources hash to file, even
    # though the filename indicates a single INI section
    # MTT::Util::hashes_merge will take care of duplicate
    # hash keys. The reason for splitting up the .dump files
    # is to keep them read and write safe across INI sections
    MTT::Files::save_dumpfile("$dir/$sources_data_filename-$name.$data_filename_extension", 
                              $MTT::MPI::sources);
}

#--------------------------------------------------------------------------

sub LoadInstalls {
    my ($dir) = @_;

    # Explicitly delete anything that was there
    $MTT::MPI::installs = undef;

    my @dumpfiles = glob("$dir/$installs_data_filename-*.$data_filename_extension");
    foreach my $dumpfile (@dumpfiles) {

        # If the file exists, read it in
        my $data;
        MTT::Files::load_dumpfile($dumpfile, \$data);
        $MTT::MPI::installs = MTT::Util::merge_hashes($MTT::MPI::installs, $data->{VAR1});
    }

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
    my ($dir, $name) = @_;

    # We write the entire MPI::installs hash to file, even
    # though the filename indicates a single INI section.
    # MTT::Util::hashes_merge will take care of duplicate
    # hash keys. The reason for splitting up the .dump files
    # is to keep them read and write safe across INI sections
    MTT::Files::save_dumpfile("$dir/$installs_data_filename-$name.$data_filename_extension", 
                              $MTT::MPI::installs);
}

1;
