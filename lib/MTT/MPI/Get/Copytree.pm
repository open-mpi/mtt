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

package MTT::MPI::Get::Copytree;

use strict;
use Cwd;
use File::Basename;
use POSIX qw(strftime);
use MTT::DoCommand;
use MTT::Messages;
use MTT::Values;
use MTT::Files;

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $force) = @_;

    my $ret;
    my $data;

    # See if we got a directory in the ini section
    $data->{src_directory} = Value($ini, $section, "directory");
    return undef if (!$data->{src_directory});
    Debug(">> copytree: got directory $data->{src_directory}\n");

    if (! -d $data->{src_directory}) {
        Warning("directory does not exist: $data->{src_directory}\n");
        return undef;
    }

    # Do we have a copied tree already?  Search through $MTT::MPI::sources
    # to see if we do.
    my $md5;
    my $found = 0;
    foreach my $mpi_section (keys(%{$MTT::MPI::sources})) {
        next
            if ($section ne $mpi_section);

        my $source = $MTT::MPI::sources->{$section};
        if ($source->{module_name} eq "MTT::MPI::Get::copytree" &&
            $source->{module_data}->{src_directory} eq $data->{src_directory}) {

            # If we find a matching source directory, do a crude
            # md5sum across the tree to see if we have an
            # identical copy already
            Debug(">> found matching directory\n");
            chdir($source->{module_data}->{directory});
            $md5 = MTT::Files::md5sum_tree(".");
            if ($md5 eq $source->{module_data}->{md5sum}) {
                Debug(">> copytree: we already have this tree, and it hasn't changed\n");
                if ($force) {
                    Debug(">> copytree: but we're forcing, so we'll copy it again anyway\n");
                    $found = 1;
                    last;
                }
                # If we're not forcing, then do nothing
                return undef;
            }
        }

        # If we found one, bail
        last
            if ($found);
    }
    Debug(">> copytree: this is a new tree\n")
        if (!$found);

    # Copy the tree locally
    Debug(">> copytree: caching\n");

    # Lie a little to PrepareForInstall (don't set pre_copy and
    # post_copy yet -- they're not relevant until we actually copy for
    # build/install).  And set "directory" to be the "src_directory".
    $data->{directory} = $data->{src_directory};
    $ret->{module_data} = $data;
    $dir = PrepareForInstall($ret, cwd());
    return undef
        if (!$dir);
    
    # Reset the directory where to copy from to be here
    $data->{directory} = cwd() . "/$dir";
    chdir($data->{directory});
    $data->{md5sum} = $md5 ? $md5 : MTT::Files::md5sum_tree(".");

    # Get other values
    $data->{pre_copy} = Value($ini, $section, "pre_copy");
    $data->{post_copy} = Value($ini, $section, "post_copy");

    # Set the function pointer
    $ret->{prepare_for_install} = "MTT::MPI::Get::copytree::PrepareForInstall";

    # Make a best attempt to get a version number
    # 1. Try looking for name-<number> in the directory basename
    if (basename($data->{directory}) =~ m/[\w-]+(\d.+)/) {
        $ret->{version} = $1;
    } 
    # Give up
    else {
        $ret->{version} = basename($data->{directory}) . "-" .
            strftime("%m%d%Y-%H%M%S", localtime);
    }

    # All done
    Debug(">> copytree: returning successfully\n");
    return $ret;
} 

#--------------------------------------------------------------------------

sub PrepareForInstall {
    my ($source, $build_dir) = @_;

    Debug(">> copytree copying to $build_dir\n");
    my $data = $source->{module_data};

    # Pre copy
    if ($data->{pre_copy}) {
        Debug("copytree running pre_copy command: $data->{pre_copy}\n");
        my $x = MTT::DoCommand::CmdScript(1, $data->{pre_copy});
        if (0 != $x->{status}) {
            Warning("Pre-copy command failed: $@\n");
            return undef;
        }
    }

    # Copy the tree

    my $ret = MTT::Files::copy_tree($data->{directory}, 1);
    return undef
        if (!$ret);
    
    # Post copy
    if ($data->{post_copy}) {
        my $old = cwd();
        chdir($ret);

        Debug("copytree running post_copy command: $data->{post_copy}\n");
        my $x = MTT::DoCommand::CmdScript(1, $data->{post_copy});
        if (0 != $x->{status}) {
            Warning("Post-copy command failed: $@\n");
            return undef;
        }

        chdir($old);
    }

    # All done

    Debug(">> copytree finished copying\n");
    return $ret;
}

1;
