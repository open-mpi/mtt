#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2007      Cisco, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Messages;

use strict;
use Data::Dumper;
use Text::Wrap;
use vars qw(@EXPORT);
use base qw(Exporter);
@EXPORT = qw(Messages Error Warning BigWarning Abort Debug Verbose Trace DebugDump FuncName);

# Is debugging enabled?
my $_debug;

# Is verbose enabled?
my $_verbose;

# Path where mtt was invoked
my $_cwd;

# Max length of string to pass to wrap() (it seems that at least some
# versions of wrap() handles Very Large strings and/or strings with
# Very Long lines extremely poorly -- it thrashes endlessly).
my $_max_wrap_len = 65536;

#--------------------------------------------------------------------------


sub Messages {
    $_debug = shift;
    $_verbose = shift;
    $_cwd = shift;

    my $textwrap = $MTT::Globals::Values->{textwrap};
    $Text::Wrap::columns = ($textwrap ? $textwrap : 76);

    # Set autoflush
    select STDOUT;
    $| = 1;
}

sub Error {
    Abort(@_);
}

sub Warning {
    my $str = "@_";
    if (length($str) < $_max_wrap_len) {
        print wrap("", "    ", "*** WARNING: $str");
    } else {
        print "*** WARNING: $str";
    }
}

# More visible "boxed" Warning
sub BigWarning {
    my @lines = @_;
    print("\n" . "#" x 76 .
          "\n# *** WARNING: " .
              join("", map { "\n# $_" } @lines) .
          "\n" . "#" x 76 . "\n");
}

sub Abort {
    my $str = "@_";
    if (length($str) < $_max_wrap_len) {
        die wrap("", "    ", "*** ERROR: $str");
    } else {
        die "*** ERROR: $str";
    }
}

sub Debug {
    if ($_debug) {
        my $str = "@_";
        if (length($str) < $_max_wrap_len) {
            print wrap("", "   ", $str);
        } else {
            print $str;
        }
    }
}

sub DebugDump {
    my $d = new Data::Dumper([@_]);
    $d->Purity(1)->Indent(1);
    print $d->Dump;
}

sub Verbose {
    if ($_verbose) {
        my $str = "@_";
        if (length($str) < $_max_wrap_len) {
            print wrap("", "   ", $str);
        } else {
            print $str;
        }
    }
}

sub Trace {
    my ($str, $lev) = @_;

    $lev = 0 if (! defined($lev));
    my @called = caller($lev);

    print wrap("", "   ", (join(":", map { &_relative_path($_) } @called[1..2]), @_)) if $_verbose;
}

# Return just the root function name
# (without the '::' prefixes)
sub FuncName {
    my ($func_name) = @_;
    if ($func_name =~ /(\w+)$/) {
        return $1;
    } else {
        return $func_name;
    }
}

# Trace helper for showing paths relative to the path mtt was invoked from
sub _relative_path {
    my ($path) = shift;
    $path =~ s/$_cwd/./;
    return $path;
}

1;
