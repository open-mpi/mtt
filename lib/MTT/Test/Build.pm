#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

########################################################################
# Build Tests phase
########################################################################

# The output of this phase is the @MTT::Test::tests
# array of structs, each with the following members:

# Fields...

# Note that PATH and LD_LIBRARY_PATH are automatically prepended with
# relevant values for each MPI installation before each sub-component
# is invoked to build a test suite.  Hence, "mpicc" (and friends)
# should be found via the PATH and if they require some .so files,
# should be handled properly.  

# As a direct result, it is not necessary to prepent-path for PATH or
# LD_LIBRARY_PATH in the ini file; it is done automatically.

########################################################################

package MTT::Test::Build;

use strict;
use Cwd;
use Time::Local;
use MTT::DoCommand;
use MTT::Reporter;
use MTT::Messages;
use MTT::INI;
use MTT::Module;
use MTT::Values;
use MTT::Files;
use MTT::Defaults;
use Data::Dumper;

#--------------------------------------------------------------------------

# File to keep data about builds
my $built_file = "test_built.ini";

# Section in the ini file where info is located
my $built_section = "test_built";

# Where the top-level build tree is
my $build_base;

#--------------------------------------------------------------------------

sub _make_safe_dir {
    my ($ret) = @_;

    $ret = MTT::Files::make_safe_filename($ret);
    return MTT::Files::mkdir($ret);
}

#--------------------------------------------------------------------------

sub Build {
    my ($ini, $build_base, $force) = @_;

    Verbose("*** Test build phase starting\n");

    # Save the environment
    my %ENV_SAVE = %ENV;

    # Go through all the sections in the ini file looking for section
    # names that begin with "Test build:"
    chdir($build_base);
    foreach my $section ($ini->Sections()) {
        if ($section =~ /^\s*test build:/) {
            Verbose(">> Test build [$section]\n");
            my $skip = Logical($ini, $section, "skip");
            if ($skip) {
                Verbose("   Skipped\n");
                next;
            }

            # For each MPI source
            foreach my $mpi_get_key (keys(%{$MTT::MPI::installs})) {
                my $mpi_get = $MTT::MPI::installs->{$mpi_get_key};

                # For each installation of that source
                foreach my $mpi_install_key (keys(%{$mpi_get})) {
                    my $mpi_install = $mpi_get->{$mpi_install_key};

                    # Ensure that this was a successful MPI install
                    if (!$mpi_install->{success}) {
                        Debug("Found MPI install $mpi_install->{section_name}, but it did not have success==1\n");
                        next;
                    }

                    # See if we've already got a test build for this
                    # MPI installation.  Test incrementally so that it
                    # doesn't create each intermediate key.
                    if (!$force &&
                        exists($MTT::Test::builds->{$mpi_get_key}) &&
                        exists($MTT::Test::builds->{$mpi_get_key}->{$mpi_install_key}) &&
                        exists($MTT::Test::builds->{$mpi_get_key}->{$mpi_install_key}->{$section})) {
                        Verbose("   Already have a build for $mpi_install->{mpi_name} / [$mpi_install->{section_name}] / [$mpi_install->{mpi_get_section_name}]\n");
                        next;
                    }

                    # We don't have a test build for this particular
                    # MPI source instance.  So cd into the MPI install
                    # tree for this particular MPI install.

                    Verbose("   Building for $mpi_install->{mpi_name} / [$mpi_install->{section_name}] / [$mpi_install->{mpi_get_section_name}]\n");

                    chdir($build_base);
                    chdir(MTT::Files::make_safe_filename($mpi_install->{mpi_get_section_name}));
                    chdir(MTT::Files::make_safe_filename($mpi_install->{section_name}));

                    # Do the build and restore the environment
                    _do_build($ini, $section, $build_base, $mpi_install);
                    %ENV = %ENV_SAVE;
                    Verbose("   Completed build\n");
                }
            }
        }
    }

    Verbose("*** Test build phase complete\n");
}


#--------------------------------------------------------------------------

sub _do_build {
    my ($ini, $section, $build_base, $mpi_install) = @_;

    my $pretty_name = Value($ini, $section, "pretty_name");
    if (!$pretty_name) {
        $pretty_name = $section;
    }

    my $config;
    %$config = %$MTT::Defaults::Test_build;
    $config->{section_name} = $section;
    $config->{pretty_name} = $pretty_name;
    $config->{srcdir} = "to be filled in below";
    $config->{setenv} = "to be filled in below";
    $config->{unsetenv} = "to be filled in below";
    $config->{prepend_path} = "to be filled in below";
    $config->{append_path} = "to be filled in below";
        
    # Filled in by the module
    $config->{success} = 0;
    $config->{msg} = "";
    $config->{stdout} = "";

    # Find the build module
    $config->{build_module} = Value($ini, $section, "module");
    if (!$config->{build_module}) {
        Warning("No module specified for [$section]; skipping\n");
        return;
    }

    # Find the tests source
    my $source;
    $source->{tarball} = Value($ini, $section, "source_tarball");
    $source->{copydir} = Value($ini, $section, "source_copydir");
    $source->{svn} = Value($ini, $section, "source_svn");
    $source->{svn_username} = Value($ini, $section, "source_svn_username");
    $source->{svn_password} = Value($ini, $section, "source_svn_password");
    $source->{svn_password_cache} = Value($ini, $section, "source_svn_password_cache");
    if (!$source->{tarball} && 
        !$source->{copydir} &&
        !$source->{svn}) {
        Warning("No source specified (source_tarball, source_copydir, or source_svn) for [$section]; skipping\n");
        return;
    }

    # Make a directory just for this ini section
    my $tests_dir = MTT::Files::mkdir("tests");
    chdir($tests_dir);
    my $build_section_dir = _make_safe_dir($section);
    chdir($build_section_dir);
            
    # Handle the source
    if ($source->{tarball}) {
        Debug("BuildTests: got source tarball: $source->{tarball}\n");
        $config->{srcdir} =
            MTT::Files::unpack_tarball($source->{tarball}, 1);
    } elsif ($source->{svn}) {
        Debug("BuildTests: got source SVN: $source->{svn}\n");
        Debug("BuildTests: got source SVN username: $source->{svn_username}\n");
        Debug("BuildTests: got source SVN password: $source->{svn_password}\n");
        Debug("BuildTests: got source SVN password_cache: $source->{svn_password_cache}\n");
        my ($srcdir, $r) =
            MTT::Files::svn_checkout($source->{svn}, $source->{svn_username}, $source->{svn_password}, $source->{svn_password_cache}, 1, 1);
        $config->{srcdir} = $srcdir;
    } elsif ($source->{copydir}) {
        Debug("BuildTests: got source tree: $source->{copydir}\n");
        $config->{srcdir} = 
            MTT::Files::copy_tree($source->{copydir}, 1);
    }
    chdir($config->{srcdir});
    $config->{srcdir} = cwd();

    # What to do with stdout/stderr?
    my $tmp;
    $tmp = Logical($ini, $section, "save_stdout_on_success");
    $config->{save_stdout_on_success} = $tmp
        if (defined($tmp));
    $tmp = Logical($ini, $section, "separate_stdout_stderr");
    $config->{separate_stdout_stderr} = $tmp
        if (defined($tmp));
    $tmp = Value($ini, $section, "stderr_save_lines");
    $config->{stderr_save_lines} = $tmp
        if (defined($tmp));
    $tmp = Value($ini, $section, "stdout_save_lines");
    $config->{stdout_save_lines} = $tmp
        if (defined($tmp));

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
            $ENV{LD_LIBRARY_PATH} = "$mpi_install->{libdir}:" . $ENV{LD_LIBRARY_PATH};
        } else {
            $ENV{LD_LIBRARY_PATH} = $mpi_install->{libdir};
        }
    }

    # Process setenv, unsetenv, prepend-path, and append-path -- for
    # both the MPI that we're building with and the section of the ini
    # file that we're building.
    my @save_env;
    ProcessEnvKeys($mpi_install, \@save_env);
    $config->{setenv} = Value($ini, $section, "setenv");
    $config->{unsetenv} = Value($ini, $section, "unsetenv");
    $config->{prepend_path} = Value($ini, $section, "prepend_path");
    $config->{append_path} = Value($ini, $section, "append_path");
    ProcessEnvKeys($config, \@save_env);

    # Run the module
    my $start = timegm(gmtime());
    my $ret = MTT::Module::Run("MTT::Test::Build::$config->{build_module}",
                               "Build", $ini, $mpi_install, $config);
    my $stop = timegm(gmtime());
            
    # Analyze the return
    if ($ret) {

        $ret->{section_name} = $config->{section_name};
        $ret->{pretty_name} = $config->{pretty_name};
        $ret->{setenv} = $config->{setenv};
        $ret->{unsetenv} = $config->{unsetenv};
        $ret->{prepend_path} = $config->{prepend_path};
        $ret->{append_path} = $config->{append_path};
        $ret->{srcdir} = $config->{srcdir};
        $ret->{mpi_name} = $mpi_install->{mpi_name};
        $ret->{mpi_get_section_name} = $mpi_install->{mpi_get_section_name};
        $ret->{mpi_get_pretty_name} = $mpi_install->{mpi_get_pretty_name};
        $ret->{mpi_install_section_name} = $mpi_install->{section_name};
        $ret->{mpi_install_pretty_name} = $mpi_install->{pretty_name};
        $ret->{mpi_version} = $mpi_install->{mpi_version};
        $ret->{timestamp} = timegm(gmtime());

        my $perfbase_xml = Value($ini, $section, "perfbase_xml");
        $perfbase_xml = "inp_test_build.xml"
            if (!$perfbase_xml);
        $ret->{success} = 0
            if (!defined($ret->{success}));
        
        # Save the results in an ini file
        Debug("Writing built file: $config->{srcdir}/$built_file\n");
        WriteINI("$build_section_dir/$built_file",
                 $built_section, $ret);
                
        # Send the results back to the reporter
        my $report = {
            phase => "Test Build",
            start_timestamp => $start,
            stop_timestamp => $stop,
            success => $ret->{success},
            compiler_name => $mpi_install->{compiler_name},
            compiler_version => $mpi_install->{compiler_version},
            result_message => $ret->{result_message},
            environment => "filled in below",
            stdout => "filled in below",
            stderr => "filled in below",
            perfbase_xml => $perfbase_xml,

            test_build_section_name => $config->{section_name},
            test_build_pretty_name => $pretty_name,

            mpi_name => $mpi_install->{mpi_name},
            mpi_get_section_name => $mpi_install->{mpi_get_section_name},
            mpi_get_pretty_name => $mpi_install->{mpi_get_pretty_name},
            mpi_install_section_name => $mpi_install->{section_name},
            mpi_install_pretty_name => $mpi_install->{pretty_name},
            mpi_version => $mpi_install->{mpi_version},
        };

        # See if we want to save the stdout
        my $want_save = 1;
        if (1 == $ret->{success}) {
            if (!$config->{save_stdout_on_success}) {
                $want_save = 0;
            }
        } elsif (!$ret->{stdout}) {
            $want_save = 0;
        }

        # If we want to save, see how many lines we want to save
        if ($want_save) {
            if ($config->{stdout_save_lines} == -1) {
                $report->{stdout} = "$ret->{stdout}\n";
            } elsif ($config->{stdout_save_lines} == 0) {
                delete $report->{stdout};
            } else {
                if ($ret->{stdout} =~ m/((.*\n){$config->{stdout_save_lines}})$/) {
                    $report->{stdout} = $1;
                } else {
                    # There were less lines available than we asked
                    # for, so just take them all
                    $report->{stdout} = $ret->{stdout};
                }
            }
        } else {
            delete $report->{stdout};
        }

        # Always fill in the last bunch of lines for stderr
        if ($ret->{stderr}) {
            if ($config->{stderr_save_lines} == -1) {
                $report->{stderr} = "$ret->{stderr}\n";
            } elsif ($config->{stderr_save_lines} == 0) {
                delete $report->{stderr};
            } else {
                if ($ret->{stderr} =~ m/((.*\n){$config->{stderr_save_lines}})$/) {
                    $report->{stderr} = $1;
                } else {
                    # There were less lines available than we asked
                    # for, so just take them all
                    $report->{stderr} = $ret->{stderr};
                }
            }
        } else {
            delete $report->{stderr};
        }

        # Did we have any environment?
        $report->{environment} = undef;
        foreach my $e (@save_env) {
            $report->{environment} .= "$e\n";
        }
        # Delete keys with empty values
        foreach my $k (keys(%$report)) {
            if ($report->{$k} eq "") {
                delete $report->{$k};
            }
        }
        
        # Submit it!
        MTT::Reporter::Submit("Test Build", $section, $report);

        # It's been saved to a file, so reclaim potentially a good
        # chunk of memory...
        delete $ret->{stdout};
        delete $ret->{stderr};
        
        # If it was a good build, save it
        if (1 == $ret->{success}) {
            $MTT::Test::builds->{$mpi_install->{mpi_get_section_name}}->{$mpi_install->{section_name}}->{$section} = $ret;
            MTT::Test::SaveBuilds($build_base);
        }
    }
}

1;
