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

    # First, go through an make lists of the executables
    foreach my $group (keys %$params) {
        # Look up the tests value.  Skip it if we didn't get one for
        # this group.
        my $tests = $params->{$group}->{tests};
        if (!$tests) {
            Warning("No tests specified for group \"$group\" -- skipped\n");
            delete $params->{$group};
            next;
        }

        # Evaluate it to get the full list of tests
        $tests = MTT::Values::EvaluateString($tests, $ini, $section);

        # Split it up if it's a string
        if (ref($tests) eq "") {
            my @tests = split(/(?:\s+,\s+|\s+,|,\s+|,+|\s+)/, $tests);
            $tests = \@tests;
        }
        $params->{$group}->{tests} = $tests;
    }

    # Now go through and see if any of the tests are marked as
    # "exclusive".  If they are, remove those tests from all other
    # groups.  Note that exclusivity is based on priority ordering --
    # if a test is in multiple exclusive groups, it will remain in the
    # group with the highest exclusivity value.  If a test is in
    # multiple groups with the same highest exclusivity value, it's
    # undefined which group it ends up in.
    my @groups_to_delete;
    my @exclusive_groups;
    foreach my $group (keys %$params) {
        # If this group is marked as exclusive, remove each of its
        # tests from all other groups
        if ($params->{$group}->{exclusive}) {
            foreach my $t (@{$params->{$group}->{tests}}) {
                foreach my $g2 (keys %$params) {
                    # Skip this $g2 if: a) it's me, or b) that group
                    # has a higher exclusivity value than me (in which
                    # case, that group will come through and trim any
                    # overlapping tests from my group at some other
                    # point in this double loop).  Note that
                    # transitivity makes this all work.  Say there are
                    # 3 groups A,exclusive=10, B,exclusive=20,
                    # C,exclusive=30, and all of them contain the
                    # "foo" test. No matter which order the groups are
                    # checked, only C will end up with the "foo" test.
                    next 
                        if ($g2 eq $group ||
                            ($params->{$group}->{exclusive} < $params->{$g2}->{exclusive}));

                    my @to_delete;
                    my $i = 0;
                    foreach my $t2 (@{$params->{$g2}->{tests}}) {
                        if ($t eq $t2) {
                            push(@to_delete, $i);
                        }
                        ++$i;
                    }
                    foreach my $t2 (@to_delete) {
                        delete $params->{$g2}->{tests}[$t2];
                    }
                }
            }
        }

        # After we've performed the exclusivity filter, if the tests
        # are marked as "do_not_run", then delete this group (it's a
        # way of specifying tests to *not* run).  Don't delete them
        # now, it may (will?) screw up the outter loop's "foreach".
        if (defined($params->{$group}->{do_not_run})) {
            my $e = MTT::Values::EvaluateString($params->{$group}->{do_not_run},
                                                $ini, $section);
            push(@groups_to_delete, $group)
                if ($e);
        }
    }

    # Delete all the groups that were marked
    foreach my $t (@groups_to_delete) {
        delete $params->{$t};
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

1;
