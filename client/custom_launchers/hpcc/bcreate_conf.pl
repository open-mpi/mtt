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
    foreach my $host (@hosts){
    my $tmp_cpu_info=`ssh $host \"cat /proc/cpuinfo\" | egrep \'processor\\s*:\' |wc -l`;
    chomp $tmp_cpu_info;
    push (@$r_cpu,$tmp_cpu_info);
    my $tmp_mem_info=`ssh $host \"cat /proc/meminfo  |grep MemTotal\"`;
    chomp $tmp_mem_info;
    if($tmp_mem_info=~/(\d+)/){
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
	my ($Ns,$Nb, $p,$q,$hpl,$hpcc)=@_;


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
	if ($hpcc){
	    print HPL "##### This line (no. 32) is ignored (it serves as a separator). ######\n";
	    print HPL "0                               Number of additional problem sizes for PTRANS\n";
	    print HPL "1200 10000 30000                values of N\n";
	    print HPL "0                               number of additional blocking sizes for PTRANS\n";
	    print HPL "40 9 8 13 13 20 16 32 64        values of NB\n";
	}
	close HPL;
	return $hpl;
}

sub usage{
	my $myname = `basename $0`;
	chomp($myname);
    my $help = "Usage: $myname [-p <int>] [-q <int] [-np <int>] [-ns <int>] [-nb <int>] [-l] <-h host1,host2,host3> <-t /path/to/HPL.dat>

		where
			-l - generate HPL.dat with big sized problem definiton

	";
	die "$help\n";

}

##############################################################
my $hosts;
my $dat_file = "/tmp/HPL.dat";
my $opt_long;

my $opt_hpcc;
my $opt_nb=128;
my $opt_ns;
my $opt_np;
my $opt_p;
my $opt_q;
my $opt_help;

GetOptions( 
	'l' => \$opt_long, 
	'h|hosts=s' => \$hosts,
	'target|t=s' =>\$dat_file, 
	'hpcc' => \$opt_hpcc,
	'nb=i', => \$opt_nb,
	'ns=i', => \$opt_ns,
	'np=i', => \$opt_np,
	'p=i', => \$opt_p,
	'q=i', => \$opt_q,
	'help', => \$opt_help,
) or die "Incorrect usage!\n";

usage() if $opt_help;

my $np=0;
my $ns;

if ( $opt_ns and $opt_np ) {
	$np = $opt_np;
	$ns = $opt_ns;

} elsif ( defined $hosts ) {

	my @arr_hosts=split(/\,/,$hosts);
	my (@cpuinfo,@meminfo);

	Collect_Hosts_Info(\@cpuinfo,\@meminfo,@arr_hosts);
	print ("meminfo=@meminfo\n");
	print ("cpuinfo=@cpuinfo\n");
	foreach my $cpu (@cpuinfo) {
		$np+=$cpu;
	}
	my $ram_per_core=($meminfo[0]/($cpuinfo[0]*1000000));
	if($ram_per_core >= 0.9) {
		$ram_per_core=1;
	}

	$ns=int(sqrt(0.8*$ram_per_core*1024*1024*1024*$np/8));
	print ("ram_per_core=$ram_per_core\n");
}


my (@p,@q);
if ( not defined $opt_p and not defined $opt_q ) {
	if ( $opt_long ) {
		Calc_NP(\@p,\@q,$np);
	} else {
		Calc_Np_Short(\@p,\@q,$np);
	}
} else {
	push @p, $opt_p;
	push @q, $opt_q;
}

print ("NP=$np, NS=$ns, P=@p, Q=@q\n");

Generate_HPL_DAT($ns,$opt_nb,\@p,\@q,$dat_file,$opt_hpcc);

print ("dat file : $dat_file\n");
