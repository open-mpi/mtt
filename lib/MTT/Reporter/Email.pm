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

package MTT::Reporter::Email;

use strict;
use POSIX qw(strftime);
use MTT::Messages;
use MTT::FindProgram;
use MTT::Mail;
use MTT::Values;
use Data::Dumper;

# who we're e-mailing to
my $to;

# what the subject should be
my $subject;

# any extra header lines
my @headers;

# separator line
my $sep;

#--------------------------------------------------------------------------

sub Init {
    my ($ini, $section) = @_;

    # Extract data from the ini fields

    $to = Value($ini, $section, "email_to");
    if (!$to) {
        Warning("Not enough information in Email Reporter section [$section]; must have to; skipping this section");
        return undef;
    }
    $subject = Value($ini, $section, "email_subject");
    $subject = "MPI test results"
        if (!$subject);
    $sep = Value($ini, $section, "email_separator");
    $sep = "============================================================================"
        if (!$sep);

    # Setup the mailer
    if (!MTT::Mail::Init()) {
        Debug("Failed to setup Email reporter\n");
        return 0;
    }

    Debug("Email reporter initialized ($to, $subject)\n");

    1;
}

#--------------------------------------------------------------------------

sub Finalize {
    undef $to;
    undef $subject;
    undef @headers;
    undef $sep;
}

#--------------------------------------------------------------------------

sub Submit {
    my ($info, $entries) = @_;

    Debug("E-mail reporter\n");

    # Assume that entries are grouped such that we can just combine
    # the reports into a single body and send it in a single mail

    my $s;
    my $body;
    foreach my $phase (keys(%$entries)) {
        my $phase_obj = $entries->{$phase};

        foreach my $section (keys(%$phase_obj)) {
            my $section_obj = $phase_obj->{$section};

            foreach my $report_original (@$section_obj) {
                # Ensure to do a deep copy of the report (vs. just
                # copying the reference) because we want to locally
                # change some values
                my $report;
                %$report = %{$report_original};

                $body .= "$sep\n"
                    if ($body);
                $body .= MTT::Reporter::MakeReportString($report);

                # Trivial e-mail reporter now -- we could do something
                # much prettier later...

                my $date = strftime("%m%d%Y", localtime);
                my $time = strftime("%H%M%S", localtime);
                my $mpi_name = $report->{mpi_name} ? $report->{mpi_name} : "UnknownMPIName";
                my $mpi_version = $report->{mpi_version} ? $report->{mpi_version} : "UnknownMPIVersion";
                
                my $str = "\$s = \"$subject\"";
                eval $str;
            }
        }
    }

    # Now send it
    
    MTT::Mail::Send($s, $to, $body);
    Verbose(">> Reported to e-mail: $to\n");
}

1;
