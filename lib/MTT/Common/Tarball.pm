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

package MTT::Common::Tarball;

use strict;
use Cwd;
use File::Basename;
use POSIX qw(strftime);
use MTT::DoCommand;
use MTT::Messages;
use MTT::Values;
use MTT::Files;
use Data::Dumper;

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $previous_md5) = @_;

    my $ret;
    my $data;
    my $src_md5;

    # See if we got a tarball in the ini section
    $data->{tarball} = Value($ini, $section, "tarball_filename");
    if (!$data->{tarball}) {
        $ret->{result_message} = "No tarball specified in [$section]; skipping";
        Warning("$ret->{result_message}\n");
        return $ret;
    }
    Debug(">> tarball: got tarball $data->{tarball}\n");

    if (! -f $data->{tarball}) {
        $ret->{result_message} = "Tarball does not exist: $data->{tarball}";
        Warning("$ret->{result_message}\n");
        return $ret;
    }

    # If we have a previous md5sum, compare
    if ($previous_md5) {
        $src_md5 = MTT::Files::md5sum($data->{tarball});
        if ($src_md5 eq $previous_md5) {
            Debug(">> tarball: we already have this tarball\n");
            $ret->{test_result} = MTT::Values::PASS;
            $ret->{have_new} = 0;
            $ret->{result_message} = "Tarball has not changed (did not re-copy)";
            return $ret;
        }
    }
    $ret->{have_new} = 1;

    # Copy this tarball locally
    Debug(">> tarball: caching\n");
    my $dir = cwd();
    my $x = MTT::DoCommand::Cmd(1, "cp $data->{tarball} .");
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        $ret->{test_result} = MTT::Values::FAIL;
        $ret->{result_message} = "Failed to copy tarball";
        Warning($ret->{result_message});
        return $ret;
    }

    # Reset the directory where to copy from to be here
    $data->{tarball} = cwd() . "/" . basename($data->{tarball});
    $data->{md5sum} = defined($src_md5) ? $src_md5 : MTT::Files::md5sum($data->{tarball});

    # Get other module-data values
    $data->{pre_extract} = Value($ini, $section, "tarball_pre_extract");
    $data->{post_extract} = Value($ini, $section, "tarball_post_extract");

    # Set the final top-level return data
    $ret->{prepare_for_install} = __PACKAGE__ . "::PrepareForInstall";
    $ret->{module_data} = $data;

    # Make a best attempt to get a version number
    # 1. Try looking for a field in the INI file
    $ret->{version} = Value($ini, $section, "tarball_version");
    if (!defined($ret->{version})) {

        # 2. Try looking for name-<number>.tar.(gz|bz)
        if (basename($data->{tarball}) =~ m/[\w-]+(\d.+).tar.(gz|bz2)/) {
            $ret->{version} = $1;
        } 
        # 3. Give up
        else {
            $ret->{version} = basename($data->{tarball}) . "-" .
                strftime("%m%d%Y-%H%M%S", localtime);
        }
    }

    # All done
    Debug(">> tarball: returning successfully\n");
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";
    return $ret;
} 

#--------------------------------------------------------------------------

sub PrepareForInstall {
    my ($source, $build_dir) = @_;

    Debug(">> tarball extracting to $build_dir\n");

    my $orig = cwd();
    MTT::DoCommand::Chdir($build_dir);
    my $data = $source->{module_data};

    # Pre extract
    if ($data->{pre_extract}) {
        my $x = MTT::DoCommand::CmdScript(1, $data->{pre_copy});
        if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
            Warning("Pre-extract command failed: $@\n");
            return undef;
        }
    }

    # Extract the tarball
    my $ret = MTT::Files::unpack_tarball($data->{tarball}, 1);
    if (!$ret) {
        MTT::DoCommand::Chdir($orig);
        return undef;
    }

    # Post extract
    if ($data->{post_extract}) {
        my $old = cwd();
        MTT::DoCommand::Chdir($ret);

        my $x = MTT::DoCommand::Cmds(1, $data->{pre_copy});
        if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
            Warning("Post-extract command failed: $@\n");
            return undef;
        }

        MTT::DoCommand::Chdir($old);
    }

    # All done

    MTT::DoCommand::Chdir($orig);
    Debug(">> tarball finished extracting\n");
    return $ret;
}

1;
