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

my $dummy_user=undef;

my $mpiroot=undef;
my $mpiopt=undef;
my $opt_hosts=undef;
my $opt_np=undef;

my $opt_exec=undef;
my $casedir=undef;

my $solver_params=undef;

my $opt_autodecompose=undef;
my $decomposefile=undef;
my $opt_silent=0;
my $opt_verbose=0;
my $opt_scratchdir=undef;
my $opt_workdir=undef;
my $opt_prepare=undef;
my $opt_run=undef;
my $opt_output_file=undef;


my @ARGV_SAVED=@ARGV;

GetOptions (
	"user=s" => \$dummy_user,
	"scratchdir=s" => \$opt_scratchdir,
	"workdir=s" => \$opt_workdir,
	"hosts=s" => \$opt_hosts,
	"np=i" => \$opt_np,
	"mpiroot=s" => \$mpiroot,
	"mpiopt=s"=>\$mpiopt,
	"exec|e|solver=s"=>\$opt_exec, 
	"case|c|casedir=s"=>\$casedir,
	"params=s"=>\$solver_params,
	"decomposefile=s"=>\$decomposefile,
	"silent|q"=>\$opt_silent,
	"autodecompose"=>\$opt_autodecompose,
	"verbose|v"=>\$opt_verbose,
	"prepare|p"=>\$opt_prepare,
	"run|r"=>\$opt_run,
	"out|f=s"=>\$opt_output_file,
	"help|h"=>\$opt_help, 
);

usage() if ($opt_help);

$opt_prepare = undef if ( $opt_run );
usage("No mpiroot provided") if (not defined($mpiroot));
usage("No openfoamuser provided") if (not defined($dummy_user));

if ( $opt_prepare ) {
	prepare_openfoam_env();
} else {
	usage("No hosts provided") if (not defined($opt_hosts));
	usage("No np provided") if (not defined($opt_np));
	usage("No solver provided") if (not defined($opt_exec));
	usage("No casedir provided: $casedir") if (not defined($casedir) or ( ! -d $casedir));
	run_openfoam();
}
exit 0;

sub prepare_openfoam_env
{
	print "Preparing OpenFoam run\n";
	my $mpihome_file="~$dummy_user/.openfoam_mpihome";
	my $workdir="$opt_scratchdir/$$";
	my $temp_script_name = "$workdir/openfoam_run.sh";

	runcmd("sudo rm -f $mpihome_file");
	runcmd("sudo -u $dummy_user bash -c 'echo $mpiroot > $mpihome_file'");

	runcmd("mkdir -p $workdir");
	runcmd("chmod a+rwx $workdir");

	open(TEMP_SCRIPT, ">$temp_script_name") or die "Error: Unable to create temp script";
	my $new_args = join(" ", @ARGV_SAVED,"-run -workdir $workdir");
	print TEMP_SCRIPT "$0 $new_args\n";
	close TEMP_SCRIPT;
	runcmd("sudo su - $dummy_user < $temp_script_name");
}

sub run_openfoam
{
	print "Running OpenFoam \n";
	use Env qw($FOAM_APPBIN);
	my $foam_appbin=$FOAM_APPBIN;
	print "EXEC: $opt_exec\n";
	print "CASE: " . basename($casedir) . "\n";


	my $case = basename($casedir);
	opendir(CASED, $casedir) || die("Cannot open directory: $casedir");
	my @thefiles= readdir(CASED);
	closedir(CASED);

	my $processorN = 0;
	foreach my $file (@thefiles) {
		next if (($file eq ".") || ($file eq "..") );
		if ($file =~ m/^processor\d+$/) {
			$processorN++;
			next;
		}
	}

	if ( $opt_autodecompose ) {
		$decomposefile = "system/decomposeParDict_$opt_np";
	}

	die("Error: No decompose file found: $casedir/$decomposefile") if (not -e "$casedir/$decomposefile");
	if ( $processorN == $opt_np ) {
		print "case $case already contains decomposition folders for $opt_np procs\n";
	} else {
		runcmd("cp $casedir/$decomposefile $casedir/system/decomposeParDict");
		runcmd("rm -rf  $casedir/processor*");
		runcmd("decomposePar -case $casedir");
	}

	my $cmd_opt = "$mpiroot/bin/mpirun";
	$cmd_opt .= " -H $opt_hosts";
	$cmd_opt .= " -np $opt_np";
	$cmd_opt .= " $mpiopt" if (defined($mpiopt));
	$cmd_opt .= " $FOAM_APPBIN/$opt_exec";
	$cmd_opt .= " -case $casedir $solver_params";

	if ( $opt_silent and -d $opt_workdir) {
		$opt_output_file = "$opt_workdir/openfoam.log" if (not defined $opt_output_file);
		$cmd_opt .= " &>$opt_output_file";
		print "OUTPUT: $opt_output_file\n";
	}

	runcmd($cmd_opt);
	print_log_tail(100);
}

sub usage
{
	my ($err) = @_;
	print "Error: $err\n" if $err;

    my $myname = basename($0);
    my $usage = "
    
    $myname <options>

    where options are:

    -user       login name          - user name to start openfoam
    -hosts 	<host[,host,...]>   - list of host to run job, 
    -np         number              - used processes
    -exec|e|solver     string              - name of exec
                                     (default: $opt_exec)
    -case|c     path to casedir     - name of case (case dir)
    -mpiroot    string              - root to mpi path
    -params     string              - solver params
    -autodecompose                  - try autodecompose
    \n";
    die "$usage\n";
}

sub print_log_tail
{
	my ($lines) = @_;
	my $last_log_lines = "";
	if (defined $opt_output_file) {
		my $cmd = "tail -" . $lines . " $opt_output_file";
		$last_log_lines = "Last $lines log lines:\n...\n" . `$cmd`;
		print "$last_log_lines\n";
	}
}

sub runcmd
{
	my ($cmd) = @_;
	print "Running:\n$cmd\n" if ($opt_verbose);
	my $rc = system($cmd);
	if ($rc != 0) {
		print "Error: Failed to run command:\n$cmd\n rc: $rc\n";
		print_log_tail(100);
		exit(1);
	}
	$rc;
}
