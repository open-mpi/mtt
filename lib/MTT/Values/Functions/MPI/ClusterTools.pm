#!/usr/bin/env perl
#
# Copyright (c) 2007 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Values::Functions::MPI::ClusterTools;
my $package = ModuleName(__PACKAGE__);

use strict;
use Data::Dumper;
use MTT::Messages;
use MTT::DoCommand;
use MTT::FindProgram;
use Cwd;

#--------------------------------------------------------------------------

# Setup some shell-scripts in the ClusterTools 6 area to
# call the wrapper compilers using flags that are compatible
# with ClusterTools 7+ compilers
sub setup_shell_scripts_for_wrappers {
    my $dirname = "/opt/SUNWhpc/HPC6.0/bin";

    if (! -d $dirname) {
        Verbose("ClusterTools 6 is not installed on this system. Returning.\n");
        return undef;
    }

    # Find sudo
    my $sudo = FindProgram("sudo");
    if (!defined($sudo)) {
        Warning("&setup_shell_scripts_for_wrappers(): requires 'sudo'. Returning.\n");
        return undef;
    }

    my $save_cwd = cwd();
    MTT::DoCommand::Chdir($dirname);

    # ClusterTools 7 to ClusterTools 6 compiler name mappings
    my $wrappers;
    $wrappers->{"mpicc"}  = "mpcc";
    $wrappers->{"mpic++"} = "mpCC";
    $wrappers->{"mpif77"} = "mpf77";
    $wrappers->{"mpif90"} = "mpf90";

    my $ct6_wrapper;
    my $tempfile;
    foreach my $ct7_wrapper (keys %$wrappers) {
        $ct6_wrapper = $wrappers->{$ct7_wrapper};
        $tempfile = "/tmp/$ct7_wrapper";

        # Write a shell script to make the new ClusterTools 6 wrapper
        # essentially behave like the ClusterTools 7 wrapper
        open(WRAPPER, "> $tempfile");
        print WRAPPER "#!/bin/sh\n" .
                      "$dirname/$ct6_wrapper -lmpi \$*\n";
        chmod(0755, $tempfile);

        # Move the tempfile into the ClusterTools 6 area
        MTT::DoCommand::Cmd(1, "$sudo mv -f $tempfile $dirname");
        close(WRAPPER);
    }

    # Return to last cwd()
    MTT::DoCommand::Chdir($save_cwd);

    return 1;
}

1;
