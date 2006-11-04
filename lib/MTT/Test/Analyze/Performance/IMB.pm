#!/usr/bin/env perl
#
# Copyright (c) 2006 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::Test::Analyze::Performance::IMB;

use strict;
use Data::Dumper;

# Process the stdout emitted from an IMB test
sub Analyze {

    my($stdout) = @_;
    my $report;
    my(@headers, $data);

    my @lines = split(/\n|\r/, $stdout);

    my $line;
    while (defined($line = shift(@lines))) {

        if ($line =~ /benchmarking\s+(\w+)/i) {
            $report->{test_name} = $1;
            last;
        }
    }

    my $lat_units = '\b\w*sec(?:onds?)?';

    # Grab the table headers
    while (defined($line = shift(@lines))) {

        # Possible headers:
        # #bytes #repetitions      t[usec]                             Mbytes/sec
        # #bytes #repetitions  t_min[usec]  t_max[usec]  t_avg[usec]   Mbytes/sec
        # #bytes #repetitions  t_min[usec]  t_max[usec]  t_avg[usec]
        #        #repetitions  t_min[usec]  t_max[usec]  t_avg[usec]

        if ($line =~
                (/(?:\#?\s*(bytes) \s+)?
                  (?:\#?\s*(repetitions) \s+)
                  (?:
                      (?:\bt_?(   \[?$lat_units\]?) \s*)
                      |
                      (?:\bt_?(min\[?$lat_units\]?) \s*)
                      (?:\bt_?(max\[?$lat_units\]?) \s*)
                      (?:\bt_?(avg\[?$lat_units\]?) \s*)
                  )
                  (?:(\b\w*bytes.sec(?:ond)?)|\w?bps)?
                 /ix)) {

            my $match;
            foreach my $i ((1..7)) {
                eval '$match = $' . $i . ';';
                push(@headers, $match) if (defined($match));
            }
            last;
        }
    }

    # Grab the table body
    my $rows = 0;
    while (defined($line = shift(@lines))) {

        # If test is timed out or killed, exit loop
        last if (($line =~ /kill|terminate|exit/i) or ($line !~ /\d/));

        if ($line =~
                (/
                  (?:([\d\.]+) \s*)
                  (?:([\d\.]+) \s*)
                  (?:([\d\.]+) \s*)
                  (?:([\d\.]+) \s*)?
                  (?:([\d\.]+) \s*)?
                  (?:([\d\.]+) \s*)?
                 /ix)) {

            my $i = 1;
            my $match;
            my @headers_tmp = @headers;

            foreach my $i ((1..7)) {
                my $header = shift @headers_tmp;

                eval '$match = $' . $i . ';';

                if ($match) {
                    push(@{$data->{$header}}, $match);
                }
            }
            $rows++;

        } elsif ($line =~ /^\s*$/) {
            last;
        }
    }

    $report->{test_type} = 'latency_bandwidth';

    foreach my $k (keys %$data) {

        # Careful how header labels are parsed. E.g., 
        # bandwidth and message_size could contain some
        #   variation of string "byte"
        # bandwidth and latency could contain some
        #   variation of string "second"

        if ($k =~ /(min|max|avg)?\[$lat_units\]/i) {
            my $agg = (defined($1) ? $1 : "avg");
            $report->{"latency_$agg"} = 
                "{" . join(",", map { &trim($_) } @{$data->{$k}}) . "}";

        } elsif ($k =~ /[kmbpt]?byte.*sec|[kmbpt]?bps/i) {
            $report->{"bandwidth_avg"} =
                "{" . join(",", map { &trim($_) } @{$data->{$k}}) . "}";

        } elsif ($k =~ /byte|[kmbpt]b/i) {
            $report->{message_size} =
                "{" . join(",", map { &trim($_) } @{$data->{$k}}) . "}";
        }
    }

    if (! defined($report->{message_size})) {
        $report->{message_size} = 
            "{" . join(",", map { "0" } (1..$rows)) . "}";
    }

    return $report;
}

# Trim leading/trailing whitespace
sub trim {
    s/^\s+|\s+$//;
    return $_;
}

1;
