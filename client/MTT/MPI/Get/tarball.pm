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

package MTT::MPI::Get::tarball;

use strict;
use Cwd;
use File::Basename;
use POSIX qw(strftime);
use MTT::DoCommand;
use MTT::Messages;
use MTT::Values;
use MTT::Files;
use MTT::MPI::Get;
use Data::Dumper;

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $unique_id, $force) = @_;

    my $ret;
    my $data;

    # See if we got a tarball in the ini section
    $data->{tarball} = Value($ini, $section, "tarball");
    return undef if (!$data->{tarball});
    Debug(">> tarball: got tarball $data->{tarball}\n");

    if (! -f $data->{tarball}) {
        Warning("tarball does not exist: $data->{tarball}\n");
        return undef;
    }

    # Do we have a tarball of the same name already?  Search through
    # $MTT::MPI::sources to see if we do.
    my $md5;
    my $found = 0;
    foreach my $mpi_section (keys(%{$MTT::MPI::sources})) {
        next
            if ($section ne $mpi_section);

        foreach my $mpi_unique (keys(%{$MTT::MPI::sources->{$section}})) {
            my $source = $MTT::MPI::sources->{$section}->{$mpi_unique};
            if ($source->{module_name} eq "MTT::MPI::Get::tarball" &&
                basename($source->{module_data}->{tarball}) eq
                basename($data->{tarball})) {

                # If we find one of the same name, that may not be
                # enough (e.g., "mpi-latest.tar.gz").  So check the
                # md5sum's.
                $md5 = MTT::Files::md5sum($source->{module_data}->{tarball});
                if ($md5 eq $source->{module_data}->{md5sum}) {
                    Debug(">> tarball: we already have this tarball\n");
                    return undef
                        if (!$force);

                    Debug(">> tarball: but we're forcing, so we'll take it anyway\n");
                    $unique_id = $ret->{unique_id} = $source->{unique_id};
                    $found = 1;
                    last;
                }
            }
        }

        # If we found one, bail
        last
            if ($found);
    }
    Debug(">> tarball: this is a new tarball\n")
        if (!$found);

    # Copy this tarball locally
    Debug(">> tarball: caching\n");
    my $dir = MTT::Files::mkdir($unique_id);
    chdir($dir);
    my $x = MTT::DoCommand::Cmd(1, "cp $data->{tarball} .");
    if (0 != $x->{status}) {
        Warning("Unable to copy tarball $data->{tarball}: $@\n");
        return undef;
    }

    # Reset the directory where to copy from to be here
    $data->{tarball} = cwd() . "/" . basename($data->{tarball});
    $data->{md5sum} = $md5 ? $md5 : MTT::Files::md5sum($data->{tarball});

    # Get other module-data values
    $data->{pre_extract} = Value($ini, $section, "pre_extract");
    $data->{post_extract} = Value($ini, $section, "post_extract");

    # Set the final top-level return data
    $ret->{prepare_for_install} = "MTT::MPI::Get::tarball::PrepareForInstall";
    $ret->{module_data} = $data;

    # Make a best attempt to get a version number
    # 1. Try looking for name-<number>.tar.(gz|bz)
    if (basename($data->{tarball}) =~ m/[\w-]+(\d.+).tar.(gz|bz2)/) {
        $ret->{version} = $1;
    } 
    # Give up
    else {
        $ret->{version} = basename($data->{tarball}) . "-" .
            strftime("%m%d%Y-%H%M%S", localtime);
    }

    # All done
    Debug(">> tarball: returning successfully\n");
    return $ret;
} 

#--------------------------------------------------------------------------

sub PrepareForInstall {
    my ($source, $build_dir) = @_;

    Debug(">> tarball extracting to $build_dir\n");

    my $orig = cwd();
    chdir($build_dir);
    my $data = $source->{module_data};

    # Pre extract
    if ($data->{pre_extract}) {
        my $x = MTT::DoCommand::CmdScript(1, $data->{pre_copy});
        if (0 != $x->{status}) {
            Warning("Pre-extract command failed: $@\n");
            return undef;
        }
    }

    # Extract the tarball
    my $ret = MTT::Files::unpack_tarball($data->{tarball}, 1);
    if (!$ret) {
        chdir($orig);
        return undef;
    }

    # Post extract
    if ($data->{post_extract}) {
        my $old = cwd();
        chdir($ret);

        my $x = MTT::DoCommand::Cmds(1, $data->{pre_copy});
        if (0 != $x->{status}) {
            Warning("Post-extract command failed: $@\n");
            return undef;
        }

        chdir($old);
    }

    # All done

    chdir($orig);
    Debug(">> tarball finished extracting\n");
    return $ret;
}

1;
