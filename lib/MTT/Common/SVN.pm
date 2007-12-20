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

package MTT::Common::SVN;

use strict;
use Cwd;
use File::Basename;
use POSIX qw(strftime);
use MTT::Messages;
use MTT::Values;
use MTT::Files;

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $previous_r) = @_;

    my $ret;
    my $data;

    Debug(">> in SVN get\n");
    $ret->{test_result} = MTT::Values::FAIL;
    # See if we got a url in the ini section
    $data->{url} = Value($ini, $section, "svn_url");
    if (!$data->{url}) {
        $ret->{result_message} = "No URL specified in [$section]; skipping";
        Warning("$ret->{result_message}\n");
        return $ret;
    }
    Debug(">> svn: got url $data->{url}\n");

    # If we have a previous r number, check to see if we need a new
    # export

    if ($previous_r) {
        # Run "svn log -r <old r number>:HEAD $url" and see what comes
        # up.

        my $x = MTT::DoCommand::Cmd(1, "svn log -r $previous_r:HEAD $data->{url}");
        if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
            Warning("Can't check repository properly; going to assume we need a new export\n");
            last;
        } else {

            # There are two possibilities:

            # 1. one line of "-----", meaning that there have been no
            # commits in this directory of the repository since the
            # last R number.

            # 2. one or more entries of log messages.  In this case,
            # we need to look at the r number of the first entry
            # that comes along.  It may be the old r number (i.e.,
            # it's still the HEAD), in which case we don't need a
            # new checkout.  Or it may be a different r number, in
            # which case we need a new checkout.

            my $need_new;
            if ($x->{result_stdout} =~ /^-+\n$/) {
                $need_new = 0;
                Debug("Got one line of dashes -- no need for new export\n");
            } else {
                $x->{result_stdout} =~ m/^-+\nr(\d+)\s/;
                if ($1 eq $previous_r) {
                    $need_new = 0;
                    Debug("Got old r number -- no need for new export\n");
                } else {
                    $need_new = 1;
                    Debug("Got new r number ($1) -- need new export\n");
                }
            }
            
            if ($need_new) {
                Debug(">> svn: we have this URL, but the repository has changed and we need a new export\n");
            } else {
                Debug(">> svn: we have this URL and the repository has not changed; skipping\n");
                $ret->{test_result} = MTT::Values::PASS;
                $ret->{have_new} = 0;
                $ret->{result_message} = "Repository has not changed (did not re-export)";
                return $ret;
            }
        }
    }
    Debug(">> svn: performing export\n");
    $ret->{have_new} = 1;

    # Cache it
    Debug(">> svn: exporting\n");
    my $dir = cwd();
    my $svn_r = Value($ini, $section, "svn_r");
    my $svn_username = Value($ini, $section, "svn_username");
    my $svn_password = Value($ini, $section, "svn_password");
    my $svn_password_cache = Value($ini, $section, "svn_password_cache");
    my $svn_export = Value($ini, $section, "svn_export");
    my $svn_checkout = Value($ini, $section, "svn_checkout");
    my $svn_command = Value($ini, $section, "svn_command");

    # Allow for "svk", but default to "svn"
    if (! $svn_command) {
        $svn_command = "svn";
    }

    my $export;
    if ($svn_export and $svn_checkout) {
        Warning(">> svn: 'svn export' and 'svn checkout' were both specified. Defaulting to 'svn export'.\n");
        $export = 1;
    } elsif ($svn_checkout) {
        $export = 0;
    } else {
        $export = 1;
    }

    MTT::DoCommand::Chdir($dir);
    ($dir, $data->{r}) = MTT::Files::svn_checkout($data->{url}, $svn_r, $svn_username, $svn_password, $svn_password_cache, 1, $export, $svn_command);
    if (!$dir) {
        $ret->{test_result} = MTT::Values::FAIL;
        $ret->{result_message} = "Failed to SVN export";
        $ret->{have_new} = 0;
        return $ret;
    }
    $data->{directory} = cwd() . "/$dir";

    # Set the function pointer -- note that we just re-use the
    # copytree module, since that's all we have to do (i.e., copy a
    # local tree)
    $ret->{prepare_for_install} = "MTT::Common::Copytree::PrepareForInstall";

    # Get other values (set for copytree's PrepareForInstall)
    $data->{pre_copy} = Value($ini, $section, "svn_pre_export");
    $data->{post_copy} = Value($ini, $section, "svn_post_export");

    # Make a best attempt to get a version number
    # 1. Try looking for a field in the INI file
    $ret->{version} = Value($ini, $section, "svn_version");
    if (!defined($ret->{version})) {
        # 2. Try looking for name-<number> in the directory basename
        if ($dir =~ m/[\w-]+(\d.+)/) {
            $ret->{version} = $1;
        } 
        # 3. Use the SVN r number
        elsif ($data->{r}) {
            $ret->{version} = "r$data->{r}";
        }
        # Give up
        else {
            $ret->{version} = "$dir-" . strftime("%m%d%Y-%H%M%S", localtime);
        }
    }
    $ret->{module_data} = $data;

    # All done
    Debug(">> svn: returning successfully\n");
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
