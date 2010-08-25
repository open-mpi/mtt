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

# Process the result_stdout emitted from an IMB test
sub Analyze {

    my($result_stdout) = @_;
    my $report;
    my(@headers, $data);

    my @lines = split(/\n|\r/, $result_stdout);

    $report->{test_name} = "unknown";

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
    my $have_some_data = 0;
    while (defined($line = shift(@lines))) {

        # If test is timed out or killed, exit loop
        last if (($line =~ /kill|terminate|exit/i) or ($line !~ /\d/));

        if ($line =~
                (/
                  (?:([\d\.]+) \s+)
                  (?:([\d\.]+) \s+)
                  (?:([\d\.]+) \s+)
                  (?:([\d\.]+) \s*)?
                  (?:([\d\.]+) \s*)?
                  (?:([\d\.]+) \s*)?
                 /ix)) {

            # Set this flag so that we know whether we have begun 
            # reading in the data table
            $have_some_data = 1;

            my $i = 1;
            my $match;
            my @headers_tmp = @headers;

            foreach my $i ((1..7)) {
                my $header = shift @headers_tmp;

                eval '$match = $' . $i . ';';

                push(@{$data->{$header}}, $match);
            }
            $rows++;

        } elsif ($line =~ m/----------------------------------------------------------------/ && 1 == $have_some_data) {
            last;
        }
    }

    if (0 == $have_some_data) {
        return undef;
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

    my $imb_version = "unknown";

    if ($result_stdout =~ m/Benchmark Suite V([\d\.]+)/) {
        $imb_version = $1;
    }

    $report->{suiteinfo}->{suite_name} = "imb";
    $report->{suiteinfo}->{suite_version} = $imb_version;

    return $report;
}

# Trim leading/trailing whitespace
sub trim {
    s/^\s+|\s+$//;
    return $_;
}

sub PreReport
{
    my ($phase, $section, $report) = @_;

    $report->{testphase}->{test_case} = $report->{test_name};
    $report->{test_name} = "IMB-MPI1";
}

1;
