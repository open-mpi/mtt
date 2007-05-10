#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2007 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Trim;

use strict;

use Config::IniFiles;
use Data::Dumper;
use File::Basename;
use MTT::Messages;
use MTT::Values;
use MTT::Globals;
use MTT::Test;
use MTT::MPI;
use MTT::DoCommand;

#--------------------------------------------------------------------------

# Exported constant
use constant {
    TRIM_KEY => "TO_BE_TRIMMED",
};

#--------------------------------------------------------------------------

# Trim old trees after a run
sub Trim {
    my ($ini, $source_dir, $install_dir) = @_;

    # This will be implemented properly someday anyway, so no use in
    # having anything here at the moment.
}

1;
