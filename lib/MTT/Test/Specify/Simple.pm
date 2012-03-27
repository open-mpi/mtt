#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2008 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Specify::Simple;

use strict;
use MTT::Messages;
use MTT::Values;
use MTT::Defaults;
use MTT::FindProgram;
use MTT::Util;
use Data::Dumper;

#--------------------------------------------------------------------------

sub Specify {
    my ($ini, $section, $build_dir, $mpi_install, $config) = @_;
    my $ret;

    $ret->{test_result} = 0;

    # Loop through all the parameters from the INI file and put them
    # in a hash that is easy for us to traverse
    my $params;
    foreach my $field ($ini->Parameters($section)) {
        if ($field =~ /^simple_/) {
            $field =~ m/^simple_(\w+):(.+)/;
            $params->{$1}->{$2} = $ini->val($section, $field);
        }
    }

    # First, go through an make lists of the executables and argv
    foreach my $group (keys %$params) {
        # Look up the tests value.  Skip it if we didn't get one for
        # this group.
        my $tests = $params->{$group}->{tests};
        if (!$tests) {
            Warning("No tests specified for group \"$group\" -- skipped\n");
            delete $params->{$group};
            next;
        }

        $params->{$group}->{tests} = 
            _split_and_arrayize($ini, $section, $tests);
        $params->{$group}->{argv} = 
            _split_and_arrayize($ini, $section, $params->{$group}->{argv});
    }

    # Now go through and see if any of the tests are marked as
    # "exclusive".
    my $ex = 0;
    foreach my $group (keys %$params) {
        # If this group is marked as exclusive, remove each of its
        # tests from all other groups
        if ($params->{$group}->{exclusive}) {
            $ex = 1;
            last;
        }
    }

    # If there are exclusive tests, then explode the params list:
    # expand all test and argv arrays so that every entry in $params
    # has a test array size of 1 and an argv array size of 0 or 1.
    if ($ex) {
        my $newparams;
        foreach my $g (keys %$params) {
            # Make a dummy new entry that's a copy of the original one.
            my $template;
            %{$template} = %{$params->{$g}};

            # Zero out the tests and argv array in the template
            $template->{tests} = ();
            $template->{argv} = ();

            # Now explode the tests/argv combinations
            my $i = 0;
            my $tests = get_array_ref($params->{$g}->{tests});
            foreach my $t (@$tests) {
                my $entry;
                
                my $argv = get_array_ref($params->{$g}->{argv});

                if (defined($argv)) {
                    foreach my $a (@$argv) {
                        # Make a new copy of the template and replace
                        # both the test and argv
                        %{$entry} = %{$template};
                        @{$entry->{tests}} = ( $t );
                        $entry->{argv} = $a;
                        %{$newparams->{"$g-$i"}} = %{$entry};
                        ++$i;
                    }
                } else {
                    # Make a new copy of the template and replace the
                    # test (there's no argv)
                    %{$entry} = %{$template};
                    @{$entry->{tests}} = ( $t );
                    %{$newparams->{"$g-$i"}} = %{$entry};
                    ++$i;
                }
            }
        }

        # Now go through all exploded list and look for exclusive
        # duplicates.  A duplicate is when two entries have the same
        # ($test, $argv) tuple (i.e., the same command line).  Note
        # that exclusivity is based on priority ordering -- if a test
        # is in multiple exclusive groups, it will remain in the group
        # with the highest exclusivity value.  If a test is in
        # multiple groups with the same highest exclusivity value,
        # it's undefined which group it ends up in.
        $params = $newparams;
        foreach my $g1 (keys %$params) {
            next
                if (!exists($params->{$g1}->{exclusive}));

            my $e1 = MTT::Values::EvaluateString($params->{$g1}->{exclusive},
                                                $ini, $section);

            my @to_delete;
            foreach my $g2 (keys %$params) {
                # If $g1 and $g2 are the same, skip
                next
                    if ($g1 eq $g2);

                # Check the exclusivity value
                if (exists($params->{$g2}->{exclusive})) {
                    my $e2 = MTT::Values::EvaluateString($params->{$g2}->{exclusive},
                                                         $ini, $section);
                    next
                        if ($e2 > $e1);
                }

                # If we get here, then $g1 has precedence over $g2.
                # See if the ($test, $argv) matches between $g1 and
                # $g2.
                my $t1 = get_array_ref($params->{$g1}->{tests});
                my $a1 = get_array_ref($params->{$g1}->{argv});
                my $t2 = get_array_ref($params->{$g2}->{tests});
                my $a2 = get_array_ref($params->{$g2}->{argv});

                next
                    if (${$t1}[0] ne ${$t2}[0]);
                next
                    if (${$a1}[0] ne ${$a2}[0]);

                # Mark $g2 for deletion (we can't delete it while
                # we're looping $g2 over the keys in %$params)
                push(@to_delete, $g2);
            }

            # Did we find anything to delete?
            foreach my $d (@to_delete) {
                delete($params->{$d});
            }
        }
    }

    # After we've performed the exclusivity filter, if the tests
    # are marked as "do_not_run", then delete this group (it's a
    # way of specifying tests to *not* run).
    my @to_delete;
    foreach my $g (keys %$params) {
        if (defined($params->{$g}->{do_not_run})) {
            my $e = MTT::Values::EvaluateString($params->{$g}->{do_not_run},
                                                $ini, $section);
            push(@to_delete, $g)
                if ($e);
        }
    }
    foreach my $d (@to_delete) {
        delete($params->{$d});
    }

    # Now go through those groups and make the final list of tests to pass
    # upwards
    foreach my $group (keys %$params) {
        # Go through the list of tests and create an entry for each
        foreach my $t (@{$params->{$group}->{tests}}) {
            my $ok = 0;
            # If we can't find the file, see if it's in the path
            if ($MTT::DoCommand::no_execute) {
                $ok = 1;
            } elsif (! -f $t && FindProgram($t)) {
                $ok = 1;
            } elsif (-x $t) {
                $ok = 1;
            }
            # If it's good, add a hash with all the values into the
            # list of tests
            if ($ok) {
                my $one;
                # Do a deep copy of the defaults
                %{$one} = %{$config};

                # Set the test name
                $one->{executable} = $t;
                Debug("   Adding test: $t (group: $group)\n");

                # Set all the other names that were specified for this
                # group
                foreach my $key (keys %{$params->{$group}}) {
                    next
                        if ($key eq "tests");
                    if ($key =~ /^mpi_details:/) {
                        $key =~ m/^mpi_details:(.+)/;
                        $one->{mpi_details}->{$1} = $params->{$group}->{$key};
                    } else {
                        $one->{$key} = $params->{$group}->{$key};
                    }
                }

                # Save it on the final list of tests
                push(@{$ret->{tests}}, $one);
            }
        }
    }

    # All done
    $ret->{test_result} = 1;
    return $ret;
} 

sub _split_and_arrayize {
    my ($ini, $section) = @_;
    shift;
    shift;

    my @ret;
    
    foreach my $str (@_) {
        # Evaluate the string to get the full list of values
        my $str = MTT::Values::EvaluateString($str, $ini, $section);

        # Split it up if it's a string
        if (ref($str) eq "") {
            my @arr = split(/(?:\s+,\s+|\s+,|,\s+|,+|\s+)/, $str);
            foreach my $a (@arr) {
                push(@ret, $a);
            }
        } else {
            foreach my $s (@$str) {
                push(@ret, $s);
            }
        }
    }

    return \@ret;
}

1;
