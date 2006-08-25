#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
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
use MTT::Test::Run;
use MTT::Globals;

#--------------------------------------------------------------------------

# Returns the stdout of running a shell command
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

# Return the exit status from the last test run
sub test_exit_status {
    Debug("&test_exit_status returning: $MTT::Test::Run::test_exit_status\n");

    return $MTT::Test::Run::test_exit_status;
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
    Debug("&rm_max_procs\n");

    # Resource managers
    return slurm_max_procs()
        if slurm_job();
    return pbs_max_procs()
        if pbs_job();

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

1;
