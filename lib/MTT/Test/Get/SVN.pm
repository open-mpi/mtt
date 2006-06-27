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

package MTT::Test::Get::SVN;

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

    # If we're not forcing, do we have a svn with the same URL already?
    if (!$force) {
        foreach my $test_section (keys(%{$MTT::Test::sources})) {
            next
                if ($section ne $test_section);
            
            my $source = $MTT::Test::sources->{$section};
            if ($source->{module_name} eq "MTT::Test::Get::SVN" &&
                $source->{module_data}->{url} eq $url) {

                # We found it

                $previous_r = $source->{module_data}->{r};
                last;
            }
        }
    }

    # Call the back-end function
    return MTT::Common::SVN::Get($ini, $section, $previous_r);
}

1;
