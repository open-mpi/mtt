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

package MTT::MPI::Install::OMPI;

use strict;
use Cwd;
use MTT::DoCommand;
use MTT::Messages;
use Data::Dumper;
use MTT::FindProgram;

#--------------------------------------------------------------------------

sub _find_bindings {
    my ($bindir, $libdir, $lang) = @_;

    my %ENV_SAVE = %ENV;
    if (exists($ENV{LD_LIBRARY_PATH})) {
        $ENV{LD_LIBRARY_PATH} = "$libdir:$ENV{LD_LIBRARY_PATH}";
    } else {
        $ENV{LD_LIBRARY_PATH} = "$libdir";
    }

    open INFO, "$bindir/ompi_info --parsable|";
    my @have = grep { /^bindings:$lang:/ } <INFO>;
    chomp @have;
    close INFO;

    %ENV = %ENV_SAVE;

    return ($have[0] =~ /^bindings:${lang}:yes/) ? "1" : "0";
}

#--------------------------------------------------------------------------

sub Install {
    my ($ini, $section, $config) = @_;
    my $x;
    my $result_stdout;
    my $result_stderr;

    # Prepare $ret

    my $ret;
    $ret->{test_result} = 0;
    $ret->{exit_status} = 0;

    # Run configure

    $ret->{installdir} = $config->{installdir};
    $ret->{bindir} = "$ret->{installdir}/bin";
    $ret->{libdir} = "$ret->{installdir}/lib";

    $x = MTT::DoCommand::Cmd(1, "$config->{configdir}/configure $config->{configure_arguments} --prefix=$ret->{installdir}", -1, $config->{stdout_save_lines}, $config->{stderr_save_lines});
    $result_stdout = $x->{result_stdout} ? "--- Configure result_stdout/result_stderr ---\n$x->{result_stdout}" :
        undef;
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        $ret->{result_message} = "Configure failed -- skipping this build";
        # Put the output of the failure into $ret so that it gets
        # reported (result_stdout/result_stderr was combined into just result_stdout)
        $ret->{result_stdout} = $result_stdout;
        $ret->{exit_status} = $x->{status};
        return $ret;
    }
    # We don't need this in the main result_stdout
    $ret->{configure_stdout} = $result_stdout;

    # Build it

    $x = MTT::DoCommand::Cmd($config->{merge_stdout_stderr}, "make $config->{make_all_arguments} all", -1, $config->{stdout_save_lines});
    $result_stdout = undef;
    if ($x->{result_stdout}) {
        $result_stdout = "--- \"make all ";
        $result_stdout .= "result_stdout"
            if ($x->{result_stdout});
        $result_stdout .= "/result_stderr"
            if ($config->{merge_stdout_stderr});
        $result_stdout .= " ---\n$x->{result_stdout}";
    }
    $result_stderr = $x->{result_stderr} ? "--- \"make all\" result_stderr ---\n$x->{result_stderr}" : 
        undef;
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        $ret->{result_message} = "Failed to build: make $config->{make_all_arguments} all";
        # Put the output of the failure into $ret so that it gets
        # reported (result_stdout/result_stderr *may* be separated, so assign them
        # both -- if they were combined, then $result_stderr will be empty)
        $ret->{result_stdout} = $result_stdout;
        $ret->{result_stderr} = $result_stderr;
        $ret->{exit_status} = $x->{status};
        return $ret;
    }
    $ret->{make_all_stdout} = $result_stdout;
    $ret->{make_all_stderr} = $result_stderr;

    # Do we want to run "make check"?  If so, make sure a valid TMPDIR
    # exists.  Also, merge the result_stdout/result_stderr because we really only
    # want to see it if something fails (i.e., it's common to display
    # junk to result_stderr during "make check"'s normal execution).

    if ($config->{make_check} == 1) {
        my %ENV_SAVE = %ENV;
        $ENV{TMPDIR} = "$ret->{installdir}/tmp";
        mkdir($ENV{TMPDIR}, 0777);
        # The intent here is just to ensure that the LD_LIBRARY_PATH
        # in the environment does not point to shared libraries
        # outside of MTT's scope that would interfere with "make
        # check" (e.g., another libmpi.so outside of MTT).  Just
        # prepend our own $libdir to LD_LIBRARY_PATH and hope that
        # that's Good Enough.  :-)
        if (exists($ENV{LD_LIBRARY_PATH})) {
            $ENV{LD_LIBRARY_PATH} = "$ret->{libdir}:$ENV{LD_LIBRARY_PATH}";
        } else {
            $ENV{LD_LIBRARY_PATH} = "$ret->{libdir}";
        }

        Debug("Running make check\n");
        $x = MTT::DoCommand::Cmd(1, "make check", -1, $config->{stdout_save_lines}, $config->{stderr_save_lines});
        %ENV = %ENV_SAVE;

        $result_stdout = "--- \"make check\" result_stdout ---\n$x->{result_stdout}"
            if ($x->{result_stdout});
        if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
            $ret->{result_message} = "Failed to make check";
            # Put the output of the failure into $ret so that it gets
            # reported (result_stdout/result_stderr were combined)
            $ret->{result_stdout} = $x->{result_stdout};
            $ret->{exit_status} = $x->{status};
            return $ret;
        }
        $ret->{make_check_stdout} = $result_stdout;
    } else {
        Debug("Not running make check\n");
    }

    # Install it.  Merge the result_stdout/result_stderr because we really only want
    # to see the output if something went wrong.  Things sent to
    # result_stderr are common during "make install" (e.g., notices about
    # re-linking libraries when they are installed)

    $x = MTT::DoCommand::Cmd(1, "make install", -1, $config->{stdout_save_lines}, $config->{stderr_save_lines});
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        $ret->{result_stdout} .= "--- \"make install\" result_stdout ---\n$x->{result_stdout}"
            if ($x->{result_stdout});
        $ret->{result_message} = "Failed to make install";
        # Put the output of the failure into $ret so that it gets
        # reported (result_stdout/result_stderr were combined)
        $ret->{result_stdout} = $x->{result_stdout};
        $ret->{exit_status} = $x->{status};
        return $ret;
    }
    $ret->{make_install_stdout} = $result_stdout;

    # Detect the library's pointer-size

    $ret->{bitness} = get_mpi_type();

    # Set which bindings were compiled

    $ret->{c_bindings} = 1;
    Debug("Have C bindings: 1\n");
    $ret->{cxx_bindings} = _find_bindings($ret->{bindir},
                                          $ret->{libdir}, "cxx");
    Debug("Have C++ bindings: $ret->{cxx_bindings}\n"); 
    $ret->{f77_bindings} = _find_bindings($ret->{bindir},
                                          $ret->{libdir}, "f77");
    Debug("Have F77 bindings: $ret->{f77_bindings}\n"); 
    $ret->{f90_bindings} = _find_bindings($ret->{bindir},
                                          $ret->{libdir}, "f90");
    Debug("Have F90 bindings: $ret->{f90_bindings}\n"); 

    # Write out the OMPI cleanup script and be done.

    if ((0 != write_cleanup_script("$ret->{installdir}/bin")) 
        and (! $MTT::DoCommand::no_execute)) {
        $ret->{test_result} = 0;
        $ret->{exit_status} = $x->{status};
        $ret->{message} = "Failed to create cleanup script!";
    } else {
        $ret->{test_result} = 1;
        $ret->{result_message} = "Success";
        $ret->{exit_status} = $x->{status};
        Debug("Build was a test_result\n");
    }

    return $ret;
} 

# Write out a script that's capable of cleaning up OMPI jobs
sub write_cleanup_script {
    my $bindir = shift;
    my $file = "$bindir/mtt_ompi_cleanup.pl";
    unlink($file);

    # Create the script and be paranoid about the permissions.

    my $u = umask;
    umask(0777);
    if (!open(FILE, ">$file")) {
        umask($u);
        return 1;
    }
    chmod(0755, $file);
    print FILE '#!/usr/bin/env perl
    
# This script is automatically generated by MTT/MPI/Install/OMPI.pm.  
# Manual edits will be lost.

# Helper cleanup script to kill all orteds on a node (except the one
# that spawed this script, so that the mpirun that started this script
# can complete normally), and remove all session directories.

use strict;

# See which variant of ps we have

my $ps_args;
my $pid_token;
my $cmd_start_token;
my $ret;

$ret = system("pgrep . > /dev/null 2> /dev/null");
$ret = $ret >> 8;

# Run ps or pgrep, and find all orteds.  Kill any that are not my parent.

my $orted_pid = getppid();

# List of processes to clean up
my @processes = ("orted", "mpirun");

# Try using pgrep
if (0 == $ret) {

    open(CMD, "pgrep \"" . join("|", @processes) . "\" |") ||
        warn("Could not run pgrep, so I can not cleanup stale " .
                en_join(@processes) . ".");

    while (<CMD>) {
        my $pid = $_;
        if ($pid != $orted_pid) {
            kill(9, $pid);
        }
    }

# Try using ps
} else {

    $ret = system("ps auxw > /dev/null 2> /dev/null");
    $ret = $ret >> 8;

    if (0 == $ret) {
        $ps_args = "auxww";
        $pid_token = 1;
        $cmd_start_token = 10;
    } else {
        $ps_args = "-eadf";
        $pid_token = 1;
        $cmd_start_token = 7;
    }

    open(CMD, "ps $ps_args|") || 
        warn("Could not run ps, so I can not cleanup stale " .
                en_join(@processes) . ".");

    while (<CMD>) {
        my @tokens = split(/\s+/);
        my $pattern = join("|", map { "\\b$_\\b" } @processes);

        # Only look at the first token in the command to see if it is the
        # orted; we do not want to grab incidental processes that contain
        # "orted" (e.g., "emacs orted.c", "ssh <othernode> orted ...",
        # etc.).
        if ($tokens[$cmd_start_token] =~ /$pattern/) {
            if ($tokens[$pid_token] != $orted_pid) {
                # Do not bother to check the return from kill() because, at
                # least at the moment, there could be multiple instances
                # of this script running on a single node :-(
                kill(9, $tokens[$pid_token]);
            }
        }
    }
}
close(CMD);

# Whack any sessions directories

my $who = getpwuid($<);
system("rm -rf /tmp/openmpi-sessions-$who* > /dev/null 2>&1");

# All done

exit(0);

# Return an English-formatted list
sub en_join {

    my($list) = @_;

    if (@$list == 0) {
        return undef;
    } elsif (@$list == 1) {
        return @$list[0];
    } elsif (@$list == 2) {
        return @$list[0] . " and " . @$list[1];
    } elsif (@$list > 2) {
        return join(", ", @$list[0..(@$list - 2)]) .
                ", and " . @$list[@$list - 1];
    }
}
';

    close(FILE);
    umask($u);
    return 0;
}

# Determine the pointer-size (32-bit or
# 64-bit) of the installed Open MPI library
sub get_mpi_type {

    my $tmp;
    my $libmpi;
    my $filetype;
    my @binaries = (
        "opal_wrapper",
        "orted",
        "orteprobe",
        "orterun",
    );

    $tmp        = FindProgram(@binaries);
    $tmp        =~ s#\bbin/.*#lib\/libmpi.so#;
    $libmpi     = $tmp;
    $filetype   = `file $libmpi`;
    ($filetype) =~ m/\:(.*)$/;

    if ($filetype =~ /\b32\b/) {
        return 32;
    } elsif ($filetype =~ /\b64\b/) {
        return 64;
    } else {
        return undef;
    }
}

1;
