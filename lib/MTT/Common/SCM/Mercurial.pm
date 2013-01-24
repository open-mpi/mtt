#!/usr/bin/env perl
#
# Copyright (c) 2007-2009 Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2008      Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Common::SCM::Mercurial;
my ($package) = (__PACKAGE__ =~ m/(\w+)$/);

use strict;
use URI;
use URI::Escape;
use File::Basename;
use MTT::Messages;
use MTT::Values;
use MTT::DoCommand;
use MTT::FindProgram;
use Data::Dumper;

#--------------------------------------------------------------------------

sub Checkout {
    my ($params) = @_;

    my $ret;

    # Default destination dir to the URL's basename
    if (! defined($params->{dirname})) {
        $params->{dirname} = basename($params->{url});
    }

    # Assemble the command
    my $cmd = defined($params->{cmd}) ? $params->{cmd} : "hg";
    $cmd .= " " . $params->{command_arguments}
        if (defined($params->{command_arguments}));

    $cmd .= " " . 
        (defined($params->{subcommand}) ? $params->{subcommand} : "clone");
    $cmd .= " " . $params->{subcommand_arguments}
        if (defined($params->{subcommand_arguments}));
    if (defined($params->{rev})) {
        if (defined($params->{clone_all}) && $params->{clone_all}) {
            $cmd .= " -u ";
        }
        else {
            $cmd .= " -r ";
        }

        $cmd .= $params->{rev};
    };
    $cmd .= " ";

    my $hg_major = 0;
    my $hg_minor = 0;
    my $hg_cmd = (defined($params->{cmd}) ? $params->{cmd} : "hg") . " --version"; 

    my $hg_ver_output = MTT::DoCommand::Cmd(1, $hg_cmd);

    if (MTT::DoCommand::wsuccess($hg_ver_output->{exit_status}) && 
        $hg_ver_output->{result_stdout} =~ m/version (\d+).(\d+)/) {
        ($hg_major, $hg_minor) = ($1, $2);
    } 
    
    if (defined($params->{username}) && (($hg_major > 1)||($hg_major == 1 && $hg_minor >= 9))) {
        my $u = URI->new($params->{url});
        $u->userinfo($params->{username} . ":" . $params->{password});
        $cmd .= uri_unescape($u->as_string());
    } else {
        $cmd .= $params->{url};
    }
    $cmd .= " " . $params->{dirname};
	
    my $x = MTT::DoCommand::Cmd(1, $cmd);
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        Warning("HG clone failure: $x->{result_stdout}\n");
        return undef;
    }

    return _hg_identify_n($params->{dirname});
}

sub _hg_identify_n {
    my ($dir) = @_;

    my $funclet = '&' . FuncName((caller(0))[3]);
    Debug("$funclet: got @_\n");

    if (! FindProgram(qw(hg))) {
        Warning("$funclet() can not continue wihtout 'hg'.\n");
        return undef;
    }

    # Change into the Mercurial directory
    MTT::DoCommand::Pushdir($dir);

    # Run the "identify" command
    my $ret;
    my $cmd = "hg identify -n";
    my $x = MTT::DoCommand::Cmd(1, $cmd);
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        Warning("HG identify failure: $x->{result_stdout}\n");
        return undef;
    } else {
        $ret = $x->{result_stdout};
        $ret =~ s/\s+(\S*)\s+/\1/;
    }

    # Remove the newline
    chomp $ret;

    # Return to the last directory
    MTT::DoCommand::Popdir();

    Debug("$funclet returning $ret\n");
    return $ret;
}

# Throw away the first argument. Do a sequence
# hg pull/revert sequence to see what happens
sub check_previous_revision {
    my ($z, $url) = @_;

    my $ret = 0;

    my $function = '&' . FuncName((caller(0))[3]);
    Debug("$function: got @_\n");

    # Do an "hg pull" and see what happens ...
    MTT::DoCommand::Pushdir(basename($url));
    my $x = MTT::DoCommand::Cmd(1, "hg pull");
    my $y = MTT::DoCommand::Cmd(1, "hg revert");
    MTT::DoCommand::Popdir();

    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        Warning("Can't check the repository: $x->{result_stdout}.\n\tGoing to assume we need a new checkout.\n");
        $ret = 1;
        return $ret;
    } else {

        # Two possible outcomes:

        # 1.
        # $ hg pull
        # pulling from /foo/bar
        # searching for changes
        # adding changesets
        # adding manifests
        # adding file changes
        # added 1 changesets with 0 changes to 0 files
        # (run 'hg update' to get a working copy)
        my $pattern_have_new = 'added \s+ \d+ \s+ changesets';

        # 2.
        # $ hg pull
        # pulling from /foo/bar
        # searching for changes
        # no changes found
        my $pattern_have_old = 'no \s+ changes \s+ found';

        # Check the output against the patterns
        if ($x->{result_stdout} =~ /$pattern_have_old/ixo) {
            Debug("Found the pattern: '$pattern_have_old' -- no need for new checkout.\n");
        } elsif ($x->{result_stdout} =~ /$pattern_have_new/ixo) {
            $ret = 1;
            Debug("Found the pattern: '$pattern_have_new' -- need new checkout.\n");
        }
    }

    Debug("$function returning $ret\n");
    return $ret;
}

1;
