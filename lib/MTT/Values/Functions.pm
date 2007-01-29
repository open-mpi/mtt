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

package MTT::Values::Functions;

use strict;
use File::Find;
use MTT::Messages;
use MTT::Globals;
use MTT::Files;
use Data::Dumper;

# Do NOT use MTT::Test::Run here, even though we use some
# MTT::Test::Run values below.  This will create a "use loop".  Be
# confident that we'll get the values as appropriate when we need them
# through other "use" statements.

#--------------------------------------------------------------------------

# Returns the result_stdout of running a shell command
sub shell {
    Debug("&shell: got @_\n");
    my $cmd = join(/ /, @_);
    open SHELL, "$cmd|";
    my $ret;
    while (<SHELL>) {
        $ret .= $_;
    }
    chomp($ret);
    Debug("&shell: returning $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Return the sum of all parameters
sub sum {
    Debug("&sum got: @_\n");

    return "0"
        if (!@_);

    my $sum = 0;
    foreach my $val (@_) {
        $sum += $val;
    }

    Debug("&sum returning: $sum\n");
    return $sum;
}

#--------------------------------------------------------------------------

# Return the product of all parameters
sub multiply {
    Debug("&multiply got: @_\n");

    return "0"
        if (!@_);

    my $prod = 1;
    foreach my $val (@_) {
        $prod *= $val;
    }

    Debug("&multiply returning: $prod\n");
    return $prod;
}

#--------------------------------------------------------------------------

# Return all the squares
sub squares {
    Debug("&squares got: @_\n");

    my ($min, $max) = @_;

    my @ret;
    my $val = $min;
    while ($val <= $max) {
        push(@ret, $val * $val);
        ++$val;
    }

    return \@ret;
}

#--------------------------------------------------------------------------

# Returns the log of a number in base N
sub log {
    Debug("&log got: @_\n");
    my ($base, $val) = @_;
    return log($val) / log($base);
}

#--------------------------------------------------------------------------

# Return all the powers of a given base from [base^min, base^max]
sub pow {
    Debug("&pow got: @_\n");

    my ($base, $min, $max) = @_;

    my @ret;
    my $val = $min;
    while ($val <= $max) {
        push(@ret, $base ** $val);
        ++$val;
    }

    return \@ret;
}

#--------------------------------------------------------------------------

# Return the minimum value of all parameters
sub min {
    Debug("&min got: @_\n");

    return "0"
        if (!@_);

    my $min = shift;
    foreach my $val (@_) {
        $min = $val
            if ($val < $min)
    }

    Debug("&min returning: $min\n");
    return $min;
}

#--------------------------------------------------------------------------

# Return the maximum value of all parameters
sub max {
    Debug("&max got: @_\n");

    return "0"
        if (!@_);

    my $max = shift;
    foreach my $val (@_) {
        $max = $val
            if ($val > $max)
    }

    Debug("&max returning: $max\n");
    return $max;
}

#--------------------------------------------------------------------------

# Return 1 if all the values are not equal, 0 otherwise.  If there are
# no arguments, return 1.
sub ne {
    Debug("&ne got: @_\n");

    return "1"
        if (!@_);

    my $first = shift;
    do {
        my $next = shift;
        if ($first eq $next) {
            Debug("&ne: returning 0\n");
            return "0";
        }
    } while (@_);
    Debug("&ne: returning 1\n");
    return "1";
}

#--------------------------------------------------------------------------

# Return 1 if the first argument is greater than the second
sub gt {
    Debug("&gt got: @_\n");

    return "0"
        if (!@_);

    my $a = shift;
    my $b = shift;

    if ($a > $b) {
        Debug("&gt: returning 1\n");
        return "1";
    } else {
        Debug("&gt: returning 0\n");
        return "0";
    }
}

#--------------------------------------------------------------------------

# Return 1 if the first argument is greater than or equal to the second
sub ge {
    Debug("&ge got: @_\n");

    return "0"
        if (!@_);

    my $a = shift;
    my $b = shift;

    if ($a >= $b) {
        Debug("&ge: returning 1\n");
        return "1";
    } else {
        Debug("&ge: returning 0\n");
        return "0";
    }
}

#--------------------------------------------------------------------------

# Return 1 if the first argument is less than the second
sub lt {
    Debug("&lt got: @_\n");

    return "0"
        if (!@_);

    my $a = shift;
    my $b = shift;

    if ($a < $b) {
        Debug("&lt: returning 1\n");
        return "1";
    } else {
        Debug("&lt: returning 0\n");
        return "0";
    }
}

#--------------------------------------------------------------------------

# Return 1 if the first argument is less than or equal to the second
sub le {
    Debug("&le got: @_\n");

    return "0"
        if (!@_);

    my $a = shift;
    my $b = shift;

    if ($a <= $b) {
        Debug("&le: returning 1\n");
        return "1";
    } else {
        Debug("&le: returning 0\n");
        return "0";
    }
}

#--------------------------------------------------------------------------

# Return 1 if all the values are equal, 0 otherwise.  If there are no
# arguments, return 1.
sub eq {
    Debug("&eq got: @_\n");

    return "1"
        if (!@_);

    my $first = shift;
    do {
        my $next = shift;
        if ($first ne $next) {
            Debug("&eq: returning 0\n");
            return "0";
        }
    } while (@_);
    Debug("&eq: returning 1\n");
    return "1";
}

#--------------------------------------------------------------------------

# Return 1 if all the values are true, 0 otherwise.  If there are no
# arguments, return 1.
sub and {
    Debug("&and got: @_\n");

    return "1"
        if (!@_);

    do {
        my $val = shift;
        if (!$val) {
            Debug("&and: returning 0\n");
            return "0";
        }
    } while (@_);
    Debug("&and: returning 1\n");
    return "1";
}

#--------------------------------------------------------------------------

# Return 1 if any of the values are true, 0 otherwise.  If there are no
# arguments, return 1.
sub or {
    Debug("&or got: @_\n");

    return "1"
        if (!@_);

    do {
        my $val = shift;
        if ($val) {
            Debug("&or: returning 1\n");
            return "1";
        }
    } while (@_);
    Debug("&or: returning 0\n");
    return "0";
}

#--------------------------------------------------------------------------

# If the first argument is true (nonzero), return the 2nd argument.
# Otherwise, return the 3rd argument.
sub if {
    Debug("&if got: @_\n");
    my $t = shift;
    my $a = shift;
    my $b = shift;

    if ($t) {
        Debug("&if returning $a\n");
        return $a;
    } else {
        Debug("&if returning $b\n");
        return $b;
    }
}

#--------------------------------------------------------------------------

# Return a reference to all the strings passed in as @_
sub enumerate {
    Debug("&enumerate got: @_\n");

    my @ret;
    foreach my $arg (@_) {
        push(@ret, $arg);
    }
    return \@ret;
}

#--------------------------------------------------------------------------

# Return a reference to all the strings passed in as @_
sub split {
    Debug("&split got: @_\n");
    my $str = shift;

    my @ret = split(/ /, $str);
    return \@ret;
}

#--------------------------------------------------------------------------

# Join all the strings passed into one string and return in
sub join {
    Debug("&join got: @_\n");
    my $str;
    while (@_) {
        $str .= shift;
    }
    Debug("&join returning: $str\n");
    return $str;
}

#--------------------------------------------------------------------------

# First argument is the lower bound, second argument is upper bound,
# third [optional] argument is the stride (is 1 if not specified).
# Return a reference to all values starting with $lower and <=$upper
# with the given $stride.  E.g., &step(3, 10, 2) returns 3, 5, 7, 9.
sub step {
    Debug("&step got: @_\n");

    my $lower = shift;
    my $upper = shift;
    my $step = shift;
    $step = 1
        if (!$step);

    my @ret;
    while ($lower <= $upper) {
        push(@ret, "$lower");
        $lower += $step;
    }
    return \@ret;
}

#--------------------------------------------------------------------------

# Return the current np value from a running test.
sub test_np {
    Debug("&test_np returning: $MTT::Test::Run::test_np\n");

    return $MTT::Test::Run::test_np;
}

#--------------------------------------------------------------------------

# Return the current prefix value from a running test
sub test_prefix {
    Debug("&test_prefix returning: $MTT::Test::Run::test_prefix\n");

    return $MTT::Test::Run::test_prefix;
}

#--------------------------------------------------------------------------

# Return the current executable value from a running test
sub test_executable {
    Debug("&test_executable returning: $MTT::Test::Run::test_executable\n");

    return $MTT::Test::Run::test_executable;
}

#--------------------------------------------------------------------------

# Return the current argv (excluding $argv[0]) from a running test
sub test_argv {
    Debug("&test_params returning $MTT::Test::Run::test_argv\n");

    return $MTT::Test::Run::test_argv;
}

#--------------------------------------------------------------------------

# Return the exit exit_status from the last test run
# DEPRECATED
sub test_exit_status {
    Debug("&test_exit_status: this function is deprecated; please call test_wexitstatus()\n");
    return test_wexitstatus();
}

#--------------------------------------------------------------------------

# Return whether the last text run terminated normally
sub test_wifexited {
    my $ret = MTT::DoCommand::wifexited($MTT::Test::Run::test_exit_status);
    Debug("&test_wifexited returning: $ret\n");
    return $ret ? "1" : "0";
}

#--------------------------------------------------------------------------

# Return the exit status from the last test run
sub test_wexitstatus {
    my $ret = MTT::DoCommand::wexitstatus($MTT::Test::Run::test_exit_status);
    Debug("&test_wexitstatus returning $ret\n");
    return "$ret";
}

#--------------------------------------------------------------------------

# Return whether the last text run was terminated by a signal
sub test_wifsignaled {
    my $ret = MTT::DoCommand::wifsignaled($MTT::Test::Run::test_exit_status);
    Debug("&test_widsignaled returning: $ret\n");
    return $ret ? "1" : "0";
}

#--------------------------------------------------------------------------

# Return whether the last text run was terminated by a signal
sub test_wtermsig {
    my $ret = MTT::DoCommand::wtermsig($MTT::Test::Run::test_exit_status);
    Debug("&test_wtermsig returning: $ret\n");
    return "$ret";
}

#--------------------------------------------------------------------------

# Return a reference to an array of strings of the contents of a file
sub cat {
    Debug("&cat: @_\n");

    my @ret;
    foreach my $file (@_) {
        if (-f $file) {
            open(FILE, $file);
            while (<FILE>) {
                chomp;
                push(@ret, $_);
            }
            close(FILE);
        }
    }

    Debug("&cat returning: @ret\n");
    return \@ret;
}

#--------------------------------------------------------------------------

# Traverse a tree (or a bunch of trees) and return all the executables
# found
my @find_executables_data;
sub find_executables {
    Debug("&find_executables got @_\n");

    @find_executables_data = ();
    find(\&find_executables_sub, @_);

    Debug("&find_exectuables returning: @find_executables_data\n");
    return \@find_executables_data;
}

sub find_executables_sub {
    # Don't process directories and links, and don't recurse down
    # "special" directories
    if ( -l $_ ) { return; }
    if ( -d $_ ) { 
        if ((/\.svn/) || (/\.deps/) || (/\.libs/) || (/autom4te\.cache/)) {
            $File::Find::prune = 1;
        }
        return;
    }

    # $File::Find::name is the path relative to the starting point.
    # $_ contains the file's basename.  The code automatically changes
    # to the processed directory, so we want to examine $_.
    push(@find_executables_data, $File::Find::name)
        if (-x $_);
}

#--------------------------------------------------------------------------

# Deprecated name for env_max_procs
sub rm_max_procs {
    Warning("You are using a deprecated funclet name in your INI file: &rm_max_procs().  Please update to use the new functlet name: &env_max_procs().  This old name will disappear someday.\n");
    return env_max_procs();
}

#--------------------------------------------------------------------------

# Return the name of the run-time enviornment that we're using
sub env_name {
    Debug("&env_name\n");

    # Resource managers
    return "SLURM"
        if slurm_job();
    return "TM"
        if pbs_job();
    return "N1GE"
        if n1ge_job();
    return "loadleveler"
        if loadleveler_job();

    # Hostfile
    return "hostfile"
        if have_hostfile();

    # Hostlist
    return "hostlist"
        if have_hostlist();

    # No clue, Jack...
    return "unknown";
}

#--------------------------------------------------------------------------

# Find the max procs that we can run with.  Check several things in
# order:
#
# - Various resource managers
# - if a global hostfile was specified
# - if a global hostlist was specified
# - if a global max_np was specified
#
# If none of those things are found, return "2".
sub env_max_procs {
    Debug("&env_max_procs\n");

    # Resource managers
    return slurm_max_procs()
        if slurm_job();
    return pbs_max_procs()
        if pbs_job();
    return n1ge_max_procs()
        if n1ge_job();
    return loadleveler_max_procs()
        if loadleveler_job();

    # Hostfile
    return hostfile_max_procs()
        if have_hostfile();

    # Hostlist
    return hostlist_max_procs()
        if have_hostlist();

    # Manual specification of max_np
    return ini_max_procs()
        if have_ini_max_procs();

    # Not running under anything; just return 2.
    return "2";
}

#--------------------------------------------------------------------------

# Return "1" if we have a hostfile; "0" otherwise
sub have_hostfile {
    my $ret = (defined $MTT::Globals::Values->{hostfile}) ? "1" : "0";
    Debug("&have_hostfile returning $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# If we have a hostfile, return it.  Otherwise, return the empty string.
sub hostfile {
    Debug("&hostfile: $MTT::Globals::Values->{hostfile}\n");

    if (have_hostfile) {
        return $MTT::Globals::Values->{hostfile};
    } else {
        return "";
    }
}

#--------------------------------------------------------------------------

# If we have a hostfile, return its max procs count
sub hostfile_max_procs {
    Debug("&hostfile_max_procs\n");

    return "0"
        if (!have_hostfile());

    Debug("&hostfile_max_procs returning $MTT::Globals::Values->{hostfile_max_np}\n");
    return $MTT::Globals::Values->{hostfile_max_np};
}

#--------------------------------------------------------------------------

# Return "1" if we have a hostfile; "0" otherwise
sub have_hostlist {
    my $ret = (defined $MTT::Globals::Values->{hostlist}) ? "1" : "0";
    Debug("&have_hostlist: returning $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# If we have a hostlist, return it.  Otherwise, return the empty string.
sub hostlist {
    Debug("&hostlist: $MTT::Globals::Values->{hostlist}\n");

    if (have_hostlist) {
        return $MTT::Globals::Values->{hostlist};
    } else {
        return "";
    }
}

#--------------------------------------------------------------------------

# If we have a hostlist, return its max procs count
sub hostlist_max_procs {
    Debug("&hostlist_max_procs\n");

    return "0"
        if (!have_hostlist());

    Debug("&hostlist_max_procs returning $MTT::Globals::Values->{hostlist_max_np}\n");
    return $MTT::Globals::Values->{hostlist_max_np};
}

#--------------------------------------------------------------------------

# Return "1" if we have an "max_procs" setting in the globals in the
# INI file; "0" otherwise
sub have_ini_max_procs {
    Debug("&have_ini_max_procs\n");

    return (defined($MTT::Globals::Values->{max_np}) &&
            exists($MTT::Globals::Valeues->{max_np})) ? "1" : "0";
}

#--------------------------------------------------------------------------

# If we have a hostlist, return its max procs count
sub ini_max_procs {
    Debug("&ini_max_procs\n");

    return "0"
        if (!have_ini_max_procs());

    Debug("&ini_max_procs returning $MTT::Globals::Values->{max_np}\n");
    return $MTT::Globals::Values->{max_np};
}

#--------------------------------------------------------------------------

# Return "1" if we're running in a SLURM job; "0" otherwise.
sub slurm_job {
    Debug("&slurm_job\n");

    return ((exists($ENV{SLURM_JOBID}) &&
             exists($ENV{SLURM_TASKS_PER_NODE})) ? "1" : "0");
}

#--------------------------------------------------------------------------

# If in a SLURM job, return the max number of processes we can run.
# Otherwise, return 0.
sub slurm_max_procs {
    Debug("&slurm_max_procs\n");

    return "0"
        if (!slurm_job());

    # The SLURM env variable SLURM_TASKS_PER_NODE is a comma-delimited
    # list of strings.  Each string is of the form:
    # <tasks>[(x<nodes>)].  If the "(x<nodes>)" portion is not
    # specified, the <nodes> value is 1.

    my $max_procs = 0;
    my @tpn = split(/,/, $ENV{SLURM_TASKS_PER_NODE});
    my $tasks;
    my $nodes;
    foreach my $t (@tpn) {
        if ($t =~ m/(\d+)\(x(\d+)\)/) {
            $tasks = $1;
            $nodes = $2;
        } elsif ($t =~ m/(\d+)/) {
            $tasks = $1;
            $nodes = 1;
        }

        $max_procs += $tasks * $nodes;
    }

    Debug("&slurm_max_procs returning: $max_procs\n");
    return "$max_procs";
}

#--------------------------------------------------------------------------

# Return "1" if we're running in a PBS job; "0" otherwise.
sub pbs_job {
    Debug("&pbs_job\n");

    return ((exists($ENV{PBS_JOBID}) &&
             exists($ENV{PBS_ENVIRONMENT})) ? "1" : "0");
}

#--------------------------------------------------------------------------

# If in a PBS job, return the max number of processes we can run.
# Otherwise, return 0.
sub pbs_max_procs {
    Debug("&pbs_max_procs\n");

    return "0"
        if (!pbs_job());

    # Just count the number of lines in the $PBS_NODEFILE

    open (FILE, $ENV{PBS_NODEFILE}) || return "0";
    my $lines = 0;
    while (<FILE>) {
        ++$lines;
    }

    Debug("&pbs_max_procs returning: $lines\n");
    return "$lines";
}

#--------------------------------------------------------------------------

# Return "1" if we're running in a N1GE job; "0" otherwise.
sub n1ge_job {
    Debug("&n1ge_job\n");

    return (exists($ENV{JOBID}) ? "1" : "0");
}

#--------------------------------------------------------------------------

# If in a N1GE job, return the max number of processes we can run.
# Otherwise, return 0.
sub n1ge_max_procs {
    Debug("&n1ge_max_procs\n");

    return "0"
        if (!n1ge_job());

    # Just count the number of lines in the $PE_HOSTFILE

    open (FILE, $ENV{PE_HOSTFILE}) || return "0";
    my $lines = 0;
    while (<FILE>) {
        ++$lines;
    }

    Debug("&n1ge_max_procs returning: $lines\n");
    return "$lines";
}

#--------------------------------------------------------------------------

# Return "1" if we're running in a Load Leveler job; "0" otherwise.
sub loadleveler_job {
    Debug("&loadleveler_job\n");

    return (exists($ENV{LOADLBATCH}) ? "1" : "0");
}

#--------------------------------------------------------------------------

# If in a Load Leveler job, return the max number of processes we can
# run.  Otherwise, return 0.
sub loadleveler_max_procs {
    Debug("&loadleveler_max_procs\n");

    return "0"
        if (!loadleveler_job());

    # Just count the number of tokens in $LOADL_PROCESSOR_LIST

    my $ret = 2;
    if (exists($ENV{LOADL_PROCESSOR_LIST}) && 
	$ENV{LOADL_PROCESSOR_LIST} ne "") {
      my @hosts = split(/ /, $ENV{LOADL_PROCESSOR_LIST});
      $ret = $#hosts + 1;
    }

    Debug("&loadleveler_max_procs returning: $ret\n");
    return $ret;
}


#--------------------------------------------------------------------------

# Return the version of the GNU C compiler
sub get_gcc_version {
    Debug("&get_gcc_version\n");
    my $ret = "unknown";

    if (open GCC, "gcc --version|") {
        my $str = <GCC>;
        close(GCC);
        chomp($str);

        my @vals = split(" ", $str);
        $ret = $vals[2];
    }
    
    Debug("&get_gcc_version returning: $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Return the version of the Intel C compiler
sub get_icc_version {
    Debug("&get_icc_version\n");
    my $ret = "unknown";

    if (open ICC, "icc --version|") {
        my $str = <ICC>;
        close(ICC);
        chomp($str);

        my @vals = split(" ", $str);
        $ret = "$vals[2] $vals[3]";
    }
    
    Debug("&get_icc_version returning: $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Return the version of the PGI C compiler
sub get_pgcc_version {
    Debug("&get_pgcc_version\n");
    my $ret = "unknown";

    if (open PGCC, "pgcc -V|") {
        my $str = <PGCC>;
        $str = <PGCC>;
        close(PGCC);
        chomp($str);

        my @vals = split(" ", $str);
        $ret = "$vals[1] ($vals[2] $vals[5] $vals[6])";
    }
    
    Debug("&get_pgcc_version returning: $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Return the version of the Sun Studio C compiler
sub get_sun_cc_version {
    Debug("&get_sun_cc_version\n");
    my $ret = "unknown";

    if (open SUNCC, "cc -V 2>&1 | head -n 1 | cut -d\  -f4-") {
        my $str = <SUNCC>;
        $str = <SUNCC>;
        close(SUNCC);
        chomp($str);

        $ret = $str;
    }
    
    Debug("&get_sun_cc_version returning: $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Detect the bitness of the MPI library in this order:
#   1) User overridden (CSV of 1 or more valid bitnesses)
#   2) Small test C program (using void*)
#   3) /usr/bin/file command output
#
# Return a database-ready bitmapped value
sub get_mpi_install_bitness {
    Debug("&get_mpi_intall_bitness\n");

    my $override    = shift;
    my $install_dir = $MTT::MPI::Install::install_dir;
    my $force       = 1;
    my $ret         = "0";

    # 1)
    # Users can override the automatic bitness detection
    # (useful in cases where the MPI has multiple bitnesses
    # e.g., Sun packages or Mac OSX universal binaries)
    if ($override) {
        $ret = _bitness_to_bitmapped($override);
        Debug("&get_mpi_install_bitness returning: $ret\n");
        return $ret;
    }

    # 2)
    # Write out a simple C program to output the bitness
    my $prog_name  = "get_bitness_c";
    my $executable = "$install_dir/$prog_name";
    my $mpicc      = "$install_dir/bin/mpicc";
    my $mpirun     = "$install_dir/bin/mpirun";

    # Make sure we have a valid mpicc and mpirun before attempting
    # this
    if (-x $mpicc && -x $mpirun) {
        my $x = MTT::Files::SafeWrite($force, "$executable.c", "/*
 * This program is automatically generated via the \"get_bitness\"
 * function of the MPI Testing Tool (MTT).  Any changes you make here may
 * get lost!
 *
 * Copyrights and licenses of this file are the same as for the MTT.
 */

#include <stdio.h>

int main(int argc, char* argv[]) {
    printf(\"%d\\n\", sizeof(void *) * 8);
    return 0;
}
");

        # Compile the program
        unlink($executable);
        $x = MTT::DoCommand::Cmd(1, "$mpicc $executable.c -o $executable");

        if (0 == $x->{exit_value} && -x $executable) {

            # It compiled ok, so now run it.  Use mpirun so that
            # various paths and whatnot are set properly.
            $x = MTT::DoCommand::Cmd(1, "$mpirun -np 1 $executable", 30);
            if (0 == $x->{exit_value}) {
                $ret = _extract_valid_bitness($x->{result_stdout});

                if (! $ret) {
                    Warning("&get_mpi_instaled_bitness(): Sample compiled program $prog_name did not execute properly.\n");
                    Warning("&get_mpi_instaled_bitness(): $prog_name output: " . $x->{result_stdout} . "\n");
                } else {
                    Debug("$prog_name executed properly.\n");
                    $ret = _bitness_to_bitmapped($ret);
                    Debug("&get_mpi_install_bitness returning: $ret\n");
                    return $ret;
                }
            } else {
                Warning("&get_mpi_install_bitness(): Couldn't execute sample compiled program: $prog_name.\n");
            }
        } else {
            Warning("&get_mpi_instaled_bitness(): Couldn't compile sample $prog_name.c.\n");
        }
    }

    # 3)
    # Try snarfing bitness using the /usr/bin/file command
    my $libmpi = _find_libmpi();
    if (! -f $libmpi) {
        Debug("Couldn't find libmpi!\n");
        return "0";
    }

    my $leader = "[^:]+:";
    my $bitnesses;

    # Split up file command's output
    my @file_out = split /\n/, `file $libmpi`;

    foreach my $line (@file_out) {

        # Mac OSX *implies* 32-bit for ppc and i386
        if ($line =~ /$leader.*\bmach-o\b.*\b(?:ppc|i386)\b/i) {
            $bitnesses->{32} = 1;

        # 64-bit
        } elsif ($line =~ /$leader.*\b64-bit\b/i) {
            $bitnesses->{64} = 1;

        # 32-bit
        } elsif ($line =~ /$leader.*\b32-bit\b/i) {
            $bitnesses->{32} = 1;
        }
    }

    # Compose CSV of bitness(es)
    my $str = join(',', keys %{$bitnesses});

    $ret = _extract_valid_bitness($str);

    if (! defined($ret)) {
        Warning("Could not get bitness using \"file\" command.\n");
    } else {
        Debug("Got bitness using \"file\" command.\n");
    }

    $ret = _bitness_to_bitmapped($ret);
    Debug("&get_mpi_install_bitness returning: $ret\n");
    return $ret;
}

# Make sure the bitness value makes sense
sub _extract_valid_bitness {

    my $str = shift;
    my $ret;

    Debug("Validating bitness string ($str)\n");

    # Valid bitnesses
    my $v = "8|16|32|64|128";

    # CSV of one or more bitnesses
    if ($str =~ /^((?:$v) (?:\s*,\s*(?:$v))*)$/x) {
        $ret = $1;
    } else {
        $ret = undef;
    }

    return $ret;
}

# Convert the human-readable CSV of bitness(es) to
# its representation in the MTT database.
sub _bitness_to_bitmapped {

    my $csv = shift;
    my $ret = 0;
    my $shift;

    Debug("Converting bitness string ($csv) to a bitmapped value\n");

    return $ret if (! $csv);

    my @bitnesses = split(/,/, $csv);

    # Smallest bitness possible
    my $smallest = 8;

    # Generate a bitmap of all bitnesses
    foreach my $bitness (@bitnesses) {
        $shift = log($bitness)/log(2) - log($smallest)/log(2);
        $ret |= (1 << $shift);
    }

    return $ret;
}

#--------------------------------------------------------------------------

# Return a database-ready bitmapped value for endian-ness
sub get_mpi_install_endian {
    Debug("&get_mpi_intall_endian\n");

    my $override = shift;
    my $ret      = "0";

    # 1)
    # Users can override the automatic endian detection
    # (useful in cases where the MPI has multiple endians
    # e.g., Mac OSX universal binaries)
    if ($override) {
        $ret = _endian_to_bitmapped($override);

        Debug("&get_mpi_install_endian returning: $ret\n");
        return $ret;
    }


    # 2)
    # Try snarfing endian(s) using the /usr/bin/file command
    my $libmpi          = _find_libmpi();
    if (! -f $libmpi) {
        # No need to Warn() -- the fact that the MPI failed to install
        # should be good enough...
        Debug("*** Could not find libmpi to calculate endian-ness\n");
        return "0";
    }

    my $leader          = "[^:]+:";
    my $hardware_little = 'i386|x86_64';
    my $hardware_big    = 'ppc|ppc64';
    my $endians;

    # Split up file command's output
    my @file_out = split /\n/, `file $libmpi`;

    foreach my $line (@file_out) {

        # Mac OSX
        if ($line =~ /$leader.*\bmach-o\b.*(?:$hardware_little)\b/i) {
            $endians->{little} = 1;

        # Mac OSX
        } elsif ($line =~ /$leader.*\bmach-o\b.*(?:$hardware_big)\b/i) {
            $endians->{big} = 1;

        # Look for 'MSB' (Most Significant Bit)
        } elsif ($line =~ /$leader.*\bMSB\b/i) {
            $endians->{big} = 1;

        # Look for 'LSB' (Least Significant Bit)
        } elsif ($line =~ /$leader.*\bLSB\b/i) {
            $endians->{little} = 1;
        }
    }

    # Compose CSV of endian(s)
    my $str = join(',', keys %{$endians});

    $ret = _endian_to_bitmapped($str);

    if (! $ret) {
        Debug("Could not get endian-ness from $libmpi using \"file\" command.\n");
    } else {
        Debug("Got endian-ness using \"file\" command on $libmpi.\n");
        return $ret;
    }

    # 3)
    # Auto-detect by casting an int to a char
    my $str = unpack('c2', pack('i', 1)) ? 'little' : 'big';
    $ret = _endian_to_bitmapped($str);

    Debug("&get_mpi_install_endianness returning: $ret\n");
    return $ret;
}

# Convert the human-readable CSV of endian(s) to
# its representation in the MTT database.
sub _endian_to_bitmapped {

    my $csv        = shift;
    my $ret        = 0;
    my $bit_little = 0;
    my $bit_big    = 1;

    Debug("Converting endian string ($csv) to a bitmapped value\n");

    return $ret if (! $csv);

    if ($csv =~ /little/i) {
        $ret |= $ret | (1 << $bit_little);
    }
    if ($csv =~ /big/i) {
        $ret |= $ret | (1 << $bit_big);
    }
    if ($csv =~ /both/i) {
        $ret |= $ret | (1 << $bit_little) | (1 << $bit_big);
    }

    Debug("&_endian_to_bitmapped returning: $ret\n");
    return $ret;
}

# Return the MPI library that will be passed to the file command
sub _find_libmpi {

    my $install_dir = $MTT::MPI::Install::install_dir;
    my $ret = undef;

    # Try to find a libmpi
    my @libmpis = (
        "$install_dir/lib/libmpi.dylib",
        "$install_dir/lib/libmpi.a",
        "$install_dir/lib/libmpi.so",
    );

    foreach my $libmpi (@libmpis) {
        if (-e $libmpi) {
            while (-l $libmpi) {
                $libmpi = readlink($libmpi);
                next if (-e $libmpi);
                $libmpi = "$install_dir/lib/$libmpi";
                next if (-e $libmpi);
                Warning("*** Got bogus sym link for libmpi -- points to nothing\n");
                return $ret;
            }

            $ret = $libmpi;
            last;
        }
    }

    Debug("&_find_libmpi returning: $ret\n");
    return $ret;
}

1;
