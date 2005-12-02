#!/usr/bin/env perl
#
# Copyright (c) 2004-2005 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2004-2005 The Trustees of the University of Tennessee.
#                         All rights reserved.
# Copyright (c) 2004-2005 High Performance Computing Center Stuttgart, 
#                         University of Stuttgart.  All rights reserved.
# Copyright (c) 2004-2005 The Regents of the University of California.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Run::Intel_ompi_tests;

use strict;
use Cwd;
use MTT::Messages;
use Data::Dumper;

# default runfile
my $default_runfile = "all_tests_no_perf";

#--------------------------------------------------------------------------

sub Run {
    my ($ini, $section, $build_dir, $mpi_install) = @_;

    my $runfile = Value($ini, $config->{section_name}, "runfile");
    $runfile = $default_runfile
        if (!$runfile);
    if (! -f $runfile) {
        $ret->{result_message} = "Could not find runfile: $runfile; skipping\n";
        return $ret;
    }

    # The runfile was already trimmed according to which language
    # bindings were available

} 

1;
