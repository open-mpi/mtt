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
    
    $cmd .= " ";

    my $git_major = 0;
    my $git_minor = 0;
    my $git_cmd = (defined($params->{cmd}) ? $params->{cmd} : "git") . " --version"; 

    my $git_ver_output = MTT::DoCommand::Cmd(1, $git_cmd);

    if (MTT::DoCommand::wsuccess($git_ver_output->{exit_status}) && 
        $git_ver_output->{result_stdout} =~ m/git version (\d+).(\d+).(\d+).(\d+)/) {
        ($git_major, $git_minor) = ($1, $2);
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

sub _git_identify_n {
    # TODO
    my $ret = 0;
    return $ret;
}

# TODO
#sub check_previous_revision 

1;
