#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::MPI::Get::LAM_Snapshot;

use strict;
use Cwd;
use File::Basename;
use Data::Dumper;
use POSIX;
use MTT::Messages;
use MTT::Files;
use MTT::FindProgram;
use MTT::Values;

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $force) = @_;

    my $ret;
    my $data;
    $ret->{test_result} = MTT::Values::FAIL;

    # See if we got a url in the ini section
    my $url = Value($ini, $section, "lam_snapshot_url");
    if (!$url) {
        $ret->{result_message} = "No URL specified in [$section]; skipping";
        Warning("$ret->{result_message}\n");
        return $ret;
    }
    Debug(">> LAM_Snapshot got url: $url\n");

    my $simple_section = $section;
    $simple_section =~ s/^\s*mpi get:\s*//;

    # Make some dirs
    my $tarball_dir = MTT::Files::mkdir("tarballs");
    my $data_dir = MTT::Files::mkdir("data");
    Debug("Tarball dir: $tarball_dir\n");

    chdir($data_dir);
    unlink("index.html");
    MTT::Files::http_get("$url");

    Abort("Could not download snapshot index\n")
        if (! -f "index.html" && ! $MTT::DoCommand::no_execute);

    # Parse the file, look for LAM snapshot tarballs, and find the one
    # with the most recent file date
    my $months = {
        Jan => 1,
        Feb => 2,
        Mar => 3,
        Apr => 4,
        May => 5,
        Jun => 6,
        Jul => 7,
        Aug => 8,
        Sep => 9,
        Oct => 10,
        Nov => 11,
        Dec => 12,
    };
    my $most_recent_date = 0;
    my $snapshot_filename;
    my $snapshot_version;
    open F, "index.html";
    while (<F>) {
        if (m@<img src="/icons/unknown.gif" .+ <a href="(lam-[0-9\.a-z]+\.tar\.bz2)">lam-[0-9\.a-z]+\.tar\.bz2</a>\s*([0-9]{2})-([a-zA-Z]{3})-([0-9]{4})@) {
            Debug("Found LAM snapshot file: $1 / $2-$3-$4\n");
            my $d = mktime(0, 0, 0, $2, $months->{$3}, $4);
            if ($d > $most_recent_date) {
                $most_recent_date = $d;
                $snapshot_filename = $1;
                $1 =~ m@lam-([0-9]+\.[0-9]+.*r[0-9]+)\.tar\.bz2@;
                $snapshot_version = $1;
            }
        }
    }
    Debug("Found most recent LAM snapshot file: $snapshot_filename / $snapshot_version\n");
    $ret->{version} = $snapshot_version;

    # This is useful for scale testing the database
    $ret->{version} = MTT::Values::RandomString(10) 
        if ($MTT::DoCommand::no_execute);

    # see if we need to download the tarball
    my $tarball_name = $snapshot_filename;
    my $found = 0;
    foreach my $mpi_get_key (keys(%{$MTT::MPI::sources})) {
        my $mpi_get = $MTT::MPI::sources->{$mpi_get_key};
        Debug(">> checking section: [$simple_section] vs. $mpi_get_key\n");

        if ($simple_section ne $mpi_get_key) {
            Debug(">> have no snapshots from this section; need to download\n");
            next;
        }

        # Ok, so this is the right section.  Do we have this version
        # already?

        Debug(">> have snapshots from this section; checking to see if we already have $ret->{version}\n");
        foreach my $version_key (keys(%{$mpi_get})) {
            my $source = $mpi_get->{$version_key};
            Debug(">> have [$simple_section] version $version_key\n");

            if ($source->{module_name} eq "MTT::MPI::Get::LAM_Snapshot" &&
                basename($source->{module_data}->{tarball}) eq
                $tarball_name) {

                # If we find one of the same name, that's good enough
                # -- OMPI snapshot tarballs are named such that
                # something of the same tarball name is guaranteed to
                # be the same tarball
                Debug(">> we have previously downloaded this tarball\n");

                # We have this tarball already.  If we're not forcing,
                # return nothing.
                if (!$force) {
                    $ret->{test_result} = MTT::Values::PASS;
                    $ret->{have_new} = 0;
                    $ret->{result_message} = "Snapshot tarball has not changed (did not re-download)";
                    return $ret;
                }
                Debug(">> ...but we're forcing, so we'll get a new one\n");
            
                # If we are forcing, then reset to get a new copy
                $found = 1;
                last;
            }

            # If we found one, bail
            last
                if ($found);
        }

        # If we found one, bail
        last
            if ($found);
    }
    Debug(">> we have not previously downloaded this tarball\n")
        if (!$found);
    $ret->{have_new} = 1;

    # Download the tarball
    chdir($tarball_dir);
    unlink("$tarball_dir/$tarball_name");
    MTT::Files::http_get("$url/$tarball_name");
    Abort ("Could not download tarball -- aborting\n")
        if (! -f $tarball_name and ! $MTT::DoCommand::no_execute);
    chdir($data_dir);
        
    # now adjust the tarball name to be absolute
    $ret->{module_data}->{tarball} = "$tarball_dir/$tarball_name";
    $ret->{prepare_for_install} = __PACKAGE__ . "::PrepareForInstall";

    # All done
    Debug(">> LAM_Snapshot complete\n");
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";
    return $ret;
} 

#--------------------------------------------------------------------------

sub PrepareForInstall {
    my ($source, $build_dir) = @_;

    # Extract the tarball
    Debug(">> LAM_Snapshot extracting tarball to $build_dir\n");
    my $orig = cwd();
    chdir($build_dir);
    my $ret = MTT::Files::unpack_tarball($source->{module_data}->{tarball}, 1);
    chdir($orig);
    Debug(">> LAM_Snapshot finished extracting tarball\n");
    return $ret;
}

1;
