#!/usr/bin/env perl
#
# Copyright (c) 2010 Voltaire
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::Reporter::Utils::UnknownCluster;

use strict;
use Data::Dumper;
use MTT::Messages;

sub _collect_hosts_info {
    my $hostList = shift @_;

    my @hostarray = split( /,/, $hostList );
    my $hostName = @hostarray[0];
    my $node_count = scalar @hostarray;

    my $info;

    $info->{node_count} = $node_count;
    $info->{node_hostname} = $hostName;

    $info->{node_arch} = 'unknown';

    $info->{node_ncpu} = undef;
    $info->{node_nsocket} = undef;
    $info->{node_htt} = undef;
    $info->{node_cache} = undef;
    $info->{node_mhz}   = undef;

    $info->{total_mhz} = 1000; # Dummy value

    $info->{node_mem} = undef;

    $info->{node_os_kernel} = "";

    $info->{node_os_vendor} = "";

    $info->{node_os_release} = "";

    $info->{net_pci} = "";

    $info->{net_conf} = "";

    my $ethernet = 'False';
    my $ethernet1000 = 'False';
    my $ethernet10G = 'False';
    my $ibddr = 'False';
    my $ibqdr = 'False';
    my $iwarp = 'False';

    $info->{net_eth100} = $ethernet;
    $info->{net_eth1000} = $ethernet1000;
    $info->{net_eth10k} = $ethernet10G;

    $info->{net_iwarp} = $iwarp;
    $info->{net_ibddr} = $ibddr;
    $info->{net_ibqdr} = $ibqdr;

    return $info;
}

sub get_cluster_info {
    my $hostList = shift @_;
    if (!defined($hostList) || $hostList eq "") {
        die "ERROR: Host list is empty.";
    }

    my $hostInfo = _collect_hosts_info($hostList);
   
    return $hostInfo;
}

1;