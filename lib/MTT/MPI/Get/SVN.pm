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

package MTT::MPI::Get::SVN;

use strict;
use MTT::Values;
use MTT::Messages;
use MTT::Common::SVN;

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $force) = @_;
    my $ret;
    my $previous_r;

    my $url = Value($ini, $section, "svn_url");
    if (!$url) {
        $ret->{result_message} = "No URL specified in [$section]; skipping";
        Warning("$ret->{result_message}\n");
        return $ret;
    }

    my $simple_section = $section;
    $simple_section =~ s/^\s*mpi get:\s*//;

    # If we're not forcing, do we have a svn with the same URL already?
    if (!$force) {
        foreach my $mpi_get_key (keys(%{$MTT::MPI::sources})) {
            next if ($section ne $mpi_get_key);
            
            my $mpi_get = $MTT::MPI::sources->{$mpi_get_key};
            foreach my $version_key (keys(%{$mpi_get})) {
                my $source = $mpi_get->{$version_key};
                Debug(">> have [$simple_section] version $version_key\n");

                if ($source->{module_name} eq "MTT::MPI::Get::SVN" &&
                    $source->{module_data}->{url} eq $url) {
                    
                    # We found it
                    
                    $previous_r = $source->{module_data}->{r};
                    last;
                }
            }
        }
    }

    # Call the back-end function
    return MTT::Common::SVN::Get($ini, $section, $previous_r);
} 

1;
