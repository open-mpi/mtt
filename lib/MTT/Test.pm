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

package MTT::Test;

use strict;
use MTT::Test::Get;
use MTT::Test::Build;
use MTT::Test::Run;
use XML::Simple;
use Data::Dumper;

#--------------------------------------------------------------------------

# Exported sources tests handle
our $sources;

# Exported build tests handle
our $builds;

# Exported run tests handle
our $runs;

#--------------------------------------------------------------------------

# Filename where list of test sources information is kept
my $sources_data_filename = "test_sources.xml";

# XML options for the test builds
my $sources_xs;

# Filename where list of test build information is kept
my $builds_data_filename = "test_builds.xml";

# XML options for the test builds
my $builds_xs;

# Filename where list of test run information is kept
my $runs_data_filename = "test_runs.xml";

# XML options for the test runs
my $runs_xs;

#--------------------------------------------------------------------------

# This function exists solely so that we don't have to invoke
# MTT::Test::Get::Get in the top level
sub Get {
    return MTT::Test::Get::Get(@_);
}

#--------------------------------------------------------------------------

# This function exists solely so that we don't have to invoke
# MTT::Test::Build::Build in the top level
sub Build {
    return MTT::Test::Build::Build(@_);
}

#--------------------------------------------------------------------------

# This function exists solely so that we don't have to invoke
# MTT::Test::Run::Run in the top level
sub Run {
    return MTT::Test::Run::Run(@_);
}

#--------------------------------------------------------------------------

sub _scrub {
    my $h = shift;

    foreach my $k (keys(%$h)) {
        if (ref($h->{$k}) eq "") {
            # Remove bad characters
            $h->{$k} =~ s/\000/<NULL>/g;
        } else {
            _scrub($h->{$k});
        }
    }
}

#--------------------------------------------------------------------------

sub _setup_sources_xml {
    $sources_xs = new XML::Simple(KeyAttr => { test_get => "simple_section_name",
                                           },
                                  ForceArray => [ "test_get", 
                                                  ],
                                  AttrIndent => 1,
                                  RootName => "test_sources",
                                  );
}

#--------------------------------------------------------------------------

sub LoadSources {
    my ($dir) = @_;

    # Explicitly delete anything that was there
    $MTT::Test::sources = undef;

    _setup_sources_xml()
        if (!$sources_xs);
    
    # If the file exists, read it in
    if (-f "$dir/$sources_data_filename") {
        my $in = $sources_xs->XMLin("$dir/$sources_data_filename");

        # Now transform this to the form suitable for
        # $MTT::Test::sources (see comment in SaveSources)

        # For each Test get section
        foreach my $test_get_key (keys(%{$in->{test_get}})) {
            my $test_get = $in->{test_get}->{$test_get_key};

            $MTT::Test::sources->{$test_get_key} = $test_get;
            $MTT::Test::sources->{$test_get_key}->{simple_section_name} = $test_get_key;
        }
    }
}

#--------------------------------------------------------------------------

sub SaveSources {
    my ($dir) = @_;

    _setup_sources_xml()
        if (!$sources_xs);

    # Transform $MTT::Test::sources to something XML::Simple can write
    # into valid XML (since our values can [and will] contain :'s,
    # which are the namespace identifiers in XML)
    my $transformed;

    # For each Test get section
    foreach my $test_get_key (keys(%$MTT::Test::sources)) {
        my $test_get = $MTT::Test::sources->{$test_get_key};

        # Deep copy and scrub
        my $h;
        %$h = %$test_get;
        _scrub($h);

        $transformed->{test_get}->{$test_get_key} = $h;
    }

    # Write out the file
    my $xml = $sources_xs->XMLout($transformed);
    my $file = "$dir/$sources_data_filename";
    open(FILE, ">$file.new");
    print FILE $xml;
    close(FILE);
    system("mv $file.new $file");
}

#--------------------------------------------------------------------------

sub _setup_builds_xml {
    $builds_xs = new XML::Simple(KeyAttr => { mpi_get => "simple_section_name",
                                              mpi_version => "version",
                                              mpi_install => "simple_section_name",
                                              test_build => "simple_section_name",
                                            },
                                   ForceArray => [ "mpi_get", 
                                                   "mpi_version",
                                                   "mpi_install",
                                                   "test_build",
                                                   ],
                                   AttrIndent => 1,
                                   RootName => "test_builds",
                                   );
}

#--------------------------------------------------------------------------

sub LoadBuilds {
    my ($dir) = @_;

    # Explicitly delete anything that was there
    $MTT::Test::builds = undef;

    _setup_builds_xml()
        if (!$builds_xs);
    
    # If the file exists, read it in
    if (-f "$dir/$builds_data_filename") {
        my $in = $builds_xs->XMLin("$dir/$builds_data_filename");

        # Now transform this to the form suitable for
        # $MTT::Test::builds (see comment in SaveSources).  Wow.
        # For each MPI get section
        foreach my $mpi_get_key (keys(%{$in->{mpi_get}})) {
            my $mpi_get = $in->{mpi_get}->{$mpi_get_key};

            # For each version of that MPI
            foreach my $mpi_version_key (keys(%{$mpi_get->{mpi_version}})) {
                my $mpi_version = $mpi_get->{mpi_version}->{$mpi_version_key};

                # For each MPI install section
                foreach my $mpi_install_key (keys(%{$mpi_version->{mpi_install}})) {
                    my $mpi_install = $mpi_version->{mpi_install}->{$mpi_install_key};
                    
                    # For each test build section
                    foreach my $test_build_key (keys(%{$mpi_install->{test_build}})) {
                        my $test_build = $mpi_install->{test_build}->{$test_build_key};
                        
                        $MTT::Test::builds->{$mpi_get_key}->{$mpi_version_key}->{$mpi_install_key}->{$test_build_key} = 
                            $in->{mpi_get}->{$mpi_get_key}->{mpi_version}->{$mpi_version_key}->{mpi_install}->{$mpi_install_key}->{test_build}->{$test_build_key};
                        $MTT::Test::builds->{$mpi_get_key}->{$mpi_version_key}->{$mpi_install_key}->{$test_build_key}->{simple_section_name} = $test_build_key;
                    }
                }
            }
        }
    }
}

#--------------------------------------------------------------------------

sub SaveBuilds {
    my ($dir) = @_;

    _setup_builds_xml()
        if (!$builds_xs);

    # Transform $MTT::Test::builds to something XML::Simple can write
    # into valid XML (see comment in SaveSources).  Wow.
    my $transformed;

    # For each MPI get section
    foreach my $mpi_get_key (keys(%{$MTT::Test::builds})) {
        my $mpi_get = $MTT::Test::builds->{$mpi_get_key};

        # For each version of that MPI
        foreach my $mpi_version_key (keys(%{$mpi_get})) {
            my $mpi_version = $mpi_get->{$mpi_version_key};
            
            # For each MPI install section
            foreach my $mpi_install_key (keys(%{$mpi_version})) {
                my $mpi_install = $mpi_version->{$mpi_install_key};
            
                # For each test build section
                foreach my $test_build_key (keys(%{$mpi_install})) {
                    my $test_build = $mpi_install->{$test_build_key};
                    
                    # Deep copy and scrub
                    my $h;
                    %$h = %$test_build;
                    _scrub($h);

                    $transformed->{mpi_get}->{$mpi_get_key}->{mpi_version}->{$mpi_version_key}->{mpi_install}->{$mpi_install_key}->{test_build}->{$test_build_key} = $h;
                }
            }
        }
    }

    # Write out the file
    my $xml = $builds_xs->XMLout($transformed);
    my $file = "$dir/$builds_data_filename";
    open(FILE, ">$file.new");
    print FILE $xml;
    close(FILE);
    system("mv $file.new $file");
}

#--------------------------------------------------------------------------

sub _setup_runs_xml {
    $runs_xs = new XML::Simple(KeyAttr => { mpi_get => "simple_section_name",
                                            mpi_version => "version",
                                            mpi_install => "simple_section_name",
                                            test_build => "simple_section_name",
                                            test_run => "simple_section_name",
                                            test_name => "name",
                                            test_np => "nprocs",
                                            test_cmd => "argv",
                                        },
                               ForceArray => [ "mpi_get", 
                                               "mpi_version",
                                               "mpi_install",
                                               "test_build",
                                               "test_run",
                                               "test_name",
                                               "test_np",
                                               "test_cmd",
                                               ],
                               AttrIndent => 1,
                               RootName => "test_runs",
                               );
}

#--------------------------------------------------------------------------

sub LoadRuns {
    my ($dir) = @_;

    # Explicitly delete anything that was there
    $MTT::Test::runs = undef;

    _setup_runs_xml()
        if (!$runs_xs);
    
    # If the file exists, read it in
    if (-f "$dir/$runs_data_filename") {
        my $in = $runs_xs->XMLin("$dir/$runs_data_filename");

        # Now transform this to the form suitable for
        # $MTT::Test::runs (see comment in SaveSources).  Wow.
        # For each MPI get section
        foreach my $mpi_get_key (keys(%{$in->{mpi_get}})) {
            my $mpi_get = $in->{mpi_get}->{$mpi_get_key};

            # For each MPI source
            foreach my $mpi_version_key (keys(%{$mpi_get->{mpi_version}})) {
                my $mpi_version = $mpi_get->{mpi_version}->{$mpi_version_key};

                # For each MPI install section
                foreach my $mpi_install_key (keys(%{$mpi_version->{mpi_install}})) {
                    my $mpi_install = $mpi_version->{mpi_install}->{$mpi_install_key};

                    # For each test build section
                    foreach my $test_build_key (keys(%{$mpi_install->{test_build}})) {
                        my $test_build = $mpi_install->{test_build}->{$test_build_key};
                        
                        # For each test run section
                        foreach my $test_run_key (keys(%{$test_build->{test_run}})) {
                            my $test_run = $test_build->{test_run}->{$test_run_key};
                            
                            # For each test name
                            foreach my $test_name_key (keys(%{$test_run->{test_name}})) {
                                my $test_name = $test_run->{test_name}->{$test_name_key};
                                
                                # For each np
                                foreach my $test_np_key (keys(%{$test_name->{test_np}})) {
                                    my $test_np = $test_name->{test_np}->{$test_np_key};
                                    
                                    # For each test command
                                    foreach my $test_cmd_key (keys(%{$test_np->{test_cmd}})) {
                                        my $test_cmd = $test_np->{test_cmd}->{$test_cmd_key};
                                        
                                        $MTT::Test::runs->{$mpi_get_key}->{$mpi_version_key}->{$mpi_install_key}->{$test_build_key}->{$test_run_key}->{$test_name_key}->{$test_np_key}->{$test_cmd_key} = 
                                            $in->{mpi_get}->{$mpi_get_key}->{mpi_version}->{$mpi_version_key}->{mpi_install}->{$mpi_install_key}->{test_build}->{$test_build_key}->{test_run}->{$test_run_key}->{test_name}->{$test_name_key}->{test_np}->{$test_np_key}->{test_cmd}->{$test_cmd_key};
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

#--------------------------------------------------------------------------

sub SaveRuns {
    my ($dir) = @_;

    _setup_runs_xml()
        if (!$runs_xs);

    # Transform $MTT::Test::runs to something XML::Simple can write
    # into valid XML (see comment in SaveSources).  Wow.
    my $transformed;

    # For each MPI get section
    foreach my $mpi_get_key (keys(%{$MTT::Test::runs})) {
        my $mpi_get = $MTT::Test::runs->{$mpi_get_key};

        # For each source of that MPI
        foreach my $mpi_version_key (keys(%{$mpi_get})) {
            my $mpi_version = $mpi_get->{$mpi_version_key};

            # For each MPI install section
            foreach my $mpi_install_key (keys(%{$mpi_version})) {
                my $mpi_install = $mpi_version->{$mpi_install_key};
                
                # For each test build section
                foreach my $test_build_key (keys(%{$mpi_install})) {
                    my $test_build = $mpi_install->{$test_build_key};
                    
                    # For each test run section
                    foreach my $test_run_key (keys(%{$test_build})) {
                        my $test_run = $test_build->{$test_run_key};
                        
                        # For each test name
                        foreach my $test_name_key (keys(%{$test_run})) {
                            my $test_name = $test_run->{$test_name_key};
                            
                            # For each np
                            foreach my $test_np_key (keys(%{$test_name})) {
                                my $test_np = $test_name->{$test_np_key};
                                
                                # For each cmd
                                foreach my $test_cmd_key (keys(%{$test_np})) {
                                    my $test_cmd = $test_np->{$test_cmd_key};
                                    
                                    # Deep copy and scrub
                                    my $h;
                                    %$h = %$test_cmd;
                                    _scrub($h);

                                    $transformed->{mpi_get}->{$mpi_get_key}->{mpi_version}->{$mpi_version_key}->{mpi_install}->{$mpi_install_key}->{test_build}->{$test_build_key}->{test_run}->{$test_run_key}->{test_name}->{$test_name_key}->{test_np}->{$test_np_key}->{test_cmd}->{$test_cmd_key} = $h;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    # Write out the file
    my $xml = $runs_xs->XMLout($transformed);
    my $file = "$dir/$runs_data_filename";
    open(FILE, ">$file.new");
    print FILE $xml;
    close(FILE);
    system("mv $file.new $file");
}

1;
