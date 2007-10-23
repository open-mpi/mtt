#!/usr/bin/env perl
#
# Copyright (c) 2007 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Timer;

use strict;
use Benchmark;
use MTT::Messages;
use Data::Dumper;

my $start_timestamp_string;
my $start_benchmark;
my $start_first_benchmark;

sub start {
    my $time_arg = shift;

    return if (!$time_arg);

    $start_benchmark = new Benchmark;
    $start_timestamp_string = localtime;

    if (!defined($start_first_benchmark)) {
        $start_first_benchmark = new Benchmark;
    }
}

# Convert seconds to DD days, HH::MM::SS
sub convert_seconds_to_hhmmss {
    my ($elapsed) = @_;
    my ($days, $hours, $mins, $secs);

    # Constants
    my $m = 60;
    my $h = $m * 60;
    my $d = $h * 24;

    # Individual components
    if ($elapsed > $d) {
        use integer;
        $days = $elapsed / $d;
        $elapsed -= $days * $d;
    } else {
        $days = 0;
    }

    if ($elapsed > $h) {
        use integer;
        $hours = $elapsed / $h;
        $elapsed -= $hours * $h;
    } else {
        $hours = 0;
    }

    if ($elapsed > $m) {
        use integer;
        $mins = $elapsed / $m;
        $elapsed -= $mins * $m;
    } else {
        $mins = 0;
    }

    my $secs = $elapsed;

    my $elapsed_string = sprintf("%02d:%02d:%02d", $hours, $mins, $secs);
    if ($days > 0) {
        $elapsed_string = "$days days, $elapsed_string";
    }
    return $elapsed_string;
}

sub stop {
    my $label = shift;
    my $time_arg = shift;
    my $verbose = shift;

    return if (!$time_arg);

    my $stop_timestamp_string = localtime;
    my $finish_benchmark = new Benchmark;

    my ($real, $user, $system, $children_user, $children_system, $iters);
    my ($real_total, $user_total, $system_total, $children_user_total, $children_system_total, $iters_total);

    # Time elapsed since client/mtt invocation
    ($real_total, $user_total, $system_total, $children_user_total, $children_system_total, $iters_total) =
        @{timediff($finish_benchmark, $start_first_benchmark)};

    # Time elapsed since Timer::start() invocation
    ($real, $user, $system, $children_user, $children_system, $iters) =
        @{timediff($finish_benchmark, $start_benchmark)};

    my $real_hhmmss = convert_seconds_to_hhmmss($real);
    my $real_total_hhmmss = convert_seconds_to_hhmmss($real_total);

    if ($verbose) {
        print ">> $label
   Started:       $start_timestamp_string
   Stopped:       $stop_timestamp_string
   Elapsed:       $real_hhmmss ${user}u ${system}s
   Total elapsed: $real_total_hhmmss ${user_total}u ${system_total}s\n";
   } else {
        print ">> $label
   Elapsed:       $real_hhmmss ${user}u ${system}s\n";
   }
}

1;
