#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2008 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

########################################################################
# MPI get phase
########################################################################

# The output of this phase is the @MTT::MPI::sources array of
# structs, each with the following members:

# section_name (IN) => name of this MPI's [section] in the INI file
# version (OUT) => string version of the MPI
# tarball (OUT) => absolute pathname of the tarball
# svn (OUT) => url of SVN repository to checkout
# directory (OUT) => root of directory tree to copy
# prepare_for_build (OUT) => the name of the routine to invoke to take
#     the sources and prepare them for building in another directory

# One of tarball, svn, or directory must be supplied.

########################################################################

package MTT::MPI::Get;

use strict;
use POSIX qw(strftime);
use File::Basename;
use Time::Local;
use MTT::DoCommand;
use MTT::FindProgram;
use MTT::Messages;
use MTT::Files;
use MTT::INI;
use MTT::MPI;
use MTT::Values;
use MTT::Util;
use MTT::EnvModule;
use Data::Dumper;

# What we call this phase
my $phase_name = "MPI Get";

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $source_dir, $force) = @_;

    Verbose("*** $phase_name phase starting\n");

    # Save the environment
    my %ENV_SAVE = %ENV;

    # Go through all the sections in the ini file looking for section
    # names that begin with "MPI Get:"
    MTT::DoCommand::Chdir($source_dir);
    foreach my $section ($ini->Sections()) {
        # See if we're supposed to terminate
        last
            if (MTT::Util::time_to_terminate());

        if ($section =~ /^\s*mpi get:/) {
            # Make the active INI section name known
            $MTT::Globals::Values->{active_section} = $section;

            my $simple_section = $section;
            $simple_section =~ s/^\s*mpi get:\s*//;
            Verbose(">> $phase_name: [$section]\n");
            $MTT::Globals::Values->{active_phase} = $phase_name;
            $MTT::Globals::Internals->{mpi_get_name} = $simple_section;
            _do_get($section, $ini, $source_dir, $force);
            delete $MTT::Globals::Internals->{mpi_get_name};
            %ENV = %ENV_SAVE;
        }
    }

    Verbose("*** $phase_name phase complete\n");
}

#--------------------------------------------------------------------------

# Get a new get
sub _do_get {
    my ($section, $ini, $source_dir, $force) = @_;

    Verbose("   Checking for new MPI sources...\n");

    # Simple section name
    my $simple_section = GetSimpleSection($section);

    my $module = Value($ini, $section, "module");
    if (!$module) {
        Warning("No module defined for $phase_name [$section]; skipping\n");
        return;
    }
    my $mpi_details = Value($ini, $section, "mpi_details");
    if (!$mpi_details) {
        Warning("No mpi_details defined for $phase_name [$section]; skipping\n");
        return;
    }

    my $skip_section = Value($ini, $section, "skip_section");
    if ($skip_section) {
        Verbose("skip_section evaluates to $skip_section [$simple_section]; skipping\n");
        return;
    }

    # Load any environment modules?
    my $config;
    my @env_modules;
    $config->{env_modules} = Value($ini, $section, "env_module");
    if ($config->{env_modules}) {
        @env_modules = MTT::Util::split_comma_list($config->{env_modules});
        MTT::EnvModule::unload(@env_modules);
        MTT::EnvModule::load(@env_modules);
    }

    # Process setenv, unsetenv, prepend_path, and
    # append_path
    $config->{setenv} = Value($ini, $section, "setenv");
    $config->{unsetenv} = Value($ini, $section, "unsetenv");
    $config->{prepend_path} = Value($ini, $section, "prepend_path");
    $config->{append_path} = Value($ini, $section, "append_path");
    my @save_env;
    ProcessEnvKeys($config, \@save_env);

    # Make a directory just for this section
    MTT::DoCommand::Chdir($source_dir);
    my $section_dir = MTT::Files::make_safe_filename($section);
    $section_dir = MTT::Files::mkdir($section_dir);
    MTT::DoCommand::Chdir($section_dir);

    # Run the module
    my $ret = MTT::Module::Run("MTT::MPI::Get::$module",
                               "Get", $ini, $section, $force);
    
    # Unload any loaded environment modules
    if ($#env_modules >= 0) {
        MTT::EnvModule::unload(@env_modules);
    }

    # Did we get a source tree back?
    if (MTT::Values::PASS == $ret->{test_result}) {
        if ($ret->{have_new}) {

            Verbose("   Got new MPI sources: version $ret->{version}\n");

            # Save other values from the section
            $ret->{full_section_name} = $section;
            $ret->{simple_section_name} = $simple_section;
            $ret->{mpi_details} = $mpi_details;
            $ret->{module_name} = "MTT::MPI::Get::$module";
            $ret->{start_timestamp} = timegm(gmtime());
            foreach my $k (qw/env_modules setenv unsetenv prepend_path append_path/) {
                $ret->{$k} = $config->{$k}
                    if (defined($config->{$k}));
            }
            $ret->{refcount} = 0;
            
            # Add this into the $MPI::sources hash
            $MTT::MPI::sources->{$simple_section}->{$ret->{version}} = $ret;

            # Save the data file recording all the sources
            MTT::MPI::SaveSources($source_dir);
        } else {
            Verbose("   No new MPI sources\n");
        }
    } else {
        Verbose("   Failed to get new MPI sources: $ret->{result_message}\n");
    }
}

1;
