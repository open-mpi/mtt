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

package MTT::Test::Get::SCM;
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

    my $simple_section = GetSimpleSection($section);

    my $ret;
    my $previous_r;

    # Process the INI parameters
    my $params = &MTT::Common::SCM::ProcessInputParameters($ini, $section);
    my $url = $params->{url};

    # If we're not forcing, do we have a svn with the same URL already?
    if (!$force) {
        foreach my $test_section (keys(%{$MTT::Test::sources})) {

            next
                if ($simple_section ne $test_section);
            
            my $source = $MTT::Test::sources->{$simple_section};

            if ($source->{module_name} eq $package &&
                $source->{module_data}->{url} eq $url) {

                # We found it

                $previous_r = $source->{module_data}->{r};
                last;
            }
        }
    }

    # Call the back-end function
    $ret = MTT::Common::SCM::Get($params, $previous_r, $force);

    return $ret;
}

1;
