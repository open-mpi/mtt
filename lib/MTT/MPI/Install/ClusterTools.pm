#!/usr/bin/env perl
#
# Copyright (c) 2007 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::MPI::Install::ClusterTools;

use strict;
use Data::Dumper;
use MTT::DoCommand;
use MTT::Messages;
use MTT::Values;
use MTT::FindProgram;

#--------------------------------------------------------------------------

sub Install {
    my ($ini, $section, $config) = @_;
    my $x;
    my $package = ModuleName(__PACKAGE__);

    # Process clustertools input parameters
    my $connection_method = Value($ini, $section, "clustertools_connection_method");
    my $activate = Value($ini, $section, "clustertools_activate");

    if ($activate) {
        $activate = "-a";
    }

    # Prepare $ret
    my $ret;
    $ret->{test_result} = MTT::Values::FAIL;
    $ret->{exit_status} = 0;

    my $bindir = "$config->{abs_srcdir}/Product/Install_Utilities/bin";
    my $installer = "ctinstall";
    my $ctinstall = "$bindir/$installer";

    # Find sudo
    my $sudo = FindProgram("sudo");
    if (!defined($sudo)) {
        Error("$package: requires 'sudo'.\n");
        return undef;
    }

    my $want_unique = 1;
    my $hosts = &MTT::Values::Functions::env_hosts($want_unique);

    # Set package location of ClusterTools
    my $basedir = "/opt/SUNWhpc";

    # Deactivate ClusterTools
    my $ctdeact = "$basedir/bin/Install_Utilities/bin/ctdeact";
    if (-x $ctdeact) {
        $x = MTT::DoCommand::Cmd(1, "$sudo $ctdeact -n $hosts -r $connection_method");
    }

    # Install ClusterTools
    $x = MTT::DoCommand::Cmd(1, "$sudo $ctinstall $activate -n $hosts -r $connection_method");

    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        Verbose("$package: $installer failed: $@\n");
        return undef;
    }

    $ret->{installdir} = $basedir;
    $ret->{bindir} = "$ret->{installdir}/bin";
    $ret->{libdir} = "$ret->{installdir}/lib";

    # Set which bindings were compiled

    $ret->{c_bindings} = 1;
    Debug("$package: Have C bindings: 1\n");
    my $func = \&MTT::Values::Functions::MPI::OMPI::find_bindings;
    $ret->{cxx_bindings} = &{$func}($ret->{bindir}, $ret->{libdir}, "cxx");
    Debug("$package: Have C++ bindings: $ret->{cxx_bindings}\n"); 
    $ret->{f77_bindings} = &{$func}($ret->{bindir}, $ret->{libdir}, "f77");
    Debug("$package: Have F77 bindings: $ret->{f77_bindings}\n"); 
    $ret->{f90_bindings} = &{$func}($ret->{bindir}, $ret->{libdir}, "f90");
    Debug("$package: Have F90 bindings: $ret->{f90_bindings}\n"); 

    # Set bitness (EAM: 32-bit and 64-bit should both be validated)
    $ret->{bitness} = "32,64";

    # All done
    Debug(">> $package: returning successfully\n");
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";

    return $ret;
} 

1;
