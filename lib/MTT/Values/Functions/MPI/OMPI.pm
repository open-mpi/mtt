#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2008 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007-2008 Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2015      Research Organization for Information Science
#                         and Technology (RIST). All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Values::Functions::MPI::OMPI;

use strict;
use MTT::Messages;
use MTT::Values::Functions;
use MTT::FindProgram;
use Data::Dumper;

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
            Warning("Unknown PML in MPI::OMPI::find_network()!");
        }
    }

    # Look for a btl
    my @networks;
    if ($find_btl && $str =~ m/-mca\s+btl\s+(\S+)\s/) {
        # Only take it if it's not negated.
        @networks = split(/,/, $1)
            if ($1 !~ /^\^/);
    }

    # Look for an mtl
    elsif ($find_mtl && $str =~ m/-mca\s+mtl\s+(\S+)\s/) {
        # Only take it if it's not negated.
        push(@networks, $1)
            if ($1 !~ /^\^/);
    }

    # Translate to the MTT-neutral names
    my @ret;
    foreach my $n (@networks) {
        if ($n eq "sm" || $n eq "vader") {
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

    my $match = qr/ompi:version:full:(.*)$/;

    if (not open INFO, "$bindir/ompi_info --parsable|") {
        open INFO, "$bindir/ompi_info -V|";
        $match = qr/Open\s+MPI\s+(.*)$/;
    }

    while (<INFO>) {
        if (/$match/) {
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
    return ($file->[0] =~ /^bindings:${lang}:(")?yes/) ? "1" : "0";
}

#--------------------------------------------------------------------------

sub find_bitness {
    my ($bindir, $libdir) = @_;

    my $str = "^compiler:c:sizeof:pointer:";
    my $file = _run_ompi_info($bindir, $libdir, $str);
    $file->[0] =~ m/${str}([0-9]+)/;
    return $1;
}

#--------------------------------------------------------------------------

# Return the name of the sessions directory that was removed

sub remove_sessions_directory {
    my $funclet = (caller(0))[3];
    Debug("$funclet: got @_\n");

    my $username     = getpwuid($<);
    my $hostname     = MTT::Values::Functions::hostname();
    my $sessions_dir = "/tmp/openmpi-sessions-${username}\@${hostname}_0";

    my $x;
    if (-d $sessions_dir) {
        $x = MTT::DoCommand::Cmd(1, "rm -rf $sessions_dir");

        if (0 != $x->{exit_status}) {
            Debug("$funclet: Unable to remove $sessions_dir.\n");
            return undef;
        } else {
            Debug("$funclet: Removed $sessions_dir.\n");
        }
    } else {
        Debug("$funclet: Did not find an Open MPI sessions directory to remove.\n");
        return undef;
    }
    Debug("$funclet: returning $sessions_dir\n");
    return $sessions_dir;
}


sub _get_mpicc_compiler_info {
    my $ompi_info = shift;
    $ompi_info = FindProgram("ompi_info")
        if (!defined($ompi_info));

    my $name = "unknown";
    my $version = "unknown";
    my @ret = ($name, $version);

    my $compiler_basename;
    my $compiler_absolute;
    my $build_host;
    if (open(INFO, "$ompi_info --parsable|")) {
        while (<INFO>) {
            my $line = $_;

            if ($line =~ /build:host:(.*$)/i) {
                $build_host = $1;
            }

            if ($line =~ /compiler:c:absolute:(.*$)/i) {
                $compiler_absolute = $1;
                last;
            }
        }
    }

    if (! $compiler_absolute) {
        return \@ret;
    }

    # Get basebame
    $compiler_basename = File::Basename::basename($compiler_absolute);

    if (($compiler_basename eq "cc") or ($compiler_basename eq "suncc")) {
        $name = "sun";
        $version = MTT::Values::Functions::get_sun_cc_version($compiler_absolute);
    } elsif ($compiler_basename eq "gcc") {
        $name = "gnu";
        $version = MTT::Values::Functions::get_gcc_version($compiler_absolute);
    } elsif ($compiler_basename eq "icc") {
        $name = "intel";
        $version = MTT::Values::Functions::get_icc_version($compiler_absolute);
    } elsif ($compiler_basename eq "pgcc") {
        $name = "pgi";
        $version = MTT::Values::Functions::get_pgcc_version($compiler_absolute);
    }

    my @ret = ($name, $version);

    Debug("_get_mpicc_compiler_info returning @ret\n");
    return \@ret;
}

sub get_mpicc_compiler_name {
    my $x = _get_mpicc_compiler_info(@_);
    return @$x[0];
}

sub get_mpicc_compiler_version {
    my $x = _get_mpicc_compiler_info(@_);
    return @$x[1];
}

#--------------------------------------------------------------------------

# Extract the MCA parameters from an mpirun command line.  Also scour
# the environment looking for OMPI_MCA_* environment variables and
# list those, too.

sub find_mca_params {
    my ($cmd) = @_;
    my @params;
    my $str;

    # Extract from command line
    while ($cmd =~ s/\s([\-]*-mca)\s+(\S+)\s+(\S+)\s/ /) {
        push(@params, "$1 $2 $3");
    }

    # Check the environment for OMPI_MCA_* values
    foreach my $e (keys(%ENV)) {
        Debug("Functions::MPI::OMPI: Checking env key: $e\n");
        if ($e =~ m/^OMPI_MCA_(\S+)/) {
            my $v = $ENV{"OMPI_MCA_$1"};
            push(@params, "--env-mca $1 $v");
        }
    }

    $str = join(' ', @params);
    Debug("Functions::MPI::OMPI: Returning MCA params $str\n");
    $str;
}

1;
