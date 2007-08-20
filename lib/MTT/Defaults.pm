#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2007 Cisco Systems, Inc.  All rights reserved.
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
    runs_data_subdir => "test_runs",
    
    http_agents => { 
        wget => { 
            command => "wget -nv \$url", 
            auth => "--user=\$username --password=\$password",
        },
        curl => {
            command => "curl -# -# \$url -o \$outfile",
            auth => "--user \$username:\$password",
        }
    },

    known_compiler_names => "gnu pgi ibm intel kai absoft pathscale sun none",
};

# User-defined configuration
our $User_config = {
    save_successful => 1,
    save_failures => 3,
};

# MPI install phase
our $MPI_install = {
    vpath_mode => "none",
    make_all_arguments => "",
    configure_arguments => "",
    save_stdout_on_success => 0,
    merge_stdout_stderr => 0,
    stdout_save_lines => 100,
    stderr_save_lines => 100,
    make_check => 0,

};

# Test build phase
our $Test_build = {
    mpi_install => "all",
    save_stdout_on_success => 0,
    merge_stdout_stderr => 1,
    stdout_save_lines => 100,
    stderr_save_lines => 100,
};

# Test specify phase
our $Test_specify = {
    pass => "&eq(&test_exit_status(), 0)",
    skipped => "&eq(&test_exit_status(), 77)",
    argv => "",
    np => "&env_max_procs()",
    np_ok => 1,
    timeout => 30,

    save_stdout_on_pass => 0,
    merge_stdout_stderr => 1,
    stdout_save_lines => 100,
    stderr_save_lines => 100,
};

1;
