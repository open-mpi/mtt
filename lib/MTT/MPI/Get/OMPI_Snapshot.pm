#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2008 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::MPI::Get::OMPI_Snapshot;

use strict;
use MTT::DoCommand;
use File::Basename;
use Data::Dumper;
use MTT::Messages;
use MTT::Files;
use MTT::FindProgram;
use MTT::Values;
use MTT::INI;

# Checksum filenames
my $md5_checksums = "md5sums.txt";
my $sha1_checksums = "sha1sums.txt";

# snapshot filename
my $latest_filename = "latest_snapshot.txt";

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $force) = @_;

    my $ret;
    my $data;
    $ret->{test_result} = MTT::Values::FAIL;

    # See if we got a url in the ini section
    my $url = Value($ini, $section, "ompi_snapshot_url");
    if (!$url) {
        $ret->{result_message} = "No URL specified in [$section]; skipping";
        Warning("$ret->{result_message}\n");
        return $ret;
    }
    Debug(">> OMPI_Snapshot got url: $url\n");

    my $simple_section = GetSimpleSection($section);

    # Make some dirs
    my $tarball_dir = MTT::Files::mkdir("tarballs");
    my $data_dir = MTT::Files::mkdir("data");
    Debug("Tarball dir: $tarball_dir\n");

    MTT::DoCommand::Chdir($data_dir);
    unlink($latest_filename);
    MTT::Files::http_get("$url/$latest_filename");

    Abort("Could not download latest snapshot number -- aborting\n")
        if (! -f $latest_filename and ! $MTT::DoCommand::no_execute);
    $ret->{version} = `cat $latest_filename`;

    # This is useful for scale testing the database
    $ret->{version} = MTT::Values::RandomString(10) if ($MTT::DoCommand::no_execute);

    chomp($ret->{version});

    # see if we need to download the tarball
    my $tarball_name = "openmpi-$ret->{version}.tar.gz";
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

            if ($source->{module_name} eq "MTT::MPI::Get::OMPI_Snapshot" &&
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
    MTT::DoCommand::Chdir($tarball_dir);
    unlink("$tarball_dir/$tarball_name");
    MTT::Files::http_get("$url/$tarball_name");
    Abort ("Could not download tarball -- aborting\n")
        if (! -f $tarball_name and ! $MTT::DoCommand::no_execute);
    MTT::DoCommand::Chdir($data_dir);
        
    # get the checksums
    unlink($md5_checksums);
    MTT::Files::http_get("$url/$md5_checksums");
    
    unlink($sha1_checksums);
    MTT::Files::http_get("$url/$sha1_checksums");

    # compare the md5sum
    my $md5_file = `fgrep $ret->{version}.tar.gz $md5_checksums | cut -d\\  -f1`;
    chomp($md5_file);
    my $md5_actual = MTT::Files::md5sum("$tarball_dir/$tarball_name");
    if ($md5_actual) {
        Abort("md5sum from checksum file does not match actual ($md5_file != $md5_actual)")
            if ($md5_file ne $md5_actual);
        Debug(">> Good md5sum\n");
    } else {
        Warning("MD5 message digests were not compared because the md5sum executable was not found\n");
    }

    # compare the sha1sum
    my $sha1_file = `fgrep $ret->{version}.tar.gz $sha1_checksums | cut -d\\  -f1`;
    chomp($sha1_file);
    my $sha1_actual = MTT::Files::sha1sum("$tarball_dir/$tarball_name");
    if ($sha1_actual) {
        Abort("sha1sum from checksum file does not match actual ($sha1_file != $sha1_actual)")
            if ($sha1_file ne $sha1_actual);
        Debug(">> Good sha1sum\n");
    } else {
        Warning("SHA1 message digests were not compared because the sha1sum executable was not found\n");
    }

    # now adjust the tarball name to be absolute
    $ret->{module_data}->{tarball} = "$tarball_dir/$tarball_name";
    $ret->{module_data}->{version} = $ret->{version};
    $ret->{module_data}->{r} = $ret->{version};
    $ret->{prepare_for_install} = __PACKAGE__ . "::PrepareForInstall";

    # All done
    Debug(">> OMPI_Snapshot complete\n");
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";
    return $ret;
} 

#--------------------------------------------------------------------------

sub PrepareForInstall {
    my ($source, $build_dir) = @_;

    # Extract the tarball
    Debug(">> OMPI_Snapshot extracting tarball to $build_dir\n");

    MTT::DoCommand::Chdir($build_dir);
    my $ret = MTT::Files::unpack_tarball($source->{module_data}->{tarball}, 1);
    MTT::DoCommand::Chdir($ret);

    Debug(">> OMPI_Snapshot finished extracting tarball\n");
    return $ret;
}

1;
