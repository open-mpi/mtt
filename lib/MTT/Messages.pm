#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2007      Cisco, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
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
@EXPORT = qw(Messages Error Warning BigWarning Abort Debug Verbose Trace DebugDump FuncName ModuleName);

# Is debugging enabled?
my $_debug;

# Is verbose enabled?
my $_verbose;

# Path where mtt was invoked
my $_cwd;

# For resetting message back to a previous level
my $debug_save;
my $verbose_save;
my $cwd_save;

# Max length of string to pass to wrap() (it seems that at least some
# versions of wrap() handles Very Large strings and/or strings with
# Very Long lines extremely poorly -- it thrashes endlessly).
my $_max_wrap_len = 65536;

# Logfile handle
my $LOGFILE = undef;

#--------------------------------------------------------------------------


sub Messages {
    $debug_save = $_debug;
    $verbose_save = $_verbose;
    $cwd_save = $_cwd;

    $_debug = shift;
    $_verbose = shift;
    $_cwd = shift;

    # Set autoflush
    select STDOUT;
    $| = 1;

    return ($debug_save, $verbose_save, $cwd_save);
}

sub SetTextwrap {
    my $textwrap = $MTT::Globals::Values->{textwrap};
    $Text::Wrap::columns = ($textwrap ? $textwrap : 76);
}

sub open_logfile {
    my $filename = shift;
    open LOG, ">$filename" ||
        Abort("Cannot open logfile \"$filename\" -- aborting\n");
    $LOGFILE = \*LOG;
}

sub close_logfile {
    if (defined($LOGFILE)) {
        close(*$LOGFILE);
        $LOGFILE = undef;
    }
}

sub Error {
    Abort(@_);
}

sub Warning {
    my $str = "@_";
    if (length($str) < $_max_wrap_len) {
        my $s = wrap("", "    ", "*** WARNING: $str");
        print $s;
        print $LOGFILE $s
            if (defined($LOGFILE));
    } else {
        my $s = "*** WARNING: $str";
        print $s;
        print $LOGFILE $s
            if (defined($LOGFILE));
    }
}

# More visible "boxed" Warning
sub BigWarning {
    my @lines = @_;
    my $s = sprintf("%s",
                   "\n" . "#" x $Text::Wrap::columns .
                   "\n# *** WARNING: " .
                   join("", map { "\n# $_" } @lines) .
                   "\n" . "#" x $Text::Wrap::columns . "\n");
    print $s;
    print $LOGFILE $s
        if (defined($LOGFILE));
}

sub Abort {
    my $str = "@_";
    if (length($str) < $_max_wrap_len) {
        my $s = wrap("", "    ", "*** ERROR: $str");
        print $LOGFILE $s
            if (defined($LOGFILE));
        die $s;
    } else {
        my $s = "*** ERROR: $str";
        print $LOGFILE $s
            if (defined($LOGFILE));
        die $s;
    }
}

sub Debug {
    if ($_debug) {
        my $str = "@_";
        if (length($str) < $_max_wrap_len) {
            my $s = wrap("", "   ", $str);
            print $s;
            print $LOGFILE $s
                if (defined($LOGFILE));
        } else {
            print $str;
            print $LOGFILE $str
                if (defined($LOGFILE));
        }
    }
}

sub DebugDump {
    my $d = new Data::Dumper([@_]);
    $d->Purity(1)->Indent(1);
    my $s = $d->Dump;
    print $s;
    print $LOGFILE $s
        if (defined($LOGFILE));
}

sub Verbose {
    if ($_verbose) {
        my $str = "@_";
        if (length($str) < $_max_wrap_len) {
            my $s = wrap("", "  ", $str);
            print $s;
            print $LOGFILE $s
                if (defined($LOGFILE));
       } else {
            print $str;
            print $LOGFILE $str
                if (defined($LOGFILE));
        }
    }
}

sub Trace {
    my ($str, $lev) = @_;

    $lev = 0 if (! defined($lev));
    my @called = caller($lev);

    my $s = (join(":", map { &_relative_path($_) } @called[1..2]), @_);
    print $s;
    print $LOGFILE $s
        if (defined($LOGFILE));
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

# Return just the root package name
# (without the '::' prefixes)
sub ModuleName {
    my ($module_name) = @_;
    if ($module_name =~ /(\w+)$/) {
        return $1;
    } else {
        return $module_name;
    }
}

# Trace helper for showing paths relative to the path mtt was invoked from
sub _relative_path {
    my ($path) = shift;
    $path =~ s/$_cwd/./;
    return $path;
}

1;
