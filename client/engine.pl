#!/usr/bin/env perl
#
# Copyright (c) 2004-2005 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2004-2005 The Trustees of the University of Tennessee.
#                         All rights reserved.
# Copyright (c) 2004-2005 High Performance Computing Center Stuttgart, 
#                         University of Stuttgart.  All rights reserved.
# Copyright (c) 2004-2005 The Regents of the University of California.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

use strict;
use Cwd;
use lib cwd();

use Data::Dumper;
use Config::IniFiles;
use Getopt::Long;
use MTT::MPI;
use MTT::Test;
use MTT::Files;
use MTT::Messages;
use MTT::INI;
use MTT::Reporter;
use MTT::Constants;

my @file_arg;
my $scratch_arg;
my $help_arg;
my $debug_arg;
my $verbose_arg;
my $force_arg;
my $get_mpi_arg;
my $install_mpi_arg;
my $build_tests_arg;
my $run_tests_arg;

&Getopt::Long::Configure("bundling", "require_order");
my $ok = Getopt::Long::GetOptions("file|f=s" => \@file_arg,
                                  "scratch|s=s" => \$scratch_arg,
				  "help|h" => \$help_arg,
				  "debug|d" => \$debug_arg,
				  "verbose|v" => \$verbose_arg,
                                  "force|f" => \$force_arg,
                                  "get-mpi" => \$get_mpi_arg,
                                  "install-mpi" => \$install_mpi_arg,
                                  "build-tests" => \$build_tests_arg,
                                  "run-tests" => \$run_tests_arg,
                                  );

# Everything ok?

if (! @file_arg) {
    print "Must specify at least one --file argument.\n";
    $ok = 0;
}
if (!$ok || $help_arg) {
    print("Command line error\n") 
        if (!$ok);
    print "Usage: $0 --file|-f filename\n";
    exit($ok);
}

# Check debug

my $debug = ($debug_arg ? 1 : 0);
my $verbose = ($verbose_arg ? 1 : $debug);
Debug("Debug is $debug, Verbose is $verbose\n");
Messages($debug, $verbose);

########################################################################
# Params
########################################################################

# See if we got a scratch root
if (! $scratch_arg) {
    $scratch_arg = ".";
}
Debug("Scratch: $scratch_arg\n");
if (! -d $scratch_arg) {
    MTT::Files::mkdir($scratch_arg, 0777);
}
if (! -d $scratch_arg) {
    Abort("Could not make scratch dir: $scratch_arg\n");
}
chdir($scratch_arg);
$scratch_arg = cwd();
Debug("Scratch resolved: $scratch_arg\n");

# If any of the --get-mpi, --install-mpi, --build-tests, or
# --run-tests are specified, then their defaults all go to 0.
# Otherwise, if none are specified, they all default to 1.

my $get_mpi = 1;
my $install_mpi = 1;
my $build_tests = 1;
my $run_tests = 1;

if (defined($get_mpi_arg) || defined($install_mpi_arg) ||
    defined($build_tests_arg) || defined($run_tests_arg)) {
    $get_mpi = $install_mpi = $build_tests = $run_tests = 0;

    $get_mpi = 1 if defined($get_mpi_arg);
    $install_mpi = 1 if defined($install_mpi_arg);
    $build_tests = 1 if defined($build_tests_arg);
    $run_tests = 1 if defined($run_tests_arg);
}


########################################################################
# Load up all old data
########################################################################

# Make directories
my $source_dir = 
    MTT::Files::mkdir("$scratch_arg/$MTT::Constants::source_subdir");
my $install_dir = 
    MTT::Files::mkdir("$scratch_arg/$MTT::Constants::install_subdir");

# Load up all the MPI sources that this system has previously obtained
MTT::MPI::LoadSources($source_dir);

# Load up all the installs of the MPI sources
MTT::MPI::LoadInstalls($install_dir);

# Load up the built tests for each install
MTT::Test::LoadBuilds($install_dir);


########################################################################
# Read the ini file(s)
########################################################################

foreach my $file (@file_arg) {

    # Load up the ini file

    Debug("Reading ini file: $file\n");
    my $ini = new Config::IniFiles(-file => $file, 
                                   -nocase => 1,
                                   -allowcontinue => 1);
    if (! $ini) {
        Warning("Could not read INI file: $file; skipping\n");
        next;
    }

    # Run the phases

    MTT::Reporter::Init($ini);

    MTT::MPI::Get($ini, $source_dir, $force_arg)
        if ($get_mpi);
    MTT::MPI::Install($ini, $install_dir, $force_arg)
        if ($install_mpi);
    MTT::Test::Build($ini, $install_dir, $force_arg)
        if ($build_tests);
    MTT::Test::Run($ini, $install_dir, $force_arg)
        if ($run_tests);

    # Remove old sources, installs, and builds

    # JMS do this...
}

# That's it!

exit(0);
