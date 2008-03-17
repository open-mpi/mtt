#!/usr/bin/env perl
#
# Copyright (c) 2007 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Common::SCM;
my ($package) = (__PACKAGE__ =~ m/(\w+)$/);

use strict;
use Cwd;
use File::Basename;
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
    my $scm_module = $params->{scm_module};

    # Do we want to overwrite previous sources?
    my $delete_first = $params->{delete_first};

    # Main command (i.e., svn, hg, git)
    my $command = $params->{command};

    # Sub-command (i.e., export, checkout, clone)
    my $subcommand = $params->{subcommand};

    # URL or local directory path to sources
    my $url = $params->{url};

    # Default scm_module
    if (! defined($scm_module)) {
        $scm_module = "SVN";
    }

    # Default commands/subcommands
    if ($scm_module eq "SVN") {
        $command = "svn" if (! $command);
        $subcommand = "export" if (! $subcommand);
    } elsif ($scm_module eq "Mercurial") {
        $command = "hg" if (! $command);
        $subcommand = "clone" if (! $subcommand);
    } elsif ($scm_module eq "SVK") {
        $command = "svk" if (! $command);
        $subcommand = "checkout" if (! $subcommand);
    } else {
        Warning("MTT does not have a source control plugin for \"$scm_module\". Using \"Unknown\".\n");
    }

    # --force equates to overwriting an existing MPI get
    if ($force) {
        $delete_first = 1;
    }

    # Skip this check if we are starting fresh
    if ((! $delete_first) and defined($previous_r)) {

        if (defined($scm_module)) {
            $want_new =
                MTT::Module::Run("MTT::Common::SCM::$scm_module", "check_previous_revision", $previous_r, $url);
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

    # Do the scm_module checkout
    Debug("Checkout: " . ($url ? $url : $command) . "\n");

    my $basename;
    my $dirname;
    my $cwd = cwd();

    # Some SCMs do not have a naked [SOURCE] argument.
    # E.g., teamware uses "-p [SOURCE]". In these cases,
    # we give the programmer the benefit of the doubt that
    # they've constructed a valid checkout command, but 
    # we also ignore the delete_first parameter
    if ($url) {
        # Strip off trailing slash for basename
        $url =~ s/\/\s*$//;

        $basename = basename($url);
        $dirname = "$cwd/$basename";
        MTT::DoCommand::Cmd(1, "rm -rf $basename")
            if ($delete_first);
    }

    my $cmd = "$command $subcommand $url $dirname";

    if (! $scm_module) {
        $scm_module = "Unknown";
    }

    # Do the code checkout
    my $r = MTT::Module::Run("MTT::Common::SCM::$scm_module", "Checkout", $cmd, $url);

    if (!$dirname) {
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
    $data->{directory}          = $dirname;
    $data->{r}                  = $r;

    # Make a best attempt to get a version number
    # 1. Try looking for a field in the INI file
    my $ver;
    if (!defined($ret->{version})) {
        # 2. Try looking for name-<number> in the directory basename
        if ($ver = &get_version_from_filename($dirname)) {
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
    my $r                    = Value($ini, $section, &_prefix_parameter("r"));
    my $username             = Value($ini, $section, &_prefix_parameter("username"));
    my $password             = Value($ini, $section, &_prefix_parameter("password"));
    my $password_cache       = Value($ini, $section, &_prefix_parameter("password_cache"));
    my $export               = Value($ini, $section, &_prefix_parameter("export"));   # Deprecated
    my $checkout             = Value($ini, $section, &_prefix_parameter("checkout")); # Deprecated
    my $command              = Value($ini, $section, &_prefix_parameter("command"));
    my $command_arguments    = Value($ini, $section, &_prefix_parameter("command_arguments"));
    my $subcommand           = Value($ini, $section, &_prefix_parameter("subcommand"));
    my $subcommand_arguments = Value($ini, $section, &_prefix_parameter("subcommand_arguments"));
    my $delete_first         = Value($ini, $section, &_prefix_parameter("delete_first"));

    my $module = Value($ini, $section, "module");
    my $scm_module = Value($ini, $section, "scm_module");

    # Setup sub-command
    # EAM: move to SVN.pm
    my $export;
    if ($export and $checkout) {
        Warning("export and checkout were both specified. Defaulting to export.\n");
        Warning("Both of these parameters are deprecated. Use \"*_subcommand = <subcommand>\" instead.\n");
        $subcommand = "export";
    } elsif ($checkout) {
        Warning("checkout is deprecated. Use \"*_subcommand = checkout\" instead.\n");
        $subcommand = "checkout";
    } elsif ($export) {
        Warning("export is deprecated. Use \"*_subcommand = export\" instead.\n");
        $subcommand = "export";
    }

    # Append arguments to commands
    # EAM: move to SVN.pm
    $command .= " $command_arguments "  if ($command_arguments);
    $command .= " -r $r "                if ($r);
    $command .= " --username $username " if ($username);
    $command .= " --password $password " if ($password);
    $command .= " --no-auth-cache "      if ("0" eq $password_cache);

    $subcommand .= " $subcommand_arguments "
        if ($subcommand_arguments);

    # Default to overwriting an existing checkout
    if (! defined($delete_first)) {
        $delete_first = 1;
    }

    # Set the function pointer -- note that we just re-use the
    # copytree module, since that's all we have to do (i.e., copy a
    # local tree)
    $ret->{prepare_for_install} = "MTT::Common::Copytree::PrepareForInstall";
    $ret->{pre_copy}            = Value($ini, $section, &_prefix_parameter("pre_export"));
    $ret->{post_copy}           = Value($ini, $section, &_prefix_parameter("post_export"));
    $ret->{version}             = Value($ini, $section, &_prefix_parameter("version"));

    $ret->{delete_first}   = $delete_first;
    $ret->{command}        = $command;
    $ret->{subcommand}     = $subcommand;
    $ret->{url}            = $url;
    $ret->{module}         = $module;
    $ret->{scm_module}     = $scm_module;

    $ret->{simple_section} = GetSimpleSection($section);

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
