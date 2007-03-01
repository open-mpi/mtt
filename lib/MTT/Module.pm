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

package MTT::Module;

########################################################################

use strict;
use MTT::Messages;
use Data::Dumper;
use vars qw(@EXPORT);
use base qw(Exporter);
@EXPORT = qw(Run);

#--------------------------------------------------------------------------

sub Run {
    my $module = shift;
    my $method = shift;
    my @args = @_;

    # Load the module

    return undef if (! Exists($module));

    # Call the method in that module

    my $ret = undef;
    my $str = "\$ret = \&${module}::$method(\@args)";
    Debug("Evaluating: $str\n");
    my $check = eval $str;
    if ($@) {
        if (!$check) {
            Error("Module aborted: $module:$method: $@\n");
        }

        Warning("Could not run module $module:$method: $@\n");
        return undef;
    }

    return $ret;
}

# Load the module (return 1 if everything went a-okay)
sub Exists {
    my $module = shift;

    my $str = "require $module";
    Debug("Evaluating: $str\n");
    my $check = eval $str;
    if ($@) {
        if (!$check) {
            Warning("Module aborted during require: $module: $@\n");
        }

        Warning("Could not load module $module: $@\n");
        return 0;
    } else {
        return 1;
    }
}

1;
