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

my $hosts;
my $dat_file = "/tmp/HPL.dat";
my $opt_long;

my $opt_hpcc;
my $opt_nb=128;
my $opt_ns;
my $opt_np;
my $opt_p;
my $opt_q;
my $opt_pfacts = "0 1 2";
my $opt_rfacts = "0 1 2";
my $opt_nbmins = "2 4";
my $opt_ndiv   = "2";
my $opt_help;
my $opt_bcast = "0";
my $opt_depth = "0";
# for hpcc
my $opt_p_problem_sizes = "0";
my $opt_p_vals_of_n = "1200 10000 30000";
my $opt_p_blocking_sizes = "0";
my $opt_p_values_of_nb = "40 9 8 13 13 20 16 32 64";

GetOptions( 
	'help', => \$opt_help,
	'l' => \$opt_long, 
	'h|hosts=s' => \$hosts,
	'target|t=s' =>\$dat_file, 
	'hpcc' => \$opt_hpcc,
	'nb=i', => \$opt_nb,
	'ns=i', => \$opt_ns,
	'np=i', => \$opt_np,
	'p=i', => \$opt_p,
	'q=i', => \$opt_q,
	'pfacts=s' => \$opt_pfacts,
	'rfacts=s' => \$opt_rfacts,
	'bcast=s' => \$opt_bcast,
	'depth=s' => \$opt_depth,
	'nbmins=s' => \$opt_nbmins,
	'ndiv=s' => \$opt_ndiv,
	'p_ps=s' => \$opt_p_problem_sizes,
	'p_pvon=s' => \$opt_p_vals_of_n,
	'p_bs=s' => \$opt_p_blocking_sizes,
	'p_vonb=s' => \$opt_p_values_of_nb,
) or die "Incorrect usage!\n";


usage() if $opt_help;

my $np = $opt_np? $opt_np : undef;
my $ns = $opt_ns? $opt_ns : undef;

if ( defined $hosts ) {

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
if ( $np and not defined $opt_p and not defined $opt_q ) {
	if ( $opt_long ) {
		Calc_NP(\@p,\@q,$np);
	} else {
		Calc_Np_Short(\@p,\@q,$np);
	}
} elsif ( defined $opt_p and defined $opt_q) {
	push @p, $opt_p;
	push @q, $opt_q;
} else {
	usage();
}

print ("NS=$ns, P=@p, Q=@q\n");

Generate_HPL_DAT($ns,$opt_nb,\@p,\@q,$dat_file,$opt_hpcc);

print ("dat file : $dat_file\n");

##############################################################


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

	$opt_pfacts = "1";
	$opt_rfacts = "2";
	$opt_nbmins = "4";
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

sub count_items
{
	my ($str) = @_;
	my @items = split(" ",$str);
	return $#items + 1;
}

sub Generate_HPL_DAT
{
	my ($Ns,$Nb, $p,$q,$hpl,$hpcc)=@_;

	my $nPfacts = count_items($opt_pfacts);
	my $nRfacts = count_items($opt_rfacts);
	my $nBcast  = count_items($opt_bcast);
	my $nDepth  = count_items($opt_depth);
	my $nNbmins = count_items($opt_nbmins);
	my $nNb     = count_items($Nb);
	my $nNs     = count_items($Ns);
	my $nNdiv   = count_items($opt_ndiv);

	open HPL,">$hpl" or die "$!";
	print HPL  "HPLinpack benchmark input file\n" ;
	print HPL  "Innovative Computing Laboratory, University of Tennessee\n";
	print HPL  "HPL.out      output file name (if any)\n";
	print HPL  "6            device out (6=stdout,7=stderr,file)\n";
	print HPL  "$nNs            # of problems sizes (N)\n";
	print HPL "$Ns  Ns\n";
	print HPL  "$nNb            # of NBs\n";
	print HPL "$Nb      NBs\n";
	print HPL "0            PMAP process mapping (0=Row-,1=Column-major)\n";
	my $size=@$p;
	print HPL "$size            # of process grids (P x Q)\n";
	print HPL "@$p        Ps\n";
	print HPL "@$q        Qs\n";
	print HPL "16.0         threshold\n";
	print HPL "$nPfacts            # of panel fact\n";
	print HPL "$opt_pfacts        PFACTs (0=left, 1=Crout, 2=Right)\n";
	print HPL "$nNbmins            # of recursive stopping criterium\n";
	print HPL "$opt_nbmins          NBMINs (>= 1)\n";
	print HPL "$nNdiv            # of panels in recursion\n";
	print HPL "$opt_ndiv            NDIVs\n";
	print HPL "$nRfacts            # of recursive panel fact.\n";
	print HPL "$opt_rfacts        RFACTs (0=left, 1=Crout, 2=Right)\n";
	print HPL "$nBcast            # of broadcast\n";
	print HPL "$opt_bcast            BCASTs (0=1rg,1=1rM,2=2rg,3=2rM,4=Lng,5=LnM)\n";
	print HPL "$nDepth            # of lookahead depth\n";
	print HPL "$opt_depth            DEPTHs (>=0)\n";
	print HPL "2            SWAP (0=bin-exch,1=long,2=mix)\n";
	print HPL "64           swapping threshold\n";
	print HPL "0            L1 in (0=transposed,1=no-transposed) form\n";
	print HPL "0            U  in (0=transposed,1=no-transposed) form\n";
	print HPL "1            Equilibration (0=no,1=yes)\n" ;
    print HPL "8            memory alignment in double (> 0)\n";


	if ($hpcc){
	    print HPL "##### This line (no. 32) is ignored (it serves as a separator). ######\n";
	    print HPL "$opt_p_problem_sizes                                Number of additional problem sizes for PTRANS\n";
	    print HPL "$opt_p_vals_of_n                                    values of N\n";
	    print HPL "$opt_p_blocking_sizes                               number of additional blocking sizes for PTRANS\n";
	    print HPL "$opt_p_values_of_nb                                 values of NB\n";
	}
	close HPL;
	return $hpl;
}

sub usage{
	my $myname = `basename $0`;
	chomp($myname);

    my $help = "Usage: $myname <options>
	
	
	Where options are:
	
	The following params are available to configure Linpack (HPL)
	[-p <int>] 
	[-q <int] 
	[-np <int>] 
	[-ns <int>] 
	[-nb <int>] 
	[-pfacts <str>] 
	[-rfacts <str>] 
	[-depth <str>] 
	[-nbmins <str>] 
	[-ndiv <str>] 


	The following params are available in HPCC only:
	[-p_ps <string>]
	[-p_pvon <string>]
	[-p_bs <string>]
	[-p_vonb <string]


	General parameters:
	[-hpcc]                         - Generate HPCC configuration file
	[-l]                            - Generate long running HPL.dat
	<-h host1,host2,host3>          - Use specified nodes to gather cpu/mem info and calc HPL.dat
	<-t /path/to/result/file.dat>   - Path to resulting file

	";
	die "$help\n";

}

##############################################################
