#!/usr/bin/env perl
#
# Copyright (c) 2009 Voltaire
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::Reporter::Utils::LinuxClusterInfo;

use strict;
use Data::Dumper;
use MTT::Messages;

sub _collect_hosts_info {
    my $hostList = shift @_;

    Debug("Collect cluster information. Nodes: $hostList\n");

    my @hostarray = split( /,/, $hostList );
    my $hostName = @hostarray[0];
    my $node_count = scalar @hostarray;

    my $error = 0;

    my $info;

    $info->{node_count} = $node_count;
    $info->{node_hostname} = $hostName;

    # get CPU information
    my $cpuInfo;
    for my $host (@hostarray)
    {
       Debug("Collect CPU info for host: $host ...\n");
       open(SHELL, "ssh $host cat /proc/cpuinfo|") || ($error = 1);
        if ($error == 0) {
            my $cpu_count = 0;
            my $cpu_cores = 1;
            my $cpu_model;
            my $cpu_cache        = 0;
            my $cpu_mhz          = 0;
            my $max_processor_id = 0;
            while (<SHELL>) {
                if ( $_ =~ m/^processor\s+:\s+([\S\s]+)\s+$/ ) {
                    $cpu_count++;
                    Debug("Found processor: $1, total=$cpu_count\n");
                }
                if ( $_ =~ m/^cpu cores\s+:\s+([\S\s]+)\s+$/ ) {
                    $cpu_cores = $1;
                }
                if ( $_ =~ m/^model name\s+:\s+(\S[\S\s]+)\s+$/ ) {
                    $cpu_model = $1;
                }
                if ( $_ =~ m/^cache size\s+:\s+(\S[\S\s]+) KB$/ ) {
                   $cpu_cache = $1;
                }
                if ( $_ =~ m/^cpu MHz\s+:\s+([\S\s]+)\s+$/ ) {
                   $cpu_mhz = $1;
                }
                if ( $_ =~ m/^processor id\s+:\s+(\S[\S\s]+)\s+$/ ) {
                    my $id = $1;
                    if ( int($id) > $max_processor_id ) {
                        $max_processor_id = $id;
                    }
                }
            }
            close SHELL;

            open(SHELL, "ssh $hostName 'sudo dmidecode |grep \"Current Speed\"|head -1'|") || ($error = 1);
            if ($error == 0) {
                while (<SHELL>) {
                    if (m/Current Speed: (\S+) MHz/) {
                        Debug("Overrive cpu speed from bios: $1\n");
                        $cpu_mhz = $1;
                    }
                }
                close SHELL;
            } # $error = 0
            else {
                Message( "If sudo was failed then check /etc/sudoers file for proper config \"requiretty\"\n" );
                $error = 0;
            }

            Debug("cpu model: $cpu_model\n");
            Debug("cpu cores: $cpu_cores\n");
            Debug("cpu cache: $cpu_cache\n");
            Debug("cpu mhz: $cpu_mhz\n");

            # TODO add processor aliases
            $cpu_model = "Intel Core2"
                if ( $cpu_model =~ m/Intel\(R\) Core\(TM\)2/ );
            $cpu_model = "AMD Opteron"
                if ( $cpu_model =~ m/AMD Opteron\(tm\)2/ );
            $cpuInfo->{$host}->{node_arch} = $cpu_model;

            $cpuInfo->{$host}->{node_ncpu} = $cpu_count;
            if ( $max_processor_id eq 0 ) {
                $cpuInfo->{$host}->{node_nsocket} = int( $cpu_count / $cpu_cores );
            }
            else {
                $cpuInfo->{$host}->{node_nsocket} = $max_processor_id + 1;
            }
            if ( $max_processor_id eq 0 ) {
                $cpuInfo->{$host}->{node_htt} = 'False';
            }
            else {
                $cpuInfo->{$host}->{node_htt} =
                   ( ( $max_processor_id + 1 ) * $cpu_cores eq $cpu_count )
                   ? "False"
                   : "True";
            }
            $cpuInfo->{$host}->{node_cache} = int($cpu_cache);
            $cpuInfo->{$host}->{node_mhz}   = int($cpu_mhz);
        } # $error = 0
        else {
            $error = 0;
            $cpuInfo->{$host}->{node_arch} = 'ERROR, please check clusterinfo.pm';

            $cpuInfo->{$host}->{node_ncpu} = undef;
            $cpuInfo->{$host}->{node_nsocket} = undef;
            $cpuInfo->{$host}->{node_htt} = undef;
            $cpuInfo->{$host}->{node_cache} = undef;
            $cpuInfo->{$host}->{node_mhz}   = undef;
        }
    } # for $host

    $info = { %$info, %{$cpuInfo->{$hostName}} };

    my $total_mhz = 0;
    for my $host (@hostarray) {
        $total_mhz = $total_mhz + ($cpuInfo->{$host}->{node_ncpu} * $cpuInfo->{$host}->{node_mhz});
    }
    $info->{total_mhz} = $total_mhz;

    # get memory information
    my $memory_total;
    open(SHELL, "ssh $hostName cat /proc/meminfo|") || ($error = 1);
    if ($error == 0) {
        while (<SHELL>) {
            if ( $_ =~ m/^MemTotal:\s+(\S+)\s+kB$/ ) {
                $memory_total = int( ($1+1023) / 1024 );    # in Mb
                last;
            }
        }
        close SHELL;
        $info->{node_mem} = $memory_total;           # in Mb
    } # error = 0
    else {
        $error = 0;
        $info->{node_mem} = undef;
    }

    my $os_kernel;
    open(SHELL, "ssh $hostName uname -r|") || ($error = 1);
    if ($error == 0) {
        while (<SHELL>) {
            if ( $_ =~ m/^([\S\s]+)\s$/ ) {
                $os_kernel = $1;
                last;
            }
        }
        close SHELL;
        $info->{node_os_kernel} = $os_kernel;
    } # $error = 0
    else {
        $error = 0;
        $info->{node_os_kernel} = "ERROR, check clusterinfo.pm";
    }

    my $os_distro_vendor;
    open(SHELL, "ssh $hostName /usr/bin/lsb_release -is|") || ($error = 1);
    if ($error == 0) {
        while (<SHELL>) {
            if ( $_ =~ m/^([\S\s]+)\s$/ ) {
                $os_distro_vendor = $1;
                last;
            }
        }
        close SHELL;
        $info->{node_os_vendor} = $os_distro_vendor;
    } # $error = 0
    else {
        $error = 0;
        $info->{node_os_vendor} = "ERROR, check clusterinfo.pm";
    }


    my $os_distro_release;
    open(SHELL, "ssh $hostName /usr/bin/lsb_release -rs|") || ($error = 1);
    if ($error == 0) {
        while (<SHELL>) {
            if ( $_ =~ m/^([\S\s]+)\s$/ ) {
                $os_distro_release = $1;
                last;
            }
        }
        close SHELL;
        $info->{node_os_release} = $os_distro_release;
    } # $error = 0
    else {
        $error = 0;
        $info->{node_os_release} = "ERROR, check clusterinfo.pm";
    }


# TODO 
#    my $ofed_info_str = "";
#    open(SHELL, "ssh $hostName ofed_info|") || ($error = 1);
#    if ($error == 0) {
#     	   while (<SHELL>) {
#            $ofed_info_str .= $_;
#        }
#        close SHELL;
#        $info->{node_ofed} = $ofed_info_str
#    } # $error = 0
#    else {
#        $error = 0;
#        $info->{node_ofed} = "ERROR, check clusterinfo.pm";
#    }

    my $lspci_str = "";
    open(SHELL, "ssh $hostName lspci -m|") || ($error = 1);
    if ($error == 0) {
        while (<SHELL>) {
            if ( $_ =~ m/(Ethernet|InfiniBand)/ ) {
                $lspci_str .= $_;
            }
        }
        close SHELL;
        $info->{net_pci} = $lspci_str;
    } # $error = 0
    else {
        $error = 0;
        $info->{net_pci} = "ERROR, check clusterinfo.pm";
    }

    my $net_config_str = "";
    my @eth_interfaces = ();
    open(SHELL, "ssh $hostName /sbin/ifconfig -a|") || ($error = 1);
    if ($error == 0) {
        while (<SHELL>) {
            $net_config_str .= $_;
            if (m/(\S+)\s*Link encap:Ethernet/) {
                push( @eth_interfaces, $1 );
            }
        }
        close SHELL;
        $info->{net_conf} = $net_config_str;
    } # $error = 0
    else {
        $error = 0;
        $info->{net_conf} = "ERROR, check clusterinfo.pm";
    }

    my $ethernet = 'False';
    my $ethernet1000 = 'False';
    my $ethernet10G = 'False';
    my $ibddr = 'False';
    my $ibqdr = 'False';
    my $iwarp = 'False';

    open(SHELL, "ssh $hostName 'for card in \$( ls /sys/class/infiniband ); do cat /sys/class/infiniband/\$card/node_type; done;'|") || ($error = 1);
    if ($error == 0) {
        while (<SHELL>) {
            $iwarp = 'True' if ($_ =~ m/RNIC/);
        }
        close SHELL;
    } # $error = 0
    else {
        $error = 0;
    }

    my $ibv_devinfo_str = "";
    open(SHELL, "ssh $hostName ibv_devinfo -v|") || ($error = 1);
    if ($error == 0) {
        while (<SHELL>) {
            $ibv_devinfo_str .= $_;
            if (m/active_speed/) {
                $ibddr = 'True' if ($_ =~ m/\(2\)\s*$/);
                $ibqdr = 'True' if ($_ =~ m/\(4\)\s*$/);
            }
        }
        close SHELL;
    } # $error = 0
    else {
        $error = 0;
    }

    foreach my $eth_interface (@eth_interfaces) {
        open(SHELL, "ssh $hostName sudo ethtool $eth_interface|") || ($error = 1);
        if ($error == 0) {
            while (<SHELL>) {
               if (m/Speed:/) {
                   my $speedStr = $_;
                   if ($speedStr =~ m/Speed:\s1000Mb/) {
                       $ethernet1000 = 'True';
                       next;
                   }
                   if ($speedStr =~ m/Speed:\s10000Mb/) { # TODO
                       $ethernet10G = 'True';
                       next;
                   }
                   $ethernet = 'True' if ($_ =! m/Speed: Unknown/);
               }
            }
            close SHELL;
        } # $error = 0
        else {
            $error = 0;
        }
    }

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