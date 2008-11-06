#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2008      Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::FindProgram;

use strict;
use File::Basename;
use MTT::Messages;
use MTT::DoCommand;
use Data::Dumper;
use vars qw(@EXPORT);
use base qw(Exporter);
@EXPORT = qw(FindProgram FindZeroDir);

#--------------------------------------------------------------------------

# Cached zero dir
my $zero_dir;

#--------------------------------------------------------------------------

# find a program from a list and load it into the target variable
sub FindProgram {
    my @names = @_;

    # loop through the list and save the first one that we find
    my $i = 0;
    while ($i <= $#names) {
        foreach my $dir (split(/:/, $ENV{PATH})) {
            if (-x "$dir/$names[$i]") {
                Debug(">> " . (caller(0))[3] . " returning $dir/$names[$i]\n");
                return "$dir/$names[$i]";
            }
        }
        ++$i;
    }
    return undef;
}

#--------------------------------------------------------------------------

sub FindZeroDir {

    # See if we found it already and cached it
    return $zero_dir 
        if ($zero_dir);

    # First check $0 itself to see if it gives any clues

    my $start = MTT::DoCommand::cwd();

    my $dir = dirname($0);
    my $cmd = basename($0);
    if (-x "$dir/$cmd") {
        MTT::DoCommand::Chdir($dir);
        $zero_dir = MTT::DoCommand::cwd();
        MTT::DoCommand::Chdir($start);
        return $zero_dir;
    }

    # If $0 has not /'s in it, then search the PATH for $0
    if ($0 !~ /\//) {
        foreach my $p (split(/:/, $ENV{PATH})) {
            if (-x "$p/$0") {
                MTT::DoCommand::Chdir($p);
                $zero_dir = MTT::DoCommand::cwd();
                MTT::DoCommand::Chdir($start);
                return $zero_dir;
            }
        }
    }

    return undef;
}

1;
