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
# Test get phase
########################################################################

package MTT::Test::Get;

use strict;
use Cwd;
use POSIX qw(strftime);
use File::Basename;
use Time::Local;
use MTT::DoCommand;
use MTT::FindProgram;
use MTT::Messages;
use MTT::Files;
use MTT::INI;
use MTT::Test;
use MTT::Values;
use Data::Dumper;

# What we call this phase
my $phase_name = "Test Get";

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $source_dir, $force) = @_;

    Verbose("*** $phase_name phase starting\n");

    # Go through all the sections in the ini file looking for section
    # names that begin with "Test Get:"
    MTT::DoCommand::Chdir($source_dir);
    foreach my $section ($ini->Sections()) {
        # See if we're supposed to terminate
        last
            if (MTT::Util::time_to_terminate());

        if ($section =~ /^\s*test get:/) {
            # Make the active INI section name known
            $MTT::Globals::Values->{active_section} = $section;

            my $simple_section = GetSimpleSection($section);
            Verbose(">> $phase_name: [$section]\n");
            $MTT::Globals::Values->{active_phase} = $phase_name;
            $MTT::Globals::Internals->{test_get_name} = $simple_section;
            _do_get($section, $ini, $source_dir, $force);
            delete $MTT::Globals::Internals->{test_get_name};
        }
    }

    Verbose("*** $phase_name phase complete\n");
}

#--------------------------------------------------------------------------

# Get a new get
sub _do_get {
    my ($section, $ini, $source_dir, $force) = @_;

    Verbose("   Checking for new test sources...\n");

    # Simple section name
    my $simple_section = $section;
    $simple_section =~ s/^\s*test get:\s*//;

    my $module = Value($ini, $section, "module");
    if (!$module) {
        Warning("No module defined for test get [$section]; skipping");
        return;
    }
    
    my $skip_section = Value($ini, $section, "skip_section");
    if ($skip_section) {
        Verbose("skip_section evaluates to $skip_section [$simple_section]; skipping\n");
        return;
    }

    # Process setenv, unsetenv, prepend_path, and
    # append_path
    my $config;
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
    my $ret = MTT::Module::Run("MTT::Test::Get::$module",
                               "Get", $ini, $section, $force);
    
    # Did we get a source tree back?
    if (MTT::Values::PASS == $ret->{test_result}) {
        if ($ret->{have_new}) {

            Verbose("   Got new test sources\n");

            # Save other values from the section
            $ret->{full_section_name} = $section;
            $ret->{simple_section_name} = $simple_section;
            $ret->{module_name} = "MTT::Test::Get::$module";
            $ret->{start_timestamp} = timegm(gmtime());
            $ret->{refcount} = 0;
            $ret->{setenv} = $config->{setenv};
            $ret->{unsetenv} = $config->{unsetenv};
            $ret->{prepend_path} = $config->{prepend_path};
            $ret->{append_path} = $config->{append_path};

            # Add this into the $Test::sources hash
            $MTT::Test::sources->{$simple_section} = $ret;
            
            # Save the data file recording all the sources
            MTT::Test::SaveSources($source_dir);
        } else {
            Verbose("   No new test sources\n");
        }
    } else {
        Verbose("   Failed to get new test sources: $ret->{result_message}\n");
    }
}

1;
