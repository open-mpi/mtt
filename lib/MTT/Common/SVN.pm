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

package MTT::Common::SVN;
my ($package) = (__PACKAGE__ =~ m/(\w+)$/);

use strict;
use Cwd;
use File::Basename;
use POSIX qw(strftime);
use MTT::Messages;
use MTT::Files;
use MTT::Values;
use MTT::SourceControl;
use Data::Dumper;

#--------------------------------------------------------------------------

sub Get {
    my ($params, $previous_r, $force) = @_;

    my $data;
    my $ret;

    # Default to getting new sources (e.g., if we do not know how to check for
    # new sources for a given SCM system)
    my $want_new = 1;

    # Prepare a return status
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";

    #
    # Note on the subtle difference between want_new/have_new:
    #  * want_new = Do we want to Get sources?
    #  * have_new = Do we want to tell the Install 
    #               phase that we have "new" sources to install?
    #
    # There are a number of possible scenarios:
    #   * We have no sources
    #   * We have old sources
    #   * We have old sources and the repo hasn't changed
    #   * All the above with and without --force
    $ret->{have_new} = $want_new;

    # Do we want to overwrite previous sources?
    my $delete_first = $params->{delete_first};

    # Main command (i.e., svn, hg, git)
    my $command = $params->{command};

    # Sub-command (i.e., export, checkout, clone)
    my $subcommand = $params->{subcommand};

    # URL or local directory path to sources
    my $url = $params->{url};

    # Default to "svn", but allow for any command
    if ($command !~ /\w/) {
        $command = "svn";
    }

    # --force equates to overwriting an existing MPI get
    if ($force) {
        $delete_first = 1;
    }

    # Skip this check if we are starting fresh
    if ((! $delete_first) and defined($previous_r)) {

        # Subversion
        if ($command =~ /\bsvn\b/) {
            $want_new = &MTT::SourceControl::svn_check_previous_revision($previous_r, $url);
        # SVK
        } elsif ($command =~ /\bsvk\b/) {
            $want_new = &MTT::SourceControl::svn_check_previous_revision($previous_r, $url);
        # Mercurial
        } elsif ($command =~ /\bhg\b/) {
            $want_new = &MTT::SourceControl::hg_check_previous_revision($previous_r, $url);
        } else {
            Warning("MTT does not know how to check whether this is a new revision.\n");
            Warning("Assuming it is new.\n");
            $want_new = 1;
        }
    }

    # Set "want_new" status for Get.pm
    $ret->{have_new} = $want_new;

    # We can exit from here if we do not have a new version to test
    if (! $want_new) {
        if ($force) {
            Debug("No new sources, but we are forcing.\n");
        } else {
            $ret->{result_message} = "No new sources to test";
            return $ret;
        }
    }

    # Do the code checkout
    my ($dir, $r) = MTT::SourceControl::Checkout($delete_first, $command, $subcommand, $url);
    if (!$dir) {
        $ret->{test_result} = MTT::Values::FAIL;
        $ret->{result_message} = "Failed to checkout sources.";
        return $ret;
    }

    # More from ProcessInputParameters
    $ret->{prepare_for_install} = $params->{prepare_for_install};
    $ret->{version}             = $params->{version};

    # Pass this data back to the main Get module
    $data->{pre_copy}           = $params->{pre_copy};
    $data->{post_copy}          = $params->{post_copy};
    $data->{url}                = $params->{url};
    $data->{directory}          = $dir;
    $data->{r}                  = $r;

    # Make a best attempt to get a version number
    # 1. Try looking for a field in the INI file
    my $ver;
    if (!defined($ret->{version})) {
        # 2. Try looking for name-<number> in the directory basename
        if ($ver = &get_version_from_filename($dir)) {
            $ret->{version} = $ver;
        } 
        # 3. Use the SVN r number
        elsif (defined($r)) {
            $ret->{version} = "r$r";
        }
        # Give up
        else {
            $ret->{version} = "$params->{simple_section}-" . strftime("%m%d%Y-%H%M%S", localtime);
        }
    }
    $ret->{module_data} = $data;

    # All done
    Debug(">> $package: returning successfully\n");
    return $ret;
}

# Get the version number from the filename
# E.g., "/foo-3.4/bar-1.2" would return "1.2"
sub get_version_from_filename {
    my ($fullname) = @_;

    my $ret;
    my $basename;

    # Start from the right of the filename, and work towards the left
    while (1) {
        $basename = basename($fullname);
        last if (!$basename);

        if ($basename =~ m/\-?([0-9\.]+)/) {
            $ret = $1;
            last;
        }

        last if ($fullname eq $basename);

        # Trim off all but the basename
        $fullname = dirname($fullname);
    }

    return $ret;
}

1;
