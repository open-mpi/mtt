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

package MTT::Reporter;

use strict;
use File::Basename;
use MTT::Messages;
use MTT::FindProgram;
use MTT::Values;
use Data::Dumper;

# Cache of info about the system
my $cache;

# cache of the ini file
my $ini;

# modules to invoke upon Reporter()
my @modules;

#--------------------------------------------------------------------------

sub _fill_cache {
    $cache = undef;

    # Try to get a FQDN

    my $hostname = `hostname`;
    chomp($hostname);
    Debug("Got hostname: $hostname\n");

    # Find whatami

    my $dir = FindZeroDir();
    my $whatami = "$dir/whatami/whatami";
    if (! -x $whatami) {
        Error("Cannot find 'whatami' program -- cannot continue\n");
    }
    Debug("Found whatami: $whatami\n");

    # Fill in the cache

    $cache->{platform_type} = `$whatami -t`;
    chomp($cache->{platform_type});
    $cache->{platform_hardware} = `$whatami -m`;
    chomp($cache->{platform_hardware});
    $cache->{os_name} = `$whatami -n`;
    chomp($cache->{os_name});
    $cache->{os_version} = `$whatami -r`;
    chomp($cache->{os_version});
    $cache->{hostname} = $hostname;
}

#--------------------------------------------------------------------------

sub GetID {
    return $cache;
}

#--------------------------------------------------------------------------

sub MakeReportString {
    my ($report) = @_;

    my $str;
    _stringify(\$str, $cache);
    _stringify(\$str, $report);
    return $str;
}

sub _stringify {
    my ($str, $hash) = @_;

    my @to_delete;
    foreach my $k (sort(keys(%$hash))) {
        $$str .= "$k:";
        my $val = $hash->{$k};

        # Huersitic: if there are any newlines in the original string,
        # we want this to be a multi-line output.
        my $want_multi = ($val =~ /\n/);

        # Trim off leading and trailing blank lines and any final \n's
        # (from perlfaq4(1))
        for ($val) {
            s/^\s+//;
            s/\s+$//;
        }

        # Double check that we have anything left in the string
        if ($val ne "") {
            if ($want_multi) {
                $$str .= "\n$val\n\n";
            } else {
                $$str .= "$val\n";
            }
        } else {
            # If we have nothing left, mark this key to be removed
            # (it's a bad idea to remove a key while we're iterating
            # over it, per perlfaq4(1))
            push(@to_delete, $k);
        }
    }

    foreach my $d (@to_delete) {
        delete $hash->{$d};
    }
}

#--------------------------------------------------------------------------

sub Init {
    ($ini) = @_;

    Verbose("*** Reporter initializing\n");

    _fill_cache();

    # Go through all the sections in the ini file looking for section
    # names that begin with "reporter:"

    foreach my $section ($ini->Sections()) {
        if ($section =~ /^reporter:/) {
            my $m = MTT::Values::Value($ini, $section, "module");
            if (!$m) {
                Warning(">> Reporter [$section] has no module; skipping\n");
                next;
            }
            Verbose(">> Initializing reporter module: $m\n");
            my $ret = MTT::Module::Run("MTT::Reporter::$m", "Init", $ini,
                                       $section);
            if ($ret) {
                push(@modules, $m);
            }
        }
    }

    Verbose("*** Reporter initialized\n");
}

#--------------------------------------------------------------------------

sub Submit {
    my ($phase, $section, $report) = @_;

    _fill_cache()
        if (!$cache);

    # Call all the reporters

    $cache->{submit_timestamp} = localtime;
    foreach my $m (@modules) {
        MTT::Module::Run("MTT::Reporter::$m", "Submit", 
                         $phase, $section, $cache, $report);
    }
}

1;
