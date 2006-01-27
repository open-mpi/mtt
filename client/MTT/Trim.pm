#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Trim;

use strict;

use Config::IniFiles;
use MTT::Messages;

#--------------------------------------------------------------------------

# Trim old trees after a run
sub Trim {
    my ($ini) = @_;

    Verbose("*** Trim phase starting\n");
    Debug("Trim: I don't do anything yet\n");
    Verbose("*** Trim phase complete\n");
}

1;


