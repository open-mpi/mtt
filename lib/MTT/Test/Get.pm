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

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $source_dir, $force) = @_;

    Verbose("*** Test get phase starting\n");

    # Go through all the sections in the ini file looking for section
    # names that begin with "Test Get:"
    MTT::DoCommand::Chdir($source_dir);
    foreach my $section ($ini->Sections()) {
        if ($section =~ /^\s*test get:/) {
            Verbose(">> Test get: [$section]\n");
            _do_get($section, $ini, $source_dir, $force);
        }
    }

    Verbose("*** Test get phase complete\n");
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
    
    # Make a directory just for this section
    MTT::DoCommand::Chdir($source_dir);
    my $section_dir = MTT::Files::make_safe_filename($section);
    $section_dir = MTT::Files::mkdir($section_dir);
    MTT::DoCommand::Chdir($section_dir);

    # Run the module
    my $ret = MTT::Module::Run("MTT::Test::Get::$module",
                               "Get", $ini, $section, $force);
    
    # Did we get a source tree back?
    if ($ret->{test_result}) {
        if ($ret->{have_new}) {

            Verbose("   Got new test sources\n");

            # Save other values from the section
            $ret->{full_section_name} = $section;
            $ret->{simple_section_name} = $simple_section;
            $ret->{module_name} = "MTT::Test::Get::$module";
            $ret->{start_timestamp} = timegm(gmtime());
            $ret->{refcount} = 0;

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
