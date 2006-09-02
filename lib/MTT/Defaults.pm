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

package MTT::Defaults;

use strict;

#--------------------------------------------------------------------------
# These values can be configured per site
#--------------------------------------------------------------------------

# System configuration
our $System_config = {
    source_subdir => "sources",
    install_subdir => "installs",

    http_agents => "wget lynx curl",

    known_compiler_names => "gnu pgi ibm intel kai absoft pathscale sun none",
};

# User-defined configuration
our $User_config = {
    save_successful => 1,
    save_failures => 3,
};

# MPI install phase
our $MPI_install = {
    perfbase_xml => "inp_mpi_install.xml",
    vpath_mode => "none",
    make_all_arguments => "",
    configure_arguments => "",
    save_stdout_on_success => 0,
    merge_stdout_stderr => 0,
    stdout_save_lines => 1000,
    stderr_save_lines => 1000,
    make_check => 0,

};

# Test build phase
our $Test_build = {
    perfbase_xml => "inp_test_build.xml",
    mpi_install => "all",
    save_stdout_on_success => 0,
    merge_stdout_stderr => 1,
    stdout_save_lines => 1000,
    stderr_save_lines => 1000,
};

# Test run phase
our $Test_run = {
    perfbase_xml => "inp_test_run_correctness.xml",
    argv => "",
    np => "&env_max_np()",
    np_ok => 1,
    pass => "&eq(&test_exit_status(), 0)",
    timeout => 30,

    save_stdout_on_pass => 0,
    merge_stdout_stderr => 1,
    stdout_save_lines => 1000,
    stderr_save_lines => 1000,
};

1;
