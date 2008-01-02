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

package MTT::MPI::Get::SCM;
my $package = __PACKAGE__;

use strict;
use MTT::Values;
use MTT::Messages;
use MTT::INI;
use MTT::Common::SCM;
use Data::Dumper;

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $force) = @_;
    my $ret;
    my $previous_r;

    # Process all the INI parameters
    my $params = &MTT::Common::SCM::ProcessInputParameters($ini, $section);
    my $url = $params->{url};

    my $simple_section = GetSimpleSection($section);

    # If we're not forcing, do we have a svn with the same URL already?
    if (!$force) {
        foreach my $mpi_get_key (keys(%{$MTT::MPI::sources})) {
            next if ($section ne $mpi_get_key);
            
            my $mpi_get = $MTT::MPI::sources->{$mpi_get_key};
            foreach my $version_key (keys(%{$mpi_get})) {
                my $source = $mpi_get->{$version_key};
                Debug(">> have [$simple_section] version $version_key\n");

                if ($source->{module_name} eq $package &&
                    $source->{module_data}->{url} eq $url) {
                    
                    # We found it
                    $previous_r = $source->{module_data}->{r};
                    last;
                }
            }
        }
    }

    # Call the back-end function
    $ret = MTT::Common::SCM::Get($params, $previous_r, $force);

    return $ret;
}

1;
