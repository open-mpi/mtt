#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2007 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Values::Functions::MPI::OMPI;

use strict;
use MTT::Messages;
use Data::Dumper;
use Cwd;

#--------------------------------------------------------------------------

sub find_mpirun_params {
    Debug("&MPI::OMPI::find_mpirun_params: got @_\n");
    my $str = shift;
    my $final = shift;

    # Split up the mpirun command line and ignore argv[0]
    my @params = split(/\s+/, $str);
    shift @params;

    my $skip = 0;
    my $mca;
    my @ret;
    foreach my $p (@params) {
        if ($skip > 0) {
            --$skip;
            next;
        }

        # If we got "--mca" last round, see if we want to record the
        # parameter
        elsif (defined($mca)) {
            if ($p eq "btl" || $p eq "mtl") {
                $skip = 1;
                $mca = undef;
                next;
            } else {
                push(@ret, $mca);
                push(@ret, $p);
                $mca = undef;
                next;
            }
        }

        # Skip some parameters that we don't care about
        elsif ($p eq "-np" || $p eq "--np" || $p eq "-c") {
            $skip = 1;
            next;
        } elsif ($p eq "-hostfile" || $p eq "--hostfile" ||
                 $p eq "-machinefile" || $p eq "--machinefile") {
            $skip = 1;
            next;
        } elsif ($p eq "-host" || $p eq "--host") {
            $skip = 1;
            next;
        } elsif ($p eq "-prefix" || $p eq "--prefix") {
            $skip = 1;
            next;
        } elsif ($p eq "-mca" || $p eq "--mca" ||
                 $p eq "-gmca" || $p eq "--gmca") {
            # If we get the "mca" parameter, we *may* skip it if it's
            # specifying a btl, mtl, or pml (because those will be
            # recorded in find_network())
            $mca = $p;
            next;
        } elsif ($p eq $final) {
            last;
        }

        # Save everything else
        push(@ret, $p);
    }

    # Return in string form
    my $ret = join(" ", @ret);
    Debug("&MPI::OMPI::find_mpirun_params returning: $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

sub find_network {
    Debug("&MPI::OMPI::find_network: got @_\n");
    my $str = shift;
    my $final = shift;

    # Ignore argv[0]
    $str =~ s/^\s*\S+\s*(.+)$/\1/;

    # To safely use this string in a regexp
    # we must escape all non-word characters
    $final = quotemeta($final); 

    # Ignore everything beyond $final
    $str =~ s/^(.+)\s*$final.+$/\1/;
    Debug("Examining: $str\n");

    # First look for "--mca\s+pml\s", indicating that we want to force
    # searching for btls or mtls.
    my $find_btl = 1;
    my $find_mtl = 1;
    if ($str =~ m/-mca\s+pml\s+(\S+)\s/) {
        if ($1 eq "ob1") {
            $find_mtl = 0;
        } elsif ($1 eq "cm") {
            $find_btl = 0;
        } else {
            Warn("Unknown PML in MPI::OMPI::find_network()!");
        }
    }

    # Look for a btl
    my @networks;
    if ($find_btl && $str =~ m/-mca\s+btl\s+(\S+)\s/) {
        @networks = split(/,/, $1);
    }

    # Look for an mtl
    elsif ($find_mtl && $str =~ m/-mca\s+mtl\s+(\S+)\s/) {
        push(@networks, $1);
    }

    # Translate to the MTT-neutral names
    my @ret;
    foreach my $n (@networks) {
        if ($n eq "sm") {
            push(@ret, "shmem");
        } elsif ($n eq "openib" || $n eq "ofud" || $n eq "mvapi") {
            push(@ret, "verbs");
        } elsif ($n eq "self") {
            push(@ret, "loopback");
        } else {
            push(@ret, $n);
        }
    }

    # Return in string form
    my $ret = join(",", @ret);
    Debug("&MPI::OMPI::find_network returning: $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Get the OMPI version string from ompi_info
sub get_version {
    my $bindir = shift;

    open INFO, "$bindir/ompi_info --parsable|";

    while (<INFO>) {
        if (/ompi:version:full:(.*)$/) {
            Debug(">> " . (caller(0))[3] . " returning $1\n");
            close(INFO);
            return $1;
        }
    }
    close(INFO);
    return undef;
}

#--------------------------------------------------------------------------

sub _run_ompi_info {
    my ($bindir, $libdir, $grep_string) = @_;

    my %ENV_SAVE = %ENV;
    if (exists($ENV{LD_LIBRARY_PATH})) {
        $ENV{LD_LIBRARY_PATH} = "$libdir:$ENV{LD_LIBRARY_PATH}";
    } else {
        $ENV{LD_LIBRARY_PATH} = "$libdir";
    }

    open INFO, "$bindir/ompi_info --all --parsable|";
    my @file = grep { /$grep_string/ } <INFO>;
    chomp @file;
    close INFO;

    %ENV = %ENV_SAVE;

    return \@file;
}

#--------------------------------------------------------------------------

sub find_bindings {
    my ($bindir, $libdir, $lang) = @_;

    my $file = _run_ompi_info($bindir, $libdir, "^bindings:$lang:");
    return ($file->[0] =~ /^bindings:${lang}:yes/) ? "1" : "0";
}

#--------------------------------------------------------------------------

sub find_bitness {
    my ($bindir, $libdir) = @_;

    my $str = "^compiler:c:sizeof:pointer:";
    my $file = _run_ompi_info($bindir, $libdir, $str);
    $file->[0] =~ m/${str}([0-9]+)/;
    return $1;
}

1;
