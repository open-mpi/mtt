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
use File::Find;
use MTT::Files;
use MTT::Messages;
use MTT::DoCommand;
use MTT::Util;
use Data::Dumper;

#--------------------------------------------------------------------------

# Exported sources tests handle
our $sources;

# Exported build tests handle
our $builds;

# Exported run tests handle
our $runs;
our $runs_to_be_saved;

#--------------------------------------------------------------------------

# Filename extension for all the Dumper data files
my $data_filename_extension = "dump";

# Filename where list of test sources information is kept
my $sources_data_filename = "test_sources";

# Filename where list of test build information is kept
my $builds_data_filename = "test_builds";

# Subdir where test runs are kept
my $runs_subdir = "test_runs";

# Filename where list of test run information is kept
my $runs_data_filename = "test_runs.$data_filename_extension";

# Helper variable for when we're loading test run data
my $load_run_file_start_dir;

#--------------------------------------------------------------------------

sub LoadSources {
    my ($dir) = @_;

    # Explicitly delete anything that was there
    $MTT::Test::sources = undef;

    my @dumpfiles = glob("$dir/$sources_data_filename-*.$data_filename_extension");
    foreach my $dumpfile (@dumpfiles) {

        # If the file exists, read it in
        my $data;
        MTT::Files::load_dumpfile($dumpfile, \$data);
        $MTT::Test::sources = MTT::Util::merge_hashes($MTT::Test::sources, $data->{VAR1});
    }

    # Rebuild the refcounts
    foreach my $test_key (keys(%{$MTT::Test::sources})) {
        my $test = $MTT::Test::sources->{$test_key};

        # Set this refcount to 0, because no one is using it yet.
        $test->{refcount} = 0;
    }
}

#--------------------------------------------------------------------------

sub SaveSources {
    my ($dir, $name) = @_;

    # We write the entire Test::sources hash to file, even
    # though the filename indicates a single INI section
    # MTT::Util::hashes_merge will take care of duplicate
    # hash keys. The reason for splitting up the .dump files
    # is to keep them read and write safe across INI sections
    MTT::Files::save_dumpfile("$dir/$sources_data_filename-$name.$data_filename_extension", 
                              $MTT::Test::sources);
}

#--------------------------------------------------------------------------

sub LoadBuilds {
    my ($dir) = @_;

    # Explicitly delete anything that was there
    $MTT::Test::builds = undef;

    my @dumpfiles = glob("$dir/$builds_data_filename-*.$data_filename_extension");
    foreach my $dumpfile (@dumpfiles) {

        # If the file exists, read it in
        my $data;
        MTT::Files::load_dumpfile($dumpfile, \$data);
        $MTT::Test::builds = MTT::Util::merge_hashes($MTT::Test::builds, $data->{VAR1});
    }

    # Rebuild the refcounts
    foreach my $get_key (keys(%{$MTT::Test::builds})) {
        my $get = $MTT::Test::builds->{$get_key};

        foreach my $version_key (keys(%{$get})) {
            my $version = $get->{$version_key};

            foreach my $install_key (keys(%{$version})) {
                my $install = $version->{$install_key};

                foreach my $build_key (keys(%{$install})) {
                    my $build = $install->{$build_key};

                    # Set the refcount of this test build to 0.
                    $build->{refcount} = 0;

                    # Bump the refcount of the corresponding MPI install.
                    if (exists($MTT::MPI::installs->{$get_key}) &&
                        exists($MTT::MPI::installs->{$get_key}->{$version_key}) &&
                        exists($MTT::MPI::installs->{$get_key}->{$version_key}->{$install_key})) {
                        ++$MTT::MPI::installs->{$get_key}->{$version_key}->{$install_key}->{refcount};
                    }

                    # Bump the refcount of the corresponding Test get.
                    if (exists($MTT::Test::sources->{$build->{test_get_simple_section_name}})) {
                        ++$MTT::Test::sources->{$build->{test_get_simple_section_name}}->{refcount};
                    }
                }
            }
        }
    }
}

#--------------------------------------------------------------------------

sub SaveBuilds {
    my ($dir, $name) = @_;

    # We write the entire Test::builds hash to file, even
    # though the filename indicates a single INI section
    # MTT::Util::hashes_merge will take care of duplicate
    # hash keys. The reason for splitting up the .dump files
    # is to keep them read and write safe across INI sections
    MTT::Files::save_dumpfile("$dir/$builds_data_filename-$name.$data_filename_extension", 
                              $MTT::Test::builds);
}

#--------------------------------------------------------------------------

use Data::Dumper;
sub LoadRuns {
    my ($dir) = @_;

    # Explicitly delete anything that was there
    $MTT::Test::runs = undef;

    # See SaveRuns, below, for an explanation.  We traverse
    # directories looking for dump files and read them into the
    # appropriate section of the $MTT::Test::runs hash.

    $load_run_file_start_dir = $dir;
    find(\&load_run_file, $load_run_file_start_dir)
        if (-d $load_run_file_start_dir);

    # Rebuild the refcounts
    foreach my $get_key (keys(%{$MTT::Test::runs})) {
        my $get = $MTT::Test::runs->{$get_key};

        foreach my $version_key (keys(%{$get})) {
            my $version = $get->{$version_key};

            foreach my $install_key (keys(%{$version})) {
                my $install = $version->{$install_key};

                foreach my $build_key (keys(%{$install})) {
                    my $build = $install->{$build_key};

                    foreach my $run_key (keys(%{$build})) {
                        my $run = $build->{$run_key};

                        # Bump the refcount of the corresponding test build.
                        if (defined(MTT::Util::does_hash_key_exist($MTT::Test::builds,
                                                                    qw/$get_key 
                                                                       $version_key 
                                                                       $install_key 
                                                                       $build_key/))) {

                            ++$MTT::Test::builds->{$get_key}->{$version_key}->{$install_key}->{$build_key}->{refcount};
                        }
                    }
                }
            }
        }
    }
}

sub load_run_file {
    # We only want files named "np=[0-9+].$runs_data_filename"
    return 0
        if (! -f $_ || $_ !~ /np=[0-9]+.$runs_data_filename/);

    # Read in the file
    my $data;
    MTT::Files::load_dumpfile($File::Find::name, \$data);

    # Put the loaded data in the hash in the right place.  Per
    # SaveRuns(), below, we look at the key values in $data->{VAR1} to
    # know where to put $data->{VAR2} in the $MTT::Test::runs hash.
    my $str = "\$MTT::Test::runs";
    my $k = 1;
    do {
        $str .= "->{\"" . $data->{VAR1}->{$k} . "\"}";
        ++$k;
    } while (exists($data->{VAR1}->{$k}));
    $str .= " = \$data->{VAR2}";
    eval $str;

    # Note that no refcounts are needed here -- nothing uses test
    # runs.  But if they were, we could easily set this record's
    # refcount to 0 here.
}

#--------------------------------------------------------------------------

sub SaveRuns {
    my ($topdir) = @_;

    # Because test run data can get very, very large, we break it up
    # and store it in lots of smaller files so that we can write out
    # to disk in small portions.

    # Test runs are stored in the hash with this order of keys:

    # mpi_get_simple_section_name
    # mpi_version
    # mpi_install_simple_section_name
    # test_build_simple_section_name
    # test_run_simple_section_name
    # test_name
    # np
    # command

    # We save from test_name and down in a single file.

    # For each MPI get section
    foreach my $mpi_get_key (keys(%{$MTT::Test::runs_to_be_saved})) {
        my $mpi_get = $MTT::Test::runs_to_be_saved->{$mpi_get_key};

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

                            my @parts = ($runs_subdir, $mpi_get_key, $mpi_version_key, $mpi_install_key, $test_build_key, $test_run_key, $test_name_key);

                            my $dir = "$topdir";
                            foreach my $d (@parts) {
                                $dir .= "/" .
                                    MTT::Files::make_safe_filename($d);
                            }
                            MTT::Files::mkdir($dir);

                            # We need to save two items in test run
                            # data files -- the actual data and where
                            # it belongs in the $MTT::Test::runs hash.
                            my $hashname = {
                                1 => $mpi_get_key,
                                2 => $mpi_version_key,
                                3 => $mpi_install_key,
                                4 => $test_build_key,
                                5 => $test_run_key,
                                6 => $test_name_key,
                            };

                            # Save one file per np value; allows
                            # multiple np values to be running in
                            # simultaneous mtt invocations
                            foreach my $np_key (keys(%{$test_name})) {
                                $hashname->{7} = $np_key;
                                my $file = "$dir/np=$np_key.$runs_data_filename";
                                MTT::Files::save_dumpfile($file, $hashname, 
                                                          $test_name->{$np_key});
                            }
                        }
                    }
                }
            }
        }
    }

    # Explicitly reset the test runs to be saved
    $MTT::Test::runs_to_be_saved = undef;
}

#--------------------------------------------------------------------------

sub TrimRuns {
    my ($topdir) = @_;

    # See "SaveRuns", above, for an explanation of the storage format
    # of test runs.

    # In this subroutine, we traverse MTT::Test::runs looking for the
    # TRIM_KEY.  If we find it, remove the data from the hash and
    # chase down all the files that need to be deleted.  Deleting
    # files may also render parent directories empty (and grandparent
    # and great-grandparent and ...) which should therefore also be
    # deleted.

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

                        # Was this result marked "to be trimmed"?
                        if (defined($test_run->{$MTT::Trim::TRIM_KEY})) {

                            my @dirs;
                            my $last = $topdir;
                            my @parts = ($runs_subdir, $mpi_get_key, $mpi_version_key, $mpi_install_key, $test_build_key, $test_run_key);
                            foreach my $d (@parts) {
                                my $n = "$last/" . 
                                    MTT::Files::make_safe_filename($d);
                                push(@dirs, $n);
                                $last = $n;
                            }

                            for (my $i = $#dirs; $i >= 0; --$i) {
                                # If it's the first dir, cheat and
                                # just "rm -rf" the whole tree
                                # (because the first dir has dirs for
                                # all the individual tests under it,
                                # and we know we want to remove them
                                # all)
                                if ($#dirs == $i) {
                                    MTT::DoCommand::Cmd(0, "rm -rf $dirs[$i]");
                                } else {
                                    # Try to remove it; rmdir will
                                    # fail if the directory is not
                                    # empty.
                                    if (!rmdir($dirs[$i])) {
                                        last;
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

1;
