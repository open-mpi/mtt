#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Common::Copytree;

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
    my ($ini, $section, $previous_mtime) = @_;

    my $ret;
    my $data;
    my $src_mtime;
    $ret->{success} = 0;

    # See if we got a directory in the ini section
    $data->{src_directory} = Value($ini, $section, "copytree_directory");
    if (!$data->{src_directory}) {
        $ret->{result_message} = "No source directory specified in [$section]; skipping";
        Warning("$ret->{result_message}\n");
        return $ret;
    }
    Debug(">> copytree: got directory $data->{src_directory}\n");

    if (! -d $data->{src_directory}) {
        $ret->{result_message} = "Directory does not exist: $data->{src_directory}";
        Warning("$ret->{result_message}\n");
        return $ret;
    }

    # If we have a previous mtime, compare it
    if ($previous_mtime) {
        $src_mtime = MTT::Files::mtime_tree($data->{src_directory});

        if ($src_mtime <= $previous_mtime) {
            Debug(">> copytree: we already have this tree, and it hasn't changed\n");
            $ret->{success} = 1;
            $ret->{have_new} = 0;
            $ret->{result_message} = "Tree has not changed (did not re-copy)";
            return $ret;
        }
    }
    $ret->{have_new} = 1;

    # Copy the tree locally
    Debug(">> copytree: caching\n");

    # Lie a little to PrepareForInstall (don't set pre_copy and
    # post_copy yet -- they're not relevant until we actually copy for
    # build/install).  And set "directory" to be the "src_directory".
    $data->{directory} = $data->{src_directory};
    $ret->{module_data} = $data;
    my $dir = PrepareForInstall($ret, cwd());
    if (!$dir) {
        $ret->{success} = 0;
        $ret->{result_message} = "Failed to copy tree";
        return $ret;
    }
    
    # Reset the directory where to copy from to be here
    $data->{directory} = cwd() . "/$dir";
    $data->{mtime} = defined($src_mtime) ? $src_mtime : MTT::Files::mtime_tree($data->{directory});

    # Get other values
    $data->{version} = Value($ini, $section, "copytree_version");
    $data->{pre_copy} = Value($ini, $section, "copytree_pre_copy");
    $data->{post_copy} = Value($ini, $section, "copytree_post_copy");

    # Set the function pointer
    $ret->{prepare_for_install} = "MTT::Common::Copytree::PrepareForInstall";

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
    $ret->{module_data} = $data;

    # All done
    Debug(">> copytree: returning successfully\n");
    $ret->{success} = 1;
    $ret->{result_message} = "Success";
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
        MTT::DoCommand::Chdir($ret);

        Debug("copytree running post_copy command: $data->{post_copy}\n");
        my $x = MTT::DoCommand::CmdScript(1, $data->{post_copy});
        if (0 != $x->{status}) {
            Warning("Post-copy command failed: $@\n");
            return undef;
        }

        MTT::DoCommand::Chdir($old);
    }

    # All done

    Debug(">> copytree finished copying\n");
    return $ret;
}

1;
