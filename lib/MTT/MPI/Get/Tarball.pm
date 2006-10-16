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

package MTT::MPI::Get::Tarball;

use strict;
use File::Basename;
use MTT::Values;
use MTT::Messages;
use MTT::Common::Tarball;

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $force) = @_;
    my $ret;
    my $previous_md5;

    # See if we got a tarball in the ini section
    my $tarball = Value($ini, $section, "tarball_filename");
    if (!$tarball) {
        $ret->{result_message} = "No tarball specified in [$section]; skipping";
        Warning("$ret->{result_message}\n");
        return $ret;
    }

    # Do we have a tarball of the same name already?  Search through
    # $MTT::MPI::sources to see if we do.
    foreach my $mpi_get_key (keys(%{$MTT::MPI::sources})) {
        next if ($section ne $mpi_get_key);

        my $mpi_get = $MTT::MPI::sources->{$mpi_get_key};
        foreach my $version_key (keys(%{$mpi_get})) {
            my $source = $mpi_get->{$version_key};
            Debug(">> have [$section] version $version_key\n");

            if ($source->{module_name} eq "MTT::MPI::Get::Tarball" &&
                basename($source->{module_data}->{tarball}) eq
                basename($tarball)) {
                
                # If we find one of the same name, that may not be
                # enough (e.g., "mpi-latest.tar.gz").  So check the
                # md5sum's.
                
                $previous_md5 = $source->{module_data}->{md5sum};
                last;
            }
        }
    }

    # Call the back-end function
    return MTT::Common::Tarball::Get($ini, $section, $previous_md5);
}

1;
