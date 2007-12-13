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

package MTT::MPI::Get::Copytree;

use strict;
use MTT::Values;
use MTT::Messages;
use MTT::INI;
use MTT::Common::Copytree;

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $force) = @_;
    my $ret;
    my $previous_mtime;

    my $simple_section = GetSimpleSection($section);

    # See if we got a directory in the ini section
    my $src_directory = Value($ini, $section, "copytree_directory"); 
    if (!$src_directory) {
        $ret->{result_message} = "No source directory specified in [$section]; skipping";
        Warning("$ret->{result_message}\n");
        return $ret;
    }

    # Do we have the tree already?  Search through $MTT::MPI::sources
    # to see if we do.
    foreach my $mpi_get_key (keys(%{$MTT::MPI::sources})) {
        next
            if ($simple_section ne $mpi_get_key);

        my $mpi_get = $MTT::MPI::sources->{$mpi_get_key};
        foreach my $version_key (keys(%{$mpi_get})) {
            my $source = $mpi_get->{$version_key};
            Debug(">> have [$simple_section] version $version_key\n");

            if ($source->{module_name} eq "MTT::MPI::Get::Copytree" &&
                $source->{module_data}->{src_directory} eq $src_directory) {
                $previous_mtime = $source->{module_data}->{mtime};
                $previous_mtime = -1
                    if (!$previous_mtime);
                last;
            }
        }
    }

    # Run the back-end function
    return MTT::Common::Copytree::Get($ini, $section, $previous_mtime);
}

1;
