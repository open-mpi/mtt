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
use Cwd;
use POSIX qw(strftime);
use File::Basename;
use MTT::DoCommand;
use MTT::FindProgram;
use MTT::Messages;
use MTT::Files;
use MTT::INI;
use MTT::MPI;
use MTT::Constants;
use MTT::Values;
use Data::Dumper;

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $source_dir, $force) = @_;

    Verbose("*** MPI get phase starting\n");

    # Go through all the sections in the ini file looking for section
    # names that begin with "MPI Get:"
    chdir($source_dir);
    foreach my $section ($ini->Sections()) {
        if ($section =~ /^\s*mpi get:/) {
            Verbose(">> MPI sources: [$section]\n");
            my $skip = Logical($ini, $section, "skip");
            if ($skip) {
                Verbose("   Skipped\n");
            } else {
                _do_get($section, $ini, $source_dir, $force);
            }
        }
    }

    Verbose("*** MPI get phase complete\n");
}

#--------------------------------------------------------------------------

# Get a new get
sub _do_get {
    my ($section, $ini, $source_dir, $force) = @_;

    Verbose("   Checking for new MPI sources...\n");

    my $module = Value($ini, $section, "module");
    if (!$module) {
        Warning("No module defined for MPI get [$section]; skipping");
        return;
    }
    my $mpi_name = Value($ini, $section, "mpi_name");
    if (!$mpi_name) {
        Warning("No mpi_name defined for MPI get [$section]; skipping");
        return;
    }
    
    # Make a new unique ID
    my $unique_id = strftime("timestamp-%m%d%Y-%H%M%S", localtime);

    # Make a directory just for this section
    chdir($source_dir);
    my $section_dir = MTT::Files::make_safe_filename($section);
    $section_dir = MTT::Files::mkdir($section_dir);
    chdir($section_dir);

    # Run the module
    my $ret = MTT::Module::Run("MTT::MPI::Get::$module",
                               "Get", $ini, $section, $unique_id, $force);
    
    # Did we get a source tree back?
    if ($ret) {

        Verbose("   Got new MPI sources\n");

        # Save other values from the section
        $ret->{section_name} = $section;
        $ret->{mpi_name} = $mpi_name;
        $ret->{unique_id} = $unique_id
            if (!$ret->{unique_id});
        $ret->{module_name} = "MTT::MPI::Get::$module";

        # Add this into the $MPI::sources hash
        $MTT::MPI::sources->{$section}->{$ret->{unique_id}} = $ret;

        # Save the data file recording all the sources
        MTT::MPI::SaveSources($source_dir);
    } else {
        Verbose("   No new MPI sources\n");
    }
}

1;
