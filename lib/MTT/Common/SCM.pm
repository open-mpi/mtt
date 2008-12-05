#!/usr/bin/env perl
#
# Copyright (c) 2007-2008 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007-2008 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Common::SCM;
my ($package) = (__PACKAGE__ =~ m/(\w+)$/);

use strict;
use File::Basename;
use POSIX;
use MTT::Messages;
use MTT::Values;
use MTT::INI;
use MTT::DoCommand;
use MTT::FindProgram;
use MTT::Module;
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

    # Default scm_module
    $params->{scm_module} = "SVN"
        if (! defined($params->{scm_module}));

    # --force equates to overwriting an existing checkout
    $ret->{have_new} = 1;
    $params->{delete_first} = 1
        if ($force);

    # Skip this check if we are starting fresh
    if ((! $params->{delete_first}) and defined($previous_r)) {
        $ret->{have_new} =
            MTT::Module::Run("MTT::Common::SCM::$params->{scm_module}",
                             "check_previous_revision", $previous_r,
                             $params->{url});
    }

    # We can exit from here if we do not have a new version to test
    if (! $ret->{have_new}) {
        if ($force) {
            Debug("No new sources, but we are forcing.\n");
        } else {
            $ret->{result_message} = "No new sources";
            return $ret;
        }
    }

    # Strip off trailing slash for basename
    my $cwd = MTT::DoCommand::cwd();
    $params->{url} =~ s/\/\s*$//;
    my $basename = basename($params->{url});
    $params->{dirname} = "$cwd/$basename";

    # Remove the cwd portion of the dirname so that we do not erroneously get a
    # version string from the users scratch dirname or INI section name
    my $scm_dirname = $params->{dirname};
    $scm_dirname    =~ s/(\/+|\\+)/\//g;
    $cwd            =~ s/(\/+|\\+)/\//g;
    $scm_dirname    =~ s/$cwd//;

    MTT::DoCommand::Cmd(1, "rm -rf $basename")
        if ($params->{delete_first});

    # Do the code checkout
    my $r = MTT::Module::Run("MTT::Common::SCM::$params->{scm_module}",
                             "Checkout", $params);
    if (!defined($r)) {
        $ret->{test_result} = MTT::Values::FAIL;
        $ret->{result_message} = "Failed to checkout";
        return $ret;
    }

    # Make a best attempt to get a version number
    # 1. Try looking for a field in the INI file
    my $ver;
    if (!defined($ret->{version})) {
        # 2. Try looking for name-<number> in the directory basename
        if ($ver = &get_version_from_filename($scm_dirname)) {
            Debug("Getting version string from name-<number> in the directory basename.\n");
            $ret->{version} = $ver;
        } 
        # 3. Use the SVN r number
        elsif (defined($params->{rev})) {
            Debug("Getting version string from the SCM r number.\n");
            $ret->{version} = "r$params->{rev}";
        }
        # Give up
        else {
            Debug("Couldn't find a decent version string. Using a date string.\n");
            $ret->{version} = "$params->{simple_section}-" . 
                strftime("%m%d%Y-%H%M%S", localtime);
        }
    }

    # More from ProcessInputParameters
    $ret->{prepare_for_install} = $params->{prepare_for_install};

    # Pass this data back to the main Get module
    $data->{pre_copy}           = $params->{pre_copy};
    $data->{post_copy}          = $params->{post_copy};
    $data->{url}                = $params->{url};
    $data->{directory}          = $params->{dirname};
    $data->{r}                  = $params->{rev};

    $ret->{module_data} = $data;

    # All done
    Debug(">> $package: returning successfully\n");
    return $ret;
}

sub get_version_from_filename {
    Debug("get_version_from_filename got @_\n");
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

    Debug("get_version_from_filename returning $ret\n");
    return $ret;
}

# Process INI parameter functions for any Subverison-like versioning
# system. We default to SVN for backcompatibility and because SVN is 
# what the Open MPI community uses.
sub ProcessInputParameters {
    Debug(">> ProcessInputParameters\n");
    my ($ini, $section) = @_;

    # Prepare a return value
    my $ret;

    # See if we got a url in the ini section
    my $url = Value($ini, $section, &_prefix_parameter("url"));
    if (!$url) {
        $ret->{result_message} = "No URL specified in [$section]; skipping";
        Warning("$ret->{result_message}\n");
        return $ret;
    }
    Debug(">> $package: got url $url\n");

    # Process INI file parameters
    foreach my $k (qw/url r rev username password password_cache export checkout command command_arguments subcommand subcommand_arguments delete_first pre_copy post_copy version/) {
        $ret->{$k} = Value($ini, $section, &_prefix_parameter($k));
    }

    $ret->{module} = Value($ini, $section, "module");
    $ret->{scm_module} = Value($ini, $section, "scm_module");

    if (defined($ret->{r})) {
        Warning("SCM param 'r' is deprecated.  Use 'rev' instead\n");
        $ret->{rev} = $ret->{r};
    }

    # Setup sub-command
    # EAM: move to SVN.pm
    if ($ret->{export} and $ret->{checkout}) {
        Warning("SCM params 'export' and 'checkout' were both specified. Defaulting to export.\n");
        Warning("Both of these parameters are deprecated. Use \"*_subcommand = <subcommand>\" instead.\n");
        $ret->{subcommand} = "export";
    } elsif ($ret->{checkout}) {
        Warning("SCM param 'checkout' is deprecated. Use \"*_subcommand = checkout\" instead.\n");
        $ret->{subcommand} = "checkout";
    } elsif ($ret->{export}) {
        Warning("SCM param 'export' is deprecated. Use \"*_subcommand = export\" instead.\n");
        $ret->{subcommand} = "export";
    }

    # Default to overwriting an existing checkout
    if (! defined($ret->{delete_first})) {
        $ret->{delete_first} = 1;
    }

    # Set the function pointer -- note that we just re-use the
    # copytree module, since that's all we have to do (i.e., copy a
    # local tree)
    $ret->{prepare_for_install} = "MTT::Common::Copytree::PrepareForInstall";
    my $tmp;
    $tmp = Value($ini, $section, &_prefix_parameter("pre_export"));
    if (defined($tmp)) {
        Warning("The 'pre_export' SCM field is deprecated.  Please use 'pre_copy' instead.\n");
        $ret->{pre_copy} = $tmp;
    }
    $tmp = Value($ini, $section, &_prefix_parameter("post_export"));
    if (defined($tmp)) {
        Warning("The 'post_export' SCM field is deprecated.  Please use 'post_copy' instead.\n");
        $ret->{post_copy} = $tmp;
    }

    $ret->{simple_section} = GetSimpleSection($section);

    # Sanity check

    Error("Must supply a URL parameter for the SCM module")
        if (!defined($ret->{url}));

    return $ret;
}

sub _prefix_parameter {
    my ($str) = @_;

    # Accept any of the below as INI parameter prefixes for an SVN section
    my @valid_versioning_tools = (
        "scm",

        # No way to deprecate these at the moment
        "svn",
        "svk",
        "hg",
        "cvs",
        "rcs",
        "sccs",
        "teamware",
        "git",
    );

    return map { "${_}_$str" } @valid_versioning_tools;
}

1;
