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

package MTT::Test::Run;

use strict;
use File::Basename;
use Time::Local;
use MTT::Messages;
use MTT::Values;
use MTT::Reporter;
use MTT::Defaults;
use MTT::Test::Specify;
use MTT::Test::RunEngine;
use Data::Dumper;

#--------------------------------------------------------------------------

# Exported current number of processes in the test
our $test_np;

# Exported current prefix of the MPI under test
our $test_prefix;

# Exported current executable under text
our $test_executable;

# Exported current argv under test
our $test_argv;

# Exported exit status of the last test run
our $test_exit_status;

#--------------------------------------------------------------------------

sub Run {
    my ($ini, $top_dir, $force) = @_;

    # Save the environment
    my %ENV_SAVE = %ENV;

    Verbose("*** Run test phase starting\n");

    # Go through all the sections in the ini file looking for section
    # names that begin with "Test run:"
    foreach my $section ($ini->Sections()) {
        if ($section =~ /^\s*test run:/) {

            # Simple section name
            my $simple_section = $section;
            $simple_section =~ s/^\s*test run:\s*//;
            Verbose(">> Test run [$simple_section]\n");

            # Ensure that we have a test build name
            my $test_build_value = MTT::Values::Value($ini, $section, "test_build");
            if (!$test_build_value) {
                Warning("No test_build specified in [$section]; skipping\n");
                next;
            }

            # Iterate through all the test_build values
            my @test_builds = split(/,/, $test_build_value);
            foreach my $test_build_name (@test_builds) {
                # Strip whitespace
                $test_build_name =~ s/^\s*(.*?)\s*/\1/;

                # Find the matching test build.  Test builds are
                # indexed on (in order): MPI Get simple section name,
                # MPI Install simple section name, Test Build simple
                # section name
                foreach my $mpi_get_key (keys(%{$MTT::Test::builds})) {
                    foreach my $mpi_version_key (keys(%{$MTT::Test::builds->{$mpi_get_key}})) {
                        foreach my $mpi_install_key (keys(%{$MTT::Test::builds->{$mpi_get_key}->{$mpi_version_key}})) {
                            foreach my $test_build_key (keys(%{$MTT::Test::builds->{$mpi_get_key}->{$mpi_version_key}->{$mpi_install_key}})) {
                                
                                if ($test_build_key eq $test_build_name) {
                                    my $test_build = $MTT::Test::builds->{$mpi_get_key}->{$mpi_version_key}->{$mpi_install_key}->{$test_build_key};
                                    Debug("Found a match! $test_build_key [$simple_section\n");
                                    if (!$test_build->{success}) {
                                        Debug("But that build was borked -- skipping\n");
                                        next;
                                    }
                                    my $mpi_install = $MTT::MPI::installs->{$mpi_get_key}->{$mpi_version_key}->{$mpi_install_key};
                                    _do_run($ini, $section, $test_build, 
                                            $mpi_install, $top_dir, $force);
                                    %ENV = %ENV_SAVE;
                                }
                            }
                        }
                    }                        
                }
            }
        }
    }

    Verbose("*** Run test phase complete\n");
} 

#--------------------------------------------------------------------------

sub _do_run {
    my ($ini, $section, $test_build, $mpi_install, $top_dir, $force) = @_;

    # Check both specify_module and module (for backcompatibility)
    my $specify_module;
    $specify_module = MTT::Values::Value($ini, $section, "specify_module");
    $specify_module = MTT::Values::Value($ini, $section, "module") if (!$specify_module);

    if (!$specify_module) {
        Warning("No module specified in [$section]; skipping\n");
        return;
    }

    Verbose(">> Running with [$mpi_install->{mpi_get_simple_section_name}] / [$mpi_install->{mpi_version}] / [$mpi_install->{simple_section_name}]\n");
    # Find an MPI details section for this MPI
    my $match = 0;
    my ($mpi_details_section,
        $details_install_section,
        $mpi_install_section);

    foreach my $s ($ini->Sections()) {
        if ($s =~ /^\s*mpi details:/) {
            Debug("Found MPI details: [$s]\n");

            # MPI Details can be specified per MPI Install,
            # or globally for every MPI Install
            $details_install_section = MTT::Values::Value($ini, $s, "mpi_name");
            $mpi_install_section = $mpi_install->{simple_section_name};
            $mpi_details_section = $s;

            if (($details_install_section eq $mpi_install_section) or
                ! $details_install_section) {

                Debug("Using [$s] with [MPI Install: $mpi_install_section]\n");
                $match = 1;
                last;
            }
        }
    }
    if (!$match and !$mpi_details_section) {
        Warning("Unable to find MPI details section for [MPI Install: $details_install_section]; skipping\n");
        return;
    }
    
    # Get some details about running with this MPI
    my $mpi_details;
    $MTT::Test::Run::test_prefix = $mpi_install->{installdir};
    $mpi_details->{before_any_exec} = 
        MTT::Values::Value($ini, $mpi_details_section, "before_any_exec");
    $mpi_details->{before_each_exec} = 
        MTT::Values::Value($ini, $mpi_details_section, "before_each_exec");
    $mpi_details->{after_each_exec} = 
        MTT::Values::Value($ini, $mpi_details_section, "after_each_exec");
    $mpi_details->{after_all_exec} = 
        MTT::Values::Value($ini, $mpi_details_section, "after_all_exec");
    # Do not evaluate this one now yet
    my $exec = $ini->val($mpi_details_section, "exec");
    while ($exec =~ m/@(.+?)@/) {
        my $val = $ini->val($mpi_details_section, $1);
        if (!$val) {
            Warning("Used undefined key @$1@ in exec value; skipping");
            return;
        }
        $exec =~ s/@(.+?)@/$val/;
    }
    Debug("Got final exec: $exec\n");
    $mpi_details->{exec} = $exec;
    $mpi_details->{name} = $mpi_install->{mpi_name};
    $mpi_details->{mpi_get_simple_section_name} =
        $mpi_install->{mpi_get_simple_section_name};
    $mpi_details->{mpi_install_simple_section_name} = 
        $mpi_install->{simple_section_name};
    $mpi_details->{version} = $mpi_install->{mpi_version};

    # Go to the right dir
    MTT::DoCommand::Chdir($test_build->{srcdir});

    # Set the PATH and LD_LIBRARY_PATH
    if ($mpi_install->{bindir}) {
        if (exists($ENV{PATH})) {
            $ENV{PATH} = "$mpi_install->{bindir}:" . $ENV{PATH};
        } else {
            $ENV{PATH} = $mpi_install->{bindir};
        }
    }
    if ($mpi_install->{libdir}) {
        if (exists($ENV{LD_LIBRARY_PATH})) {
            $ENV{LD_LIBRARY_PATH} = "$mpi_install->{libdir}:" . 
                $ENV{LD_LIBRARY_PATH};
        } else {
            $ENV{LD_LIBRARY_PATH} = $mpi_install->{libdir};
        }
    }

    # Process setenv, unsetenv, prepend-path, and append-path -- for
    # both the MPI that we're building with and the section of the ini
    # file that we're building.
    my @save_env;
    MTT::Values::ProcessEnvKeys($mpi_install, \@save_env);
    # JMS: Do we need to grab from Test::Build as well?
    my $config;
    %$config = %$MTT::Defaults::Test_specify;
    $config->{setenv} = MTT::Values::Value($ini, $section, "setenv");
    $config->{unsetenv} = MTT::Values::Value($ini, $section, "unsetenv");
    $config->{prepend_path} = 
        MTT::Values::Value($ini, $section, "prepend_path");
    $config->{append_path} = MTT::Values::Value($ini, $section, "append_path");
    MTT::Values::ProcessEnvKeys($config, \@save_env);

    # Get global values that apply to each test executable, unless
    # they supplied their own.  Don't use Value for all of them; some
    # we need to delay the evaluation.
    my $tmp;
    $tmp = $ini->val($section, "np");
    $config->{np} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "np_ok");
    $config->{np_ok} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "argv");
    $config->{argv} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "pass");
    $config->{pass} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "skipped");
    $config->{skipped} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "save_stdout_on_pass");
    $config->{save_stdout_on_pass} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "stderr_save_lines");
    $config->{stderr_save_lines} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "stdout_save_lines");
    $config->{stdout_save_lines} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "merge_stdout_stderr");
    $config->{merge_stdout_stderr} = $tmp
        if (defined($tmp));
    $tmp = $ini->val($section, "timeout");
    $config->{timeout} = $tmp
        if (defined($tmp));

    # Run the specify module to get a list of tests to run
    my $ret = MTT::Test::Specify::Specify($specify_module, $ini, $section, 
                                          $test_build, $mpi_install, $config);

    # Grab the output-parser plugin, if there is one
    $ret->{analyze_module} = MTT::Values::Value($ini, $section, "analyze_module");

    # If we got a list of tests to run, invoke the run engine to
    # actually run them.
    if ($ret && $ret->{success}) {
        MTT::Test::RunEngine::RunEngine($section, $top_dir, $mpi_details,
                                        $test_build, $force, $ret);
    }
}

1;
