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

package MTT::Constants;

use strict;

#--------------------------------------------------------------------------
# These values can be configured per site
#--------------------------------------------------------------------------

# Subdirectory off $scratch where [downloaded / not-expanded] MPI
# sources are kept
our $source_subdir = "sources";

# Subdirectory off $scratch where MPI installations and test suite
# builds are kept
our $install_subdir = "installs";

# List of programs that may be used to download files
our @http_agents = qw(wget lynx curl);

#--------------------------------------------------------------------------
# These values are global and should not be modified for consistency
# with the centralized database (someday these values will be pulled
# down from the database instead of hard-coded here)
#--------------------------------------------------------------------------

# How many lines of stderr/stdout to show upon error (i.e., report the
# last $error_lines of the output) when installing an MPI.
our $error_lines_mpi_install = 100;

# How many lines of stderr/stdout to show upon error (i.e., report the
# last $error_lines of the output) when building a test suite.
our $error_lines_test_build = 100;

# Known compiler suite names.  These are the only ones that can 
our @known_compiler_names = qw(gnu pgi intel kai absoft pathscale none);

