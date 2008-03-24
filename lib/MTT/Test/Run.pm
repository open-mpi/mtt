#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2007 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2008      Mellanox Technologies.  All rights reserved.
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
use MTT::Util;
use MTT::EnvModule;
use MTT::INI;
use Data::Dumper;

#--------------------------------------------------------------------------

# Exported current command line in the test
our $test_command_line;

# Exported current number of processes in the test
our $test_np;

# Exported current prefix of the MPI under test
our $test_prefix;

# Exported current executable under text
our $test_executable;

# Exported current argv under test
our $test_argv;

# Exported whether we're running by-node or by-slot
our $test_alloc;

# Exported exit_status of the last test run
our $test_exit_status;

# Exported pid of the last test run
our $test_pid;

# Exported data to mpi details section
our $mpi_details;

# What we call this phase
my $phase_name = "Test run";

#--------------------------------------------------------------------------

sub Run {
    my ($ini, $ini_full, $install_dir, $runs_data_dir, $force) = @_;

    # Save the environment
    my %ENV_SAVE = %ENV;

    $MTT::Globals::Values->{active_phase} = $phase_name;
    Verbose("*** $phase_name phase starting\n");

    # Go through all the sections in the ini file looking for section
    # names that begin with "Test run:"
    foreach my $section ($ini->Sections()) {
        # See if we're supposed to terminate.  Only check in the
        # outtermost and innermost loops (even though we *could* check
        # at every loop level); that's good enough.
        last
            if (MTT::Util::find_terminate_file());

        if ($section =~ /^\s*test run:/) {

            # Simple section name
            my $simple_section = GetSimpleSection($section);
            Verbose(">> $phase_name [$simple_section]\n");

            # Ensure that we have a test build name
            my $test_build_value = MTT::Values::Value($ini, $section, "test_build");
            if (!$test_build_value) {
                Warning("No test_build specified in [$section]; skipping\n");
                next;
            }

            # Make the active INI section name known
            $MTT::Globals::Values->{active_section} = $section;

            # Iterate through all the test_build values
            my @test_builds = MTT::Util::split_comma_list($test_build_value);
            foreach my $test_build_name (@test_builds) {
                # Strip whitespace
                $test_build_name =~ s/^\s*(.*?)\s*/\1/;
                $test_build_name = lc($test_build_name);

                # This is only warning about the INI file; we'll see
                # if we find meta data for the test build later
                if (!$ini_full->SectionExists("test build: $test_build_name")) {
                    Warning("Test Build section \"$test_build_name\" does not seem to exist in the INI file\n");
                }

                # Don't bother explicitly searching for the test build
                # and issuing a Debug/next because we'll implicitly do
                # this below.

                # Find the matching test build.  Test builds are
                # indexed on (in order): MPI Get simple section name,
                # MPI Install simple section name, Test Build simple
                # section name
                foreach my $mpi_get_key (keys(%{$MTT::Test::builds})) {
                    foreach my $mpi_version_key (keys(%{$MTT::Test::builds->{$mpi_get_key}})) {
                        foreach my $mpi_install_key (keys(%{$MTT::Test::builds->{$mpi_get_key}->{$mpi_version_key}})) {
                            foreach my $test_build_key (keys(%{$MTT::Test::builds->{$mpi_get_key}->{$mpi_version_key}->{$mpi_install_key}})) {

                                # See if we're supposed to terminate.
                                # Only check in the outtermost and
                                # innermost loops (even though we
                                # *could* check at every loop level);
                                # that's good enough.
                                last
                                    if (MTT::Util::find_terminate_file());

                                if ($test_build_key eq $test_build_name) {
                                    my $test_build = $MTT::Test::builds->{$mpi_get_key}->{$mpi_version_key}->{$mpi_install_key}->{$test_build_key};
                                    Debug("Found a match! $test_build_key [$simple_section\n");
                                    if (!$test_build->{test_result}) {
                                        Debug("But that build was borked -- skipping\n");
                                        next;
                                    }
                                    my $mpi_install = $MTT::MPI::installs->{$mpi_get_key}->{$mpi_version_key}->{$mpi_install_key};
                                    my $mpi_get = $MTT::MPI::sources->{$mpi_get_key}->{$mpi_version_key};

                                    # See if we're supposed to skip
                                    # this MPI get or this MPI install
                                    my $go_next = 0;
                                    my $skip_mpi_get = 
                                        MTT::Values::Value($ini, $section, 
                                                           "skip_mpi_get");
                                    foreach my $skip_one_mpi_get (MTT::Util::split_comma_list($skip_mpi_get)) {
                                        if ($skip_one_mpi_get &&
                                                $skip_one_mpi_get eq $mpi_get_key) {
                                            Verbose("   Skipping run for [$mpi_get_key] / [$mpi_version_key] / [$mpi_install_key] / [$simple_section] per INI configuration\n");
                                            $go_next = 1;
                                        }
                                    }
                                    my $skip_mpi_install = 
                                        MTT::Values::Value($ini, $section, 
                                                           "skip_mpi_install");
                                    foreach my $skip_one_mpi_install (MTT::Util::split_comma_list($skip_mpi_install)) {
                                        if ($skip_one_mpi_install &&
                                                $skip_one_mpi_install eq $mpi_install_key) {
                                            Verbose("   Skipping run for [$mpi_get_key] / [$mpi_version_key] / [$mpi_install_key] / [$simple_section] per INI configuration\n");
                                            $go_next = 1;
                                        }
                                    }

                                    if ($go_next) {
                                        next;
                                    }

                                    # Alles gut.  Go do it.
                                    $MTT::Globals::Internals->{mpi_get_name} =
                                        $mpi_get_key;
                                    $MTT::Globals::Internals->{mpi_install_name} =
                                        $mpi_install_key;
                                    $MTT::Globals::Internals->{test_get_name} =
                                        $test_build->{test_get_simple_section_name};
                                    $MTT::Globals::Internals->{test_build_name} =
                                        $test_build_name;
                                    $MTT::Globals::Internals->{test_run_name} =
                                        $simple_section;
                                    $MTT::Globals::Internals->{test_run_full_name} =
                                        $section;
                                    _do_run($ini, $section, $test_build, 
                                            $mpi_get, $mpi_install,
                                            $install_dir, $runs_data_dir, 
                                            $force);
                                    delete $MTT::Globals::Internals->{mpi_get_name};
                                    delete $MTT::Globals::Internals->{mpi_install_name};
                                    delete $MTT::Globals::Internals->{test_get_name};
                                    delete $MTT::Globals::Internals->{test_build_name};
                                    delete $MTT::Globals::Internals->{test_run_name};
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
    my ($ini, $section, $test_build, $mpi_get, $mpi_install, $install_dir, 
        $runs_data_dir, $force) = @_;

    # Check both specify_module and module (for backcompatibility)
    my $specify_module;
    $specify_module = MTT::Values::Value($ini, $section, "specify_module");
    $specify_module = MTT::Values::Value($ini, $section, "module")
        if (!$specify_module);

    if (!$specify_module) {
        Warning("No module specified in [$section]; skipping\n");
        return;
    }

    Verbose(">> Running with [$mpi_install->{mpi_get_simple_section_name}] / [$mpi_install->{mpi_version}] / [$mpi_install->{simple_section_name}]\n");
    # Find an MPI details section for this MPI

    # First: see if there is an mpi_details field in our MPI install
    # section with a corresponding MPI Details section
    my $match = 0;
    my $mpi_install_simple = $mpi_install->{simple_section_name};
    if (defined($mpi_install->{mpi_details})) {
        my $search = lc($mpi_install->{simple_section_name});
        Debug("Found mpi_details [$search] in MPI install [$mpi_install_simple]\n");
        foreach my $s ($ini->Sections()) {
            if ($s =~ /^\s*mpi details:/) {
                $s =~ m/\s*mpi details:\s*(.+)\s*$/;
                my $mpi_details_simple = $1;
                Debug("Found MPI details: [$mpi_details_simple]\n");
                if ($search eq $mpi_details_simple) {
                    $match = 1;
                    $MTT::Globals::Internals->{mpi_details_name} = $s;
                    $MTT::Globals::Internals->{mpi_details_simple_name} = $mpi_details_simple;
                    last;
                }
            }
        }
    }

    # Next: see if there is an mpi_details field in our MPI get
    # section with a corresponding MPI Details section
    my $mpi_get_simple = $mpi_install->{mpi_get_simple_section_name};
    my @keys;
    push(@keys, $mpi_get_simple);
    push(@keys, $mpi_install->{mpi_version});
    push(@keys, "mpi_details");
    my $val = does_hash_key_exist($MTT::MPI::sources, @keys);
    if (!$match && defined($val)) {
        my $search = lc($val);
        Debug("Found mpi_details [$search] in MPI get [$mpi_install->{mpi_get_simple_section_name}]\n");
        foreach my $s ($ini->Sections()) {
            if ($s =~ /^\s*mpi details:/) {
                $s =~ m/\s*mpi details:\s*(.+)\s*$/;
                my $mpi_details_simple = $1;
                Debug("Found MPI details: [$mpi_details_simple]\n");
                if ($search eq $mpi_details_simple) {
                    $match = 1;
                    $MTT::Globals::Internals->{mpi_details_name} = $s;
                    last;
                }
            }
        }
    }

    # Next: see if there is an mpi_install field in an MPI Details
    # section that matches this MPI Install section
    if (!$match) {
        foreach my $s ($ini->Sections()) {
            if ($s =~ /^\s*mpi details:/) {
                $s =~ m/\s*mpi details:\s*(.+)\s*$/;
                my $mpi_details_simple = $1;
                Debug("Found MPI details: [$mpi_details_simple]\n");

                my $details_mpi_install_simple = 
                    lc(MTT::Values::Value($ini, $s, "mpi_install"));
                if ($mpi_install_simple eq $details_mpi_install_simple) {
                    $match = 1;
                    $MTT::Globals::Internals->{mpi_details_name} = $s;
                    last;
                }
            }
        }
    }

    # Next: see if there is an mpi_get field in an MPI Details
    # section that matches this MPI get section
    if (!$match) {
        foreach my $s ($ini->Sections()) {
            if ($s =~ /^\s*mpi details:/) {
                $s =~ m/\s*mpi details:\s*(.+)\s*$/;
                my $mpi_details_simple = $1;
                Debug("Found MPI details: [$mpi_details_simple]\n");

                my $details_mpi_get_simple = 
                    lc(MTT::Values::Value($ini, $s, "mpi_get"));
                if ($mpi_get_simple eq $details_mpi_get_simple) {
                    $match = 1;
                    $MTT::Globals::Internals->{mpi_details_name} = $s;
                    last;
                }
            }
        }
    }

    # Finally: if we found nothing else, just use the first MPI
    # Details section that we find.
    if (!$match) {
        foreach my $s ($ini->Sections()) {
            $s =~ m/\s*mpi details:\s*(.+)\s*$/;
            my $mpi_details_simple = $1;
            $MTT::Globals::Internals->{mpi_details_name} = $s;
            last;
        }
    }

    if (!$match) {
        Warning("Unable to find MPI details section for [MPI Install: $mpi_install->{simple_section_name}; skipping\n");
        delete $MTT::Globals::Internals->{mpi_details_name};
        return;
    }
    my $mpi_details_section = $MTT::Globals::Internals->{mpi_details_name};
    $mpi_details_section =~ m/\s*mpi details:\s*(.+)\s*$/;
    my $mpi_details_simple_section = $1;
    Verbose("   Using MPI Details [$mpi_details_simple_section] with MPI Install [$mpi_install->{simple_section_name}]\n");

    # Get some details about running with this MPI
    my $mpi_details;
    $MTT::Test::Run::test_prefix = $mpi_install->{installdir};

    # Determine which exec param we want to use
    my $mpi_details_exec = MTT::Values::Value($ini, $section, "mpi_details_exec");

    # Do not evaluate this one yet
    my $suffix = $mpi_details_exec ? ":$mpi_details_exec" : "";
    my $exec = $ini->val($mpi_details_section, "exec$suffix");
    while ($exec =~ m/@(.+?)@/) {
        my $val = $ini->val($mpi_details_section, $1);
        if (! $val) {
            Warning("Used undefined key \@$1\@ in exec value; \n");
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

    # Do not evaluate these yet
    $mpi_details->{launcher} = 
        $ini->val($mpi_details_section, "launcher$suffix");
    $mpi_details->{launcher} = $MTT::Defaults::Test_run->{launcher}
        if (!defined($mpi_details->{launcher}));
    $mpi_details->{resource_manager} = 
        $ini->val($mpi_details_section, "resource_manager$suffix");
    $mpi_details->{resource_manager} =
        $MTT::Defaults::Test_run->{resource_manager}
        if (!defined($mpi_details->{resource_manager}));
    $mpi_details->{parameters} = 
        $ini->val($mpi_details_section, "parameters$suffix");
    $mpi_details->{network} = 
        $ini->val($mpi_details_section, "network$suffix");

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

    # Process loading of modules -- for both the MPI install and the
    # test build sections
    my $config;
    my @env_modules;
    my $val = MTT::Values::Value($ini, $section, "env_module");
    if (defined($val) && defined($test_build->{env_modules})) {
        $config->{env_modules} = $test_build->{env_modules} . "," .
            $config->{env_modules};
    } elsif (defined($val)) {
        $config->{env_modules} = $val;
    } elsif (defined($test_build->{env_modules})) {
        $config->{env_modules} = $test_build->{env_modules};
    }
    if (defined($config->{env_modules})) {
        @env_modules = MTT::Util::split_comma_list($config->{env_modules});
        MTT::EnvModule::unload(@env_modules);
        MTT::EnvModule::load(@env_modules);
        Debug("Loading environment modules: @env_modules\n");
    }

    # Process setenv, unsetenv, prepend-path, and append-path -- for
    # both the MPI that we're building with and the section of the ini
    # file that we're building.
    my @save_env;
    MTT::Values::ProcessEnvKeys($mpi_get, \@save_env);
    MTT::Values::ProcessEnvKeys($mpi_install, \@save_env);
    MTT::Values::ProcessEnvKeys($test_build, \@save_env);
    %$config = %$MTT::Defaults::Test_specify;
    $config->{setenv} = MTT::Values::Value($ini, $section, "setenv");
    $config->{unsetenv} = MTT::Values::Value($ini, $section, "unsetenv");
    $config->{prepend_path} = 
        MTT::Values::Value($ini, $section, "prepend_path");
    $config->{append_path} = MTT::Values::Value($ini, $section, "append_path");
    MTT::Values::ProcessEnvKeys($config, \@save_env);

    # description
    $config->{description} = Value($ini, $section, "description");
    $config->{description} = Value($ini, "MTT", "description")
        if (!$config->{description});

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

    $MTT::Test::Run::mpi_details = undef;
    foreach my $field ($ini->Parameters($section)) {
        if ($field =~ /^mpi_details:/) {
            $field =~ m/^mpi_details:(.+)/;
            $MTT::Test::Run::mpi_details->{$1} = $ini->val($section, $field);
        }
    }

    # Fill in the steps to run
    _fill_step($ini, $mpi_details_section, "before_any_exec", $mpi_details);
    _fill_step($ini, $mpi_details_section, "before_each_exec", $mpi_details);
    _fill_step($ini, $mpi_details_section, "after_each_exec", $mpi_details);
    _fill_step($ini, $mpi_details_section, "after_all_exec", $mpi_details);

    # Bump the refcount on the test build
    ++$test_build->{refcount};

    # Run the specify module to get a list of tests to run
    my $ret = MTT::Test::Specify::Specify($specify_module, $ini, $section, 
                                          $test_build, $mpi_install, $config);

    # Grab the output-parser plugin, if there is one, and save the
    # description.
    $ret->{analyze_module} = MTT::Values::Value($ini, $section, 
                                                "analyze_module");
    $ret->{description} = $config->{description};

    # If we got a list of tests to run, invoke the run engine to
    # actually run them.
    if ($ret && $ret->{test_result}) {
        MTT::Test::RunEngine::RunEngine($ini, $section, $install_dir, 
                                        $runs_data_dir, $mpi_details,
                                        $test_build, $force, $ret);
    }

    # Unload any loaded environment modules
    if ($#env_modules >= 0) {
        Debug("Unloading environment modules: @env_modules\n");
        MTT::EnvModule::unload(@env_modules);
    }
}

#--------------------------------------------------------------------------

sub _fill_step {
    my ($ini, $mpi_details_section, $name, $mpi_details) = @_;
    my ($t, $v);

    $mpi_details->{$name} = 
        MTT::Values::Value($ini, $mpi_details_section, $name);

    $t = $name . "_timeout";
    $v = MTT::Values::Value($ini, $mpi_details_section, $t);
    $v = $MTT::Globals::Values->{$t}
        if (!defined($v));
    $mpi_details->{$t} = MTT::Util::parse_time_to_seconds($v);

    $t = $name . "_pass";
    $v = MTT::Values::Value($ini, $mpi_details_section, $t);
    $v = $MTT::Globals::Values->{$t}
        if (!defined($v));
    $mpi_details->{$t} = $v;
}

1;
