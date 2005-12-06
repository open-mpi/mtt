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

package MTT::FindProgram;

use strict;
use File::Basename;
use Cwd;
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
                return $names[$i];
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

    my $start = cwd();

    my $dir = dirname($0);
    my $cmd = basename($0);
    if (-x "$dir/$cmd") {
        chdir($dir);
        $zero_dir = cwd();
        chdir($start);
        return $zero_dir;
    }

    # If $0 has not /'s in it, then search the PATH for $0
    if ($0 !~ /\//) {
        foreach my $p (split(/:/, $ENV{PATH})) {
            if (-x "$p/$0") {
                chdir($p);
                $zero_dir = cwd();
                chdir($start);
                return $zero_dir;
            }
        }
    }

    return undef;
}

1;
