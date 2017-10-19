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

package MTT::Common::SCM::Git;
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
    my $cmd = defined($params->{cmd}) ? $params->{cmd} : "git";
    $cmd .= " " . $params->{command_arguments}
        if (defined($params->{command_arguments}));

    $cmd .= " " .
        (defined($params->{subcommand}) ? $params->{subcommand} : "clone");
    $cmd .= " " . $params->{subcommand_arguments}
        if (defined($params->{subcommand_arguments}));

    if (defined($params->{rev})) {
        $cmd .= " -b ";
        $cmd .= $params->{rev};
    }

    if (defined($params->{shallow})) {
        $cmd .= " --depth 1";
    }

    $cmd .= " ";

    my $git_major = 0;
    my $git_minor = 0;
    my $git_cmd = (defined($params->{cmd}) ? $params->{cmd} : "git") . " --version";

    my $git_ver_output = MTT::DoCommand::Cmd(1, $git_cmd);

    if (MTT::DoCommand::wsuccess($git_ver_output->{exit_status}) &&
        $git_ver_output->{result_stdout} =~ m/git version (\d+).(\d+).(\d+).(\d+)/) {
        ($git_major, $git_minor) = ($1, $2);
    }

    # clone only the branch specified to potentially reduce the size of the dir
    if (defined($params->{rev})) {
        # git 1.7.10 added this option, so check the version
        if( $git_major > 1 || ($git_major == 1 && $git_minor > 7) ) {
            $cmd .= " --single-branch ";
        }
    }

    if (defined($params->{username})) {
        my $u = URI->new($params->{url});
        $u->userinfo($params->{username} . ":" . $params->{password});
        $cmd .= uri_unescape($u->as_string());
    } else {
        $cmd .= $params->{url};
    }
    $cmd .= " " . $params->{dirname};

    my $x = MTT::DoCommand::Cmd(1, $cmd);
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        Warning("Git clone failure: $x->{result_stdout}\n");
        return undef;
    }

    return _git_identify_n($params->{dirname});
}

# Assume that we have a nice tag to reference
sub _git_identify_n {
    my $dirname = shift;

    my $start = MTT::DoCommand::cwd();
    chdir($dirname);
    my $msg = `git describe --tags --always`;
    chdir($start);

    chomp($msg);
    $msg =~ m/-(\d+)-\S+$/;
    my $r = $1;

    # If we didn't find a tag, just give up
    $r = 0
        if (!defined($r) || $r eq "");

    return $r;
}

sub check_previous_revision {
    my ($previous_r, $url) = @_;

    my $function = '&' . FuncName((caller(0))[3]);
    Debug("$function: got @_\n");

    my $ret = 1;

    if ($previous_r) {

        # If the first character of the git URL is a /, we can just
        # use "git -C <dir> describe ..." to get the current r.
        if ($url =~ /^\//) {
            my $n = _git_identify_n($url);
            if ($n > $1) {
                Debug("Got new git tag number ($n) -- need new export\n");
                $ret = 1;
            } else {
                Debug("Got old git tag number ($n) -- no need for a new export\n");
                $ret = 0;
            }
        }

        # Otherwise, there does not seem to be an easy way to query
        # the tag of a remote repo without cloning it first, which
        # kinda defeats the point of checking to see if there's
        # anything new before cloning. :-( So just return that there
        # are new sources to test.  Someone could write a better
        # method here someday.
        else {
            Debug("Git repo is remote; cannot check if there is anything new, so we simply assume that there is something new!\n");
            $ret = 1;
        }
    } else {
        Debug("$function no previous revision to check against.\n");
    }

    Debug("$function returning $ret\n");
    return $ret;
}

1;
