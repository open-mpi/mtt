#!/usr/bin/perl -w
#
# Copyright (c) 2009 Voltaire
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

use strict;
use Math::Complex;
use Getopt::Long;


sub Collect_Hosts_Info
{
    my ($r_cpu,$r_mem,@hosts)=@_;
    foreach my $host (@hosts) {
        if ($host =~ /^([^:]+):(\d+)$/) {
            $host = $1; # for mem info
            my $ncpu = $2;
            push (@$r_cpu,$ncpu);
        } else {
            my $tmp_cpu_info=`ssh $host \"cat /proc/cpuinfo\" | egrep \'processor\\s*:\' |wc -l`;
            chomp $tmp_cpu_info;
            push (@$r_cpu,$tmp_cpu_info);
        }
        my $tmp_mem_info=`ssh $host \"cat /proc/meminfo | grep MemTotal\"`;
        chomp $tmp_mem_info;
        if($tmp_mem_info=~/(\d+)/) {
            $tmp_mem_info=$1;
        }
        else {
            print ("Can't get info from $host\n");
            exit;
        }
        push (@$r_mem,$tmp_mem_info);
    }

}

sub Calc_Np_Short
{
    my ($p,$q,$np)=@_;
	my $i = int(sqrt($np));
	my $j = int($np / $i);
	push (@$p,$i);
	push (@$q,$j);
}


sub Calc_NP
{
    my ($p,$q,$np)=@_;
    for(my $i=1;$i<=int(sqrt($np));$i++)
    {
        for(my $j=1;$j<=$np;$j++)
        {
            if($j*$i == $np)
            {
                push (@$p,$i);
                 push (@$q,$j);
            }
        }
    }
}

sub Generate_HPL_DAT
{
	my ($Ns,$p,$q,$hpl)=@_;

	my $Nb=128;

	open HPL,">$hpl" or die "$!";
	print HPL  "HPLinpack benchmark input file\n" ;
	print HPL  "Innovative Computing Laboratory, University of Tennessee\n";
	print HPL  "HPL.out      output file name (if any)\n";
	print HPL  "6            device out (6=stdout,7=stderr,file)\n";
	print HPL  "1            # of problems sizes (N)\n";
	print HPL "$Ns  Ns\n";
	print HPL  "1            # of NBs\n";
	print HPL "$Nb      NBs\n";
	print HPL "0            PMAP process mapping (0=Row-,1=Column-major)\n";
	my $size=@$p;
	print HPL "$size            # of process grids (P x Q)\n";
	print HPL "@$p        Ps\n";
	print HPL "@$q        Qs\n";
	print HPL "16.0         threshold\n";
	print HPL  "3            # of panel fact\n";
	print HPL "0 1 2        PFACTs (0=left, 1=Crout, 2=Right)\n";
	print HPL "2            # of recursive stopping criterium\n";
	print HPL "2 4          NBMINs (>= 1)\n";
	print HPL "1            # of panels in recursion\n";
	print HPL "2            NDIVs\n";
	print HPL "3            # of recursive panel fact.\n";
	print HPL "0 1 2        RFACTs (0=left, 1=Crout, 2=Right)\n";
	print HPL "1            # of broadcast\n";
	print HPL "0            BCASTs (0=1rg,1=1rM,2=2rg,3=2rM,4=Lng,5=LnM)\n";
	print HPL "1            # of lookahead depth\n";
	print HPL "0            DEPTHs (>=0)\n";
	print HPL "2            SWAP (0=bin-exch,1=long,2=mix)\n";
	print HPL "64           swapping threshold\n";
	print HPL "0            L1 in (0=transposed,1=no-transposed) form\n";
	print HPL "0            U  in (0=transposed,1=no-transposed) form\n";
	print HPL "1            Equilibration (0=no,1=yes)\n" ;
	print HPL "8            memory alignment in double (> 0)\n";
	close HPL;
	return $hpl;
}

sub usage{
	my $myname = `basename $0`;
	chomp($myname);
    my $help = "Usage: $myname [-l] <-h host1,host2,host3> <-t /path/to/HPL.dat>

		where
			-l 					- generate HPL.dat with big sized problem definiton
			-h host1,host2,...	- Generate HPL config for specified hosts

			-np <int>			- Generate HPL config for specified NP and MEM
			-m <m>
			-t <filename>		- output /path/to/HPL.dat

	";
	die "$help\n";

}

##############################################################
my $hosts;
my $dat_file = "/tmp/HPL.dat";
my $opt_long;
my $opt_np;
my $opt_mem;

GetOptions( 
	'l' => \$opt_long, 
	'h|hosts=s' => \$hosts,
	'target|t=s' =>\$dat_file,
	'np=i' => \$opt_np,
	'm=i' => \$opt_mem,
) or die "Incorrect usage!\n";

usage() if (not (defined $hosts or defined ($opt_mem and $opt_np)));




my (@cpuinfo,@meminfo);

if ( $opt_mem and $opt_np ) {
	push @cpuinfo, $opt_np;
	push @meminfo, $opt_mem;
} else {
	my @arr_hosts=split(/\,/,$hosts);
	Collect_Hosts_Info(\@cpuinfo,\@meminfo,@arr_hosts);
}

my $np=0;
foreach my $cpu (@cpuinfo) {
	$np+=$cpu;
}
print ("meminfo=@meminfo\n");
print ("cpuinfo=@cpuinfo\n");



my $ram_per_core=($meminfo[0]/($cpuinfo[0]*1000000));
if($ram_per_core >= 0.9) {
    $ram_per_core=1;
}



my $ns=int(sqrt(0.8*$ram_per_core*1024*1024*1024*$np/8));

my (@p,@q);
if ( $opt_long ) {
	Calc_NP(\@p,\@q,$np);
} else {
	Calc_Np_Short(\@p,\@q,$np);
}
print ("ram_per_core=$ram_per_core\n");
print ("NP=$np,NS=$ns.P=@p,Q=@q\n");

Generate_HPL_DAT($ns,\@p,\@q,$dat_file);

print ("dat file : $dat_file\n");
