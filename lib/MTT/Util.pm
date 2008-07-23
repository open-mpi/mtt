#!/usr/bin/env perl
#
# Copyright (c) 2007 Cisco, Inc.  All rights reserved.
# Copyright (c) 2007 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Util;

use strict;

use vars qw(@EXPORT);
use base qw(Exporter);
@EXPORT = qw(does_hash_key_exist
             split_comma_list
             find_terminate_file
             check_break_threshold
             is_valid_compiler_name
             is_valid_resource_manager_name
             is_valid_network_name
             is_valid_in_array
             delete_duplicates_from_array
             delete_matches_from_array
             parse_time_to_seconds
             get_array_ref
);

use Cwd;
use MTT::Globals;
use MTT::Messages;
use MTT::Values;
use Data::Dumper;
use Filesys::DiskFree;

#--------------------------------------------------------------------------

# Wow, Perl sucks sometimes -- you
# can't check for the entire thing because the very act of
# checking will bring all the intermediary hash levels into
# existence if they didn't already exist.
sub does_hash_key_exist {
    my $hash = shift;
    my $key = shift;
    while (defined($key) ) {
        return undef
            if (!exists($hash->{$key}));
        $hash = $hash->{$key};
        $key = shift;
    }
    return $hash;
}

#--------------------------------------------------------------------------

sub split_comma_list {
    my $str = shift;
    my @vals = split(/(?:\s+,\s+|\s+,|,\s+|,+)/, $str);
    my @ret;
    foreach my $v (@vals) {
        push(@ret, $v)
            if (length($v) > 0);
    }
    return @ret;
}

#--------------------------------------------------------------------------

my @_terminate_files;
my @_pause_files;
my $df_handle;
sub time_to_terminate {
    # If we previously found a terminate file, just return
    return 1
        if ($MTT::Globals::Values->{time_to_terminate});

    # If we have not yet filled in the @_terminate_files and
    # @_pause_files arrays, do so
    if (-1 == $#_terminate_files) {
        my $files = $MTT::Globals::Values->{terminate_files};
        if (defined($files) && $files) {
            foreach my $f (@$files) {
                push(@_terminate_files, MTT::Values::EvaluateString($f));
            }
        }

        $files = $MTT::Globals::Values->{pause_files};
        if (defined($files) && $files) {
            foreach my $f (@$files) {
                push(@_pause_files, MTT::Values::EvaluateString($f));
            }
        }

        # Setup min_disk_free to be a number of bytes
        $df_handle = new Filesys::DiskFree;
        if ($MTT::Globals::Values->{min_disk_free} =~ m/([0-9]{1,2})\%/) {
            $df_handle->df();
            my $val = $1;
            $val /= 100.0;
            $val *= $df_handle->total(cwd());
            $val = int($val);
            $MTT::Globals::Values->{min_disk_free} = $val;
        }
    }

    # Check to see if any of the files exist
    foreach my $f (@_terminate_files) {
        if (-f $f) {
            Verbose("--> Found terminate file: $f\n");
            Verbose("    Exiting...\n");
            $MTT::Globals::Values->{time_to_terminate} = 1;
            return 1;
        }
    }

    # If we find a pause file, sleep and see if it disappears.  If it
    # does disappear, do one more loop over all pause files just to
    # see if anyother pause file appeared.
    my $found;
    do {
        $found = 0;
        foreach my $f (@_pause_files) {
            if (-f $f) {
                Verbose("--> Found pause file: $f\n");
                $found = 1;
                while (1) {
                    my $now = localtime;
                    Verbose("    Sleeping for 30 seconds ($now)...\n");
                    sleep(30);
                    last 
                        if (! -f $f);
                }
                last;
            }
        }
    } while ($found == 1);

    # Check the disk space remaining
    if ($MTT::Globals::Values->{min_disk_free} > 0) {
        my $c = getcwd();
        $df_handle->df();
        if ($df_handle->avail($c) < 
            $MTT::Globals::Values->{min_disk_free}) {
            Warning("Disk free is less than minimum (" . 
                    $df_handle->avail($c) .
                    " bytes < $MTT::Globals::Values->{min_disk_free} bytes)\n");
            Warning("Waiting for up to $MTT::Globals::Values->{min_disk_free_wait} minutes to see if the situation resolves itself\n")
                if ($MTT::Globals::Values->{min_disk_free_wait} > 0);

            my $i = 0;
            while ($i < 2 * $MTT::Globals::Values->{min_disk_free_wait}) {
                sleep(30);
                $df_handle->df();
                if ($df_handle->avail($c) >
                    $MTT::Globals::Values->{min_disk_free}) {
                    last;
                }
                ++$i;
            }
            # If we reach an hour without more disk, then abort
            if ($i >= 2 * $MTT::Globals::Values->{min_disk_free_wait}) {
                Warning("Still not enough disk space available\n");
                Warning("Exiting...\n");
                $MTT::Globals::Values->{time_to_terminate} = 1;
                return 1;
            }
        }
    }

    # Ok to keep running; return false
    return 0;
}

# Return true if any of the result types have broken
# a threshold
sub check_break_threshold {
    my ($count, $threshold, $total) = @_;

    foreach my $result (keys %$threshold) {
        my $result_label = $MTT::Values::result_messages->{$result};
        my $per = sprintf("%d%%", $threshold->{$result} * 100);

        if (($count->{$result} / $total) > $threshold->{$result}) {
            Verbose("--> Threshold ($per) exceeded for \"$result_label\": $count->{$result} out of $total.\n");
            return 1;
        }
    }
    return 0;
}

#--------------------------------------------------------------------------1

sub is_valid_compiler_name {
    my ($section, $compiler) = @_;

    my $known_compiler_names = $MTT::Defaults::System_config->{known_compiler_names};
    my $ret = is_valid_in_array($section, $compiler, "compiler", $known_compiler_names);

    # Warn user if they use a compiler MTT does not recognize. This is an
    # attempt to standardize the compiler names stored in the database.
    if (!$ret) {
        my $known_compilers_pretty;
        my $str = "\n\t * ";
        my $known_compilers_pretty = $str . join($str, @$known_compiler_names);
        Warning("'$compiler' is not a valid compiler name. Please set the compiler_name parameter to one " .
                    "of the following: $known_compilers_pretty\n");
    }

    return $ret;
}

#--------------------------------------------------------------------------1

sub is_valid_resource_manager_name {
    my ($rm) = @_;
    return is_valid_in_array(undef, $rm, "resource manager",
                             $MTT::Defaults::System_config->{known_resource_manager_names});
}

#--------------------------------------------------------------------------1

sub is_valid_network_name {
    my ($network) = @_;
    return is_valid_in_array(undef, $network, "network",
                             $MTT::Defaults::System_config->{known_network_names});
}

#--------------------------------------------------------------------------1

sub is_valid_in_array {
    my ($section, $val, $label, $arr) = @_;

    return 0
        if (!defined($val));

    my $list = join(' ', @{$arr});
    if ($list !~ /$val/) {
        if (defined($section)) {
            Warning("Unrecognized $label name in [$section] ($val); the only permitted names are: \"$list\"; skipped\n");
        } else {
            Warning("Unrecognized $label name ($val); the only permitted names are: \"$list\"; skipped\n");
        }
        return 0;
    }
    
    # Yep; it's valid
    return 1;
}

#--------------------------------------------------------------------------

sub delete_duplicates_from_array {
    my @arr = @_;

    my @ret;
    my %hash;
    foreach my $elem (@arr) {
        $hash{$elem} = 1;
    }
    @ret = keys %hash;

    return @ret;
}

# Arguments:
# 1. Array
# 2. Pattern to match against
sub delete_matches_from_array {
    my (@arr) = @_;
    my $pattern = pop @arr;

    my @ret;
    foreach my $elem (@arr) {
        if ($elem !~ /$pattern/) { 
            push(@ret, $elem);
        }
    }

    return @ret;
}

#--------------------------------------------------------------------------

# Convert a time string ([HH:[MM:]]SS] to a total number of seconds
sub parse_time_to_seconds {
    my $str = shift;

    if ($str =~ m/^\s*(\d+):(\d+):(\d+)\s*$/) {
        my $ret = ($1 * 3600) + ($2 * 60) + $3;
        Debug("Time $str = $ret seconds\n");
        return $ret;
    } elsif ($str =~ m/^\s*(\d+):(\d+)\s*$/) {
        my $ret = ($1 * 60) + $2;
        Debug("Time $str = $ret seconds\n");
        return $ret;
    } elsif ($str =~ m/^\s*(\d+)\s*$/) {
        my $ret = $1;
        Debug("Time $str = $ret seconds\n");
        return $ret;
    } elsif (!defined($str) || $str > 0) {
        Debug("Time $str seconds\n");
        return $str;
    } elsif ("" eq $str) {
        Debug("Time 0 seconds\n");
        return 0;
    } elsif ($str < 0) {
        Debug("Time <infinite> seconds\n");
        return 99999999999;
    } else {
        Warning("Invalid time specification: $str\n");
        return undef;
    }
}

# Utility subroutine to handle unpredictable types
# (the only type of argument that would be non-sensical here
# would be a hashref)
sub get_array_ref {
    # We got an argument which will be one of the following things:
    # - a "string" scalar
    # - a reference to an array of strings
    # - an array of strings
    # - a single string (which is really the same thing as an array of
    #   strings)

    my $array = shift;

    if (ref($array) !~ /array/i) {
        # The argument passed wasn't a reference
        Debug("Returining reference to an array of a single scalar\n");
        return [$array];
    }

    # If the first element of the array is a reference to an array,
    # then return the dereference (so we get just a single reference
    # to an array [vs. a reference to a reference to an array])
    my $elem = @$array[0];
    my $r = ref($elem);
    if ("" eq $r) {
        # The first element wasn't a reference, so just return the
        # outter reference
        Debug("Returining outter reference\n");
        return $array;
    } elsif ($r =~ /array/i) {
        # The first element was a reference, so return the
        # "dereference" of it
        Debug("Returning de-ref'ed array\n");
        return $elem;
    } else {
        # If we got some other type of reference, we don't like it.
        Warning("get_array_ref got unknown parameter reference type -- ignored\n");
        return undef;
    }
}

1;
