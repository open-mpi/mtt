#!/usr/bin/perl
#
# Copyright (c) 2009 Voltaire
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

use Getopt::Long;
use File::Glob ':globally';
use File::Basename;
use File::Spec;
use File::Path;


use strict;

my $opt_help=0;

my $workdir=undef;

my $mpiroot=undef;
my $mpiopt="";

my $opt_hosts=undef;
my $opt_np=undef;

my $opt_ic="ib";
my $opt_mpi="openmpi,hp";
my $opt_prof=undef;
my $opt_n=0;
my $opt_desc="";
my $opt_bench=undef;
my $opt_mem_per_cpu=0;
my $opt_v = 0;
my $opt_scale_one_by_one=0;
my $opt_rf;

my $mydir = dirname($0);
my $benchs = "eddy_417k,turbo_500k,aircraft_2m,sedan_4m,truck_14m,truck_poly_14m,truck_111m";

my $fluent_path=undef; # "/hpc/home/inst/local/x86_64/commercial/fluent/Fluent.Inc";
                       # or "/hpc/home/inst/local/x86_64/commercial/fluent/beta/ansys_inc/v120/fluent";

my @ARGV_SAVED=@ARGV;

GetOptions ("help|h"=>\$opt_help,
    "workdir=s" => \$workdir,
    "mpiroot=s" => \$mpiroot,
    "mpiopt=s"=>\$mpiopt,
    "hosts=s" => \$opt_hosts,
    "np=s"=>\$opt_np,

    "fluentpath=s"=>\$fluent_path,

    "job|j=s"=>\$opt_bench,

    "mpi|m=s"=>\$opt_mpi,

    "rf=s" => \$opt_rf,
    "v"=>\$opt_v,
    "mempercpu=i" =>\$opt_mem_per_cpu, 
    "ic|i=s"=>\$opt_ic, "prof"=>\$opt_prof, "desc=s"=>\$opt_desc,
    "x"=>\$opt_n,
);

$workdir = $mydir . "/runs" if (not defined $workdir);
$workdir = File::Spec->rel2abs( $workdir );

if ( ! $opt_n ) {
	mkpath $workdir;
	open(F, ">$workdir/vbench.log") or die "Error: Unable to create vbench.log $!\n";
	print F join(" ", @ARGV_SAVED);
	close F;
}

usage() if ($opt_help);
error("No work directory provided") if (not defined($workdir));
error("No workdirectory exists") if (not -d $workdir);

error("No hosts provided") if (not defined($opt_hosts));
error("No np provided") if (not defined($opt_np));
error("No mpiroot provided") if (not defined($mpiroot));

error("No fluent path provided") if (not defined($fluent_path));
error("No fluent directory exists: $fluent_path") if (not -d $fluent_path);

error("No job provided")  if (not defined($opt_bench));

if ( $mpiroot or ($opt_mpi =~ "openmpi")) {
	$ENV{'OPENMPI_ROOT'} = $mpiroot;
	print "using OPENMPI_ROOT=$mpiroot\n" if $opt_v;
}

if ($mpiopt) {
	$ENV{'FS_MPIRUN_FLAGS'} = $mpiopt;
	$ENV{'OPENMPI_CUSTOM_FLAGS'} = "yes";
	print "using FS_MPIRUN_FLAGS=$mpiopt\n" if $opt_v;
}

my %bench_req;
$bench_req{'eddy_417k'} 	= 1;
$bench_req{'turbo_500k'} 	= 1;
$bench_req{'aircraft_2m'} 	= 2;
$bench_req{'sedan_4m'} 		= 5;
$bench_req{'truck_14m'} 	= 16;
$bench_req{'truck_poly_14m'}= 16;
$bench_req{'truck_111m'} 	= 32;

my %runenv;

my $fluent_exe;
$fluent_exe = "$fluent_path/bin/fluentbench.pl";
error("Can't find fluent executable: $fluent_exe") if ( not -x $fluent_exe );
$ENV{'PATH'} = "$fluent_path/bin:$ENV{'PATH'}";

my @hosts = select_hosts($opt_hosts);
my $nhosts= $#hosts + 1;
print "ncpus=$nhosts hosts=[", join(",",@hosts),"]\n";

my @all_benchs = split(/,/, $opt_bench);
my @all_mpi = split(/,/, $opt_mpi);
my $cmd_opt;
foreach my $m (@all_mpi) {
    foreach my $b (@all_benchs) {
        my @scaling =  create_scale($opt_np, $nhosts, $b);
        @scaling = join(" ", @scaling) if ( ! $opt_scale_one_by_one );
        foreach my $s (@scaling) {
            my $rundir = create_rundir($workdir);
            print "Run directory: " . $rundir . "\n";
            my $runlog_filename = $rundir . "/output.log";
            $cmd_opt = "$fluent_exe ";
            $cmd_opt .= " $b";
            $cmd_opt .= " $s";
            $cmd_opt .= " -cnf=" . create_fluent_hosts($rundir, @hosts);
            $cmd_opt .= " -ssh";
            $cmd_opt .= " -p$opt_ic" if (defined $opt_ic);
            $cmd_opt .= " -mpi=$m";
            if ( $m eq "hp"  && $opt_prof) {
                 $cmd_opt = "env HPMPI_MPIRUN_FLAGS='-i profile_info:l' " . $cmd_opt;
            }
            #$cmd_opt .= " -mpiopt='$mpiopt' " if (defined $mpiopt);
            $cmd_opt .= " &>$runlog_filename";
            $cmd_opt .= " < /dev/null";

            print "$cmd_opt\n";
			
            # uncomment to simulate Fluent execution
            # system ("cp -r " . dirname($0) . "/rundir-01/* $rundir/");
            # next;   

            if (!$opt_n) {
                save_params($rundir, $b, $m);
                chdir($rundir);
                my $rc = system($cmd_opt);
                if ( $rc != 0 ) {
                    if ($rc & 127) {
                        die "Fluent script exit with signal " . ($rc & 127) . ". Exit...";
                    } else {
                        my $reason = `tail -3 $runlog_filename`;
                        die "Failure. Can't run a command. Exit... rc=$rc reason=$reason\n";
                    }
                }
            }
        }
    }
}

sub get_ncpus
{
	my ($h) = @_;
	my $ncpus = `ssh $h cat /proc/cpuinfo |grep proc|wc -l`;
	chomp($ncpus);
	$ncpus;
}

sub get_nmem_gb
{
	my ($h) = @_;
	my $nmem = `ssh $h cat /proc/meminfo |grep -i memtotal|awk '{print \$2}'`;
	my $nmem_mb = $nmem / 1024;
	if ($nmem % 1024) {
		$nmem_mb = $nmem_mb + 1024;
	}

	int($nmem_mb/1024);
}
sub save_params
{
	my ($dir, $b, $m) = @_;
	my $fname="$dir/flbench.params";
	open(F, ">$fname") or die("Unable to open $fname\n");
	print F "cmd=$cmd_opt\n";
	print F "ic=$opt_ic\n";
	print F "mpi=$m\n";
	print F "bench=$b\n";
	print F "hosts=".join(",",@hosts)."\n";
	print F "scale=$opt_np\n";
	print F "desc=$opt_desc\n";
	print F "mpi_opt=$mpiopt\n";
	if ( $m =~ /openmpi/ ) {
		print F "ompi_root=$mpiroot\n";
	}
	close F;
}

sub create_rundir
{
	my ($d) = @_;
	mkpath $d if ( ! -d $d);
	opendir(DIR,$d) || die("Cannot open directory $d, $!\n");
	my @files = readdir(DIR);
	closedir(DIR);

	my $max_id = 0;
	foreach my $file (@files) {
		next if ($file eq "." || $file eq "..");
		next if (! -d "$d/$file");
		next if ($file !~ /rundir-(\d+)/);
		$max_id = $1 if ($max_id < $1);
	}
	$max_id++;
	if (length($max_id) == 1) {
		$max_id = "0" . $max_id;
	}
	
	my $rundir = $d . "/rundir-".$max_id;
	mkpath $rundir if ! $opt_n;
	$rundir;
}

sub rf_2_hf
{
	my ($refHosts, $rf) = @_;

	my (@res, %rf2hf, %tmpls, %machines);
	open(RF, $rf) or die "Error: Unable to open rankfile $rf, $!\n";
	while (<RF>) {
		my $line = $_;
		if ( $line =~ /rank (\d+)=([^ ]+) .*/ ) {
			print "Rank=$1 Host=$2\n" if $opt_v;
			$rf2hf{$1} = $2;
		}
	}
	close RF;
	foreach my $m (@{$refHosts}) {
		$machines{$m}++;
	}
	my $i = 0;
	foreach my $m (keys %machines) {
		my $t = "+n" . $i++;
		$tmpls{$t} = $m;
		print "$t = $m\n" if $opt_v;
	}

	foreach my $r (sort {$a <=> $b} keys %rf2hf) {
		my $t       = $rf2hf{$r};
		my $host    = $tmpls{$t};
		print "$r $host\n" if $opt_v;
		push @res, $host;
	}
	@res;
}

sub create_fluent_hosts
{
	my ($dir, @hosts) = @_;
	my $hostfile="$dir/fluent.hosts";
	if (! $opt_n) {
		open(F, ">$hostfile") or die("Unable to open $hostfile\n");
		if ( $opt_rf and -f $opt_rf ) {
			print "Rearranging machinefile according to the provided rankfile: $opt_rf\n";
			my @rfHosts = rf_2_hf(\@hosts, $opt_rf);
			foreach my $h (@rfHosts) {
				print F $h,"\n";
			}
		} else {
			foreach my $h (@hosts) {
				print F $h,"\n";
			}
		}
		close F;
	}
	$hostfile;
}

sub check_scale
{
	my ($nprocs, $b) = @_;
	my $req_mem = $bench_req{$b};
	my $total_mem = 0;
	my %hosts_inuse;
	foreach my $h (@hosts) {
		$hosts_inuse{$h}++;
	}
	my $i = 0;
	foreach my $h (@hosts) {
		if ($i < $nprocs) {
			my $c = $hosts_inuse{$h};
			my $m = $runenv{$h};
			$total_mem += int($m/$c);
		}
		$i++;
	}

	my $ok = 1;
	if ($total_mem) {
		if ( $req_mem > $total_mem ) {
			print "Error: job memory ($total_mem) is less then required memory ($req_mem) for $b nproc=$nprocs\n";
			$ok = 0;
		} else {
			print "Info: job memory ($total_mem), required memory ($req_mem) for $b nproc=$nprocs\n" if $opt_v;
		}
	} else {
		print "Warn: not checking required memory for $b nproc=$nprocs\n";
	}
	$ok;
}

sub create_scale
{
	my ($scale, $max_ncpus, $b) = @_;

	my @s;
	if ($scale =~ /:/) {
		my @tokens = split(/:/, $scale);
		my $ntokens = $#tokens + 1;
		my ($base, $step,$times) = (undef, undef, 1);
		if ($ntokens == 2) {
			$base = $tokens[0];
			$step = $tokens[1];
			$times = (($max_ncpus - $base)/$step) + 1;
		} elsif ($ntokens == 3) {
			$base = $tokens[0];
			$step = $tokens[1];
			$times = $tokens[2];
		}

		for (;$base<=$max_ncpus and $times--; $base+=$step) {
			push(@s, $base);
		}
		if ($times and $base > $max_ncpus) {
			push(@s, $max_ncpus);
		}
	} else {
		@s = split(/,/,$scale);
	}
	my @l;
	foreach my $item (@s) {
		if (check_scale($item, $b)) {
			push @l, "-t$item";
		}
	}
	@l;
}

sub select_hosts
{
	my ($host_list) = @_;
	my @hosts = split(/,/,$host_list);

	my @expanded_hosts = ();
	for (my $x=0; $x < $#hosts + 1; $x++) {
		my $h = $hosts[$x];
		$h=~s/[\[\]]//g;
		if ($h =~ /^([^\d]+)(\d+)-(\d+)(:\d+)?$/) {
			my $n = $1;
			for (my $i=$2; $i<=$3;$i++) {
				my $ntimes = $4;
				my $one_host = $n.$i;
				$ntimes =~ s/://g;
				if (length($ntimes)<= 0) {
					$ntimes = get_ncpus($one_host);
				}

				my $mem_gb = get_nmem_gb($one_host);
				$runenv{$one_host} = $mem_gb;

				if ($opt_mem_per_cpu) {
					my $ntimes_mem = int($mem_gb/$opt_mem_per_cpu);
					if ($ntimes_mem < $ntimes) {
						print "Adjusting $one_host ncpus from $ntimes to $ntimes_mem (totalMem=$mem_gb GB, memPerCpu=$opt_mem_per_cpu GB)\n" if $opt_n && $opt_v;
						$ntimes = $ntimes_mem;
					} else {
						print "$one_host ncpus=$ntimes (totalMem=$mem_gb GB, memPerCpu=$opt_mem_per_cpu GB)\n" if $opt_n && $opt_v;
					}
				} 

				while ($ntimes>0) {
					#print "X $n$i\n";
					push @expanded_hosts, $n.$i;
					$ntimes--;
				}
			}
		} elsif ($h =~ /^([^:]+):(\d+)$/) {
			my $n = $1;
			my $ntimes = $2;
			while ($ntimes>0) {
				#print "X $n$i\n";
				push @expanded_hosts, $n;
				$ntimes--;
			}
		} elsif ($h =~ /^(\w+)$/ ) {
			my $n = $1;
			my $ntimes = get_ncpus($n);
			while ($ntimes>0) {
				#print "X $n$i\n";
				push @expanded_hosts, $n;
				$ntimes--;
			}
		} else {
			push @expanded_hosts, $h;
		}
	}
	@expanded_hosts;
}


sub error
{
	my ($err) = @_;
	print "Error: $err\n";
	usage();
}
sub usage
{
    my $myname = basename($0);
    my $usage = "
    
    $myname <options>

    where options are:

    -hosts      <host[,host,...]>   - list of nodes to run fluent job, 
    -ic|c       <ib>                - Interconnect type  (default: $opt_ic)
    -mpi|m      hp|openmpi          - MPI vendor to use (default $opt_mpi)
    -prof                           - Use profiling
    -workdir    path                - use specified directory to keep results
                                     (default: $workdir)
    -job|j      bench_name          - name of benchmark 
                                     (default: $benchs)
    -mempercpu number               - specify memory in GB per cpu
    -x                              - dry run
    -np         <n1[,n2,...]|base:step|base:step:times> - ncpus to use
    -desc       string              - associate description with this execution
    -mpiroot   string              - root to alternate ompi path
    -s1                             - scale all jobs one by one
    -rf         path                - rearrange hostfile according to rankfile
    
    -fluent_path path to fluent

    \n
    ";
    die "$usage\n";
}
