#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2007 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Values::Functions::InfiniBand;

use strict;
use File::Temp qw(tempfile);
use MTT::Messages;
use MTT::DoCommand;
use MTT::FindProgram;
use Data::Dumper;
use Cwd;

#--------------------------------------------------------------------------

sub check_ipoib_connectivity {
    my $x = MTT::DoCommand::Cmd(1, "uname -s");

    if ($x->{result_stdout} =~ /sunos/i) {
        return _check_solaris_ipoib_connectivity();
    } elsif ($x->{result_stdout} =~ /linux/i) {
        return _check_linux_ipoib_connectivity();
    }
}

# Returns true if IPoIB connectivity is available.
# Performs the following tests:
#  1. ping localhost on all nodes
#  2. ping all nodes remotely from head node
#  3. Check that there is a "datadm" entry for each node
sub _check_solaris_ipoib_connectivity {
    my $funclet = '&' . FuncName((caller(0))[3]);

    # Gather some system utilities
    my %utils;
    my $ret;
    my @utils = ("ifconfig", "ping", "orterun", "datadm");

    foreach my $util (@utils) {
        my $prog = FindProgram($util);
        $utils{$util} = $prog;

        if (! $prog) {
            Warning("$funclet: You do not have '$util' in your PATH. " .
                  "\n\tAssuming your IB connections are not UP.\n");
            return "0";
        }
    }

    my $ifconfig = $utils{"ifconfig"};
    my $ping     = $utils{"ping"};
    my $orterun  = $utils{"orterun"};
    my $datadm   = $utils{"datadm"};

    my $cmd = "$ifconfig -a";
    my $x = MTT::DoCommand::Cmd(1, $cmd);

    # Grab the name of the IB interface

    # WARNING: "ib" MAY BE A *MAGIC* PREFIX. SUN'S CLUSTERS
    # HAPPEN TO NAME THEIR IB CARDS WITH THE PREFIX "ib",
    # BUT THIS MAY NOT BE TRUE EVERYWHERE.  TO MAKE THIS
    # PORTABLE, WE MIGHT CONSIDER DOING SOMETHING LIKE: 
    #
    #   $ sudo ifconfig <interface_name> modlist 
    # 
    # TO SEE IF THE IB MODULE IS PRESENT IN THE OUTPUT LIST.
    # WE ALSO ASSUME THE IB CARD IS NAMED IDENTICALLY ACROSS
    # THE WHOLE CLUSTER.
    my $ib_interface;
    foreach my $line (split(/\n|\r/, $x->{result_stdout})) {
        if ($line =~ /^(ib\w+):/) {
            $ib_interface = $1;
            last;
        }
    }

    if (! $ib_interface) {
        Debug("$funclet: $cmd did not print an IB interface.\n");
        return "0";
    }

    # Create a simple script to ping an IB interface
    # (Assume we are currently in an NFS mounted directory)
    my ($fh, $filename) = tempfile(DIR => cwd(), SUFFIX => "-ping");
    my $scriptlet1 = "#!/bin/sh
$ping -i $ib_interface \$*  > /dev/null

if test \"\$?\" = \"0\"; then
    if test \"\$*\" = \"localhost\"; then
        echo `hostname`
    else
        echo \$*
    fi
fi";
    print $fh $scriptlet1;
    close($fh);
    chmod(0700, $filename);

    Debug("$funclet: Running the following script ('$filename') to check on IPoIB availability:\n$scriptlet1\n");

    # Do a localhost ping for each host
    my $hosts = &MTT::Values::Functions::env_hosts(1);
    $cmd = "$orterun --bynode --host $hosts $filename localhost";
    $x = MTT::DoCommand::Cmd(1, $cmd);

    if ($x->{exit_status} ne 0) {
        Debug("$funclet: $cmd failed.\n");
        return "0";
    }

    my @down_nodes;
    my @hosts = split(/\s+|,/, $hosts);
    foreach my $host (@hosts) {
        if ($x->{result_stdout} !~ /\b$host\b/i) {
            push(@down_nodes, $host);
        }
    }

    # Return true, or report which nodes' IB interfaces are down
    if ((scalar @down_nodes) < 1) {
        $ret = 1;
        Debug("$funclet: 'ping localhost' succeeded on all nodes.\n");
    } else {
        $ret = 0;
        Warning("$funclet: 'ping localhost' failed on the following nodes: " .
                "\n\t\t" . join("\n\t\t", @down_nodes) .
                "\n\tReturning $ret.\n");
        return "$ret";
    }

    # Do a head-node to remote-node ping for each host
    @down_nodes = ();
    foreach my $host (@hosts) {
        my $cmd = "$filename $host";
        $x = MTT::DoCommand::Cmd(1, $cmd);

        if ($x->{exit_status} ne 0) {
            Debug("$funclet: $cmd failed.\n");
            return "0";
        }

        if ($x->{result_stdout} !~ /\b$host\b/i) {
            push(@down_nodes, $host);
        }
    }

    # Unlink the little ping script
    unlink($filename);

    # Return true, or report which nodes' IB interfaces are down
    if ((scalar @down_nodes) < 1) {
        $ret = 1;
        Debug("$funclet: IB interfaces are UP on all nodes.\n");
    } else {
        $ret = 0;
        Warning("$funclet: head-node to remote-node ping failed on the following nodes: " .
                "\n\t\t" . join("\n\t\t", @down_nodes) .
                "\n\tReturning $ret.\n");
    }

    # Create a simple script to check DAT registry
    # (Assume we are currently in an NFS mounted directory)
    ($fh, $filename) = tempfile(DIR => cwd(), SUFFIX => "-datadm");
    my $scriptlet2 = "#!/bin/sh
datadm=`$datadm -v | grep $ib_interface | cut -f1 -d' '`
if test \"\$datadm\" != \"\"; then
    echo `hostname`
fi";
    print $fh $scriptlet2;
    close($fh);
    chmod(0700, $filename);

    Debug("$funclet: Running the following script ('$filename') to check on DAT registry for IB interface:\n$scriptlet2\n");

    # Do a localhost ping for each host
    $cmd = "$orterun --bynode --host $hosts $filename";
    $x = MTT::DoCommand::Cmd(1, $cmd);

    if ($x->{exit_status} ne 0) {
        Debug("$funclet: $cmd failed.\n");
        return "0";
    }

    # Unlink the little datadm script
    unlink($filename);

    @down_nodes = ();
    foreach my $host (@hosts) {
        if ($x->{result_stdout} !~ /\b$host\b/i) {
            push(@down_nodes, $host);
        }
    }

    # Return true, or report which nodes' IB interfaces are down
    if ((scalar @down_nodes) < 1) {
        $ret = 1;
        Debug("$funclet: Found a 'datadm' entry on all nodes.\n");
    } else {
        $ret = 0;
        Warning("$funclet: No 'datadm' found on the following nodes: " .
                "\n\t\t" . join("\n\t\t", @down_nodes) .
                "\n\tReturning $ret.\n");
        return "$ret";
    }

    return "$ret";
}

#--------------------------------------------------------------------------

# Returns true if IPoIB connectivity is available
# Performs the following tests:
#  1. ping localhost on all nodes
#  2. ping all nodes remotely from head node
sub _check_linux_ipoib_connectivity {
    my $funclet = '&' . FuncName((caller(0))[3]);

    # Gather some system utilities.  Save PATH and add /sbin and
    # /usr/sbin.
    my $save_path = $ENV{PATH};
    $ENV{PATH} .= ":/sbin:/usr/sbin";
    my %utils;
    my $ret;
    my @utils = ("ifconfig", "ping", "orterun");

    foreach my $util (@utils) {
        my $prog = FindProgram($util);
        $utils{$util} = $prog;

        if (! $prog) {
            Warning("$funclet: You do not have '$util' in your PATH. " .
                  "\n\tAssuming your IB connections are not UP.\n");
            $ENV{PATH} = $save_path;
            return "0";
        }
    }

    my $ifconfig = $utils{"ifconfig"};
    my $ping     = $utils{"ping"};
    my $orterun  = $utils{"orterun"};
    my $datadm   = $utils{"datadm"};

    my $cmd = "$ifconfig -a";
    my $x = MTT::DoCommand::Cmd(1, $cmd);

    # Grab the name of the IB interface

    # WARNING: "ib" MAY BE A *MAGIC* PREFIX. SUN'S CLUSTERS
    # HAPPEN TO NAME THEIR IB CARDS WITH THE PREFIX "ib",
    # BUT THIS MAY NOT BE TRUE EVERYWHERE.  TO MAKE THIS
    # PORTABLE, WE MIGHT CONSIDER DOING SOMETHING LIKE: 
    #
    #   $ sudo ifconfig <interface_name> modlist 
    # 
    # TO SEE IF THE IB MODULE IS PRESENT IN THE OUTPUT LIST.
    # WE ALSO ASSUME THE IB CARD IS NAMED IDENTICALLY ACROSS
    # THE WHOLE CLUSTER.
    my $ib_interface;
    foreach my $line (split(/\n|\r/, $x->{result_stdout})) {
        if ($line =~ /^(ib\w+)/) {
            $ib_interface = $1;
            last;
        }
    }

    if (! $ib_interface) {
        Debug("$funclet: $cmd did not print an IB interface.\n");
        $ENV{PATH} = $save_path;
        return "0";
    }
    print "IB interface: $ib_interface\n";

    # Create a simple script to ping an IB interface
    # (Assume we are currently in an NFS mounted directory)
    my ($fh, $filename) = tempfile(DIR => cwd(), SUFFIX => "-ping");
    my $scriptlet1 = "#!/bin/sh
$ping -c 3 -I $ib_interface \$*  > /dev/null

if test \"\$?\" = \"0\"; then
    if test \"\$*\" = \"localhost\"; then
        echo `hostname`
    else
        echo \$*
    fi
fi
exit 0";
    print $fh $scriptlet1;
    close($fh);
    chmod(0700, $filename);

    Debug("$funclet: Running the following script ('$filename') to check on IPoIB availability:\n$scriptlet1\n");

    # Do a localhost ping for each host
    my $hosts = &MTT::Values::Functions::env_hosts(1);
    $cmd = "$orterun --bynode --host $hosts $filename localhost";
    print "CMD: $cmd\n";
    $x = MTT::DoCommand::Cmd(1, $cmd);

    if ($x->{exit_status} ne 0) {
        Debug("$funclet: $cmd failed.\n");
        $ENV{PATH} = $save_path;
        return "0";
    }
    print "Ping out: $x->{result_stdout}\n";

    my @down_nodes;
    my @hosts = split(/\s+|,/, $hosts);
    foreach my $host (@hosts) {
        if ($x->{result_stdout} !~ /\b$host\b/i) {
            push(@down_nodes, $host);
        }
    }

    # Return true, or report which nodes' IB interfaces are down
    if ((scalar @down_nodes) < 1) {
        Debug("$funclet: 'ping localhost' succeeded on all nodes.\n");
    } else {
        $ret = 0;
        Warning("$funclet: 'ping localhost' failed on the following nodes: " .
                "\n\t\t" . join("\n\t\t", @down_nodes) .
                "\n\tReturning $ret.\n");
        $ENV{PATH} = $save_path;
        return "$ret";
    }

    # Do a head-node to remote-node ping for each host
    @down_nodes = ();
    foreach my $host (@hosts) {
        my $cmd = "$filename $host";
        $x = MTT::DoCommand::Cmd(1, $cmd);

        if ($x->{exit_status} ne 0) {
            Debug("$funclet: $cmd failed.\n");
            $ENV{PATH} = $save_path;
            return "0";
        }

        if ($x->{result_stdout} !~ /\b$host\b/i) {
            push(@down_nodes, $host);
        }
    }

    # Unlink the little ping script
    unlink($filename);

    # Return true, or report which nodes' IB interfaces are down
    if ((scalar @down_nodes) < 1) {
        $ret = 1;
        Debug("$funclet: IB interfaces are UP on all nodes.\n");
    } else {
        $ret = 0;
        Warning("$funclet: head-node to remote-node ping failed on the following nodes: " .
                "\n\t\t" . join("\n\t\t", @down_nodes) .
                "\n\tReturning $ret.\n");
    }

    $ENV{PATH} = $save_path;
    return "$ret";
}

1;
