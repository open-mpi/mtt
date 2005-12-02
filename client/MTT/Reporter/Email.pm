#!/usr/bin/env perl
#
# Copyright (c) 2004-2005 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2004-2005 The Trustees of the University of Tennessee.
#                         All rights reserved.
# Copyright (c) 2004-2005 High Performance Computing Center Stuttgart, 
#                         University of Stuttgart.  All rights reserved.
# Copyright (c) 2004-2005 The Regents of the University of California.
#                         All rights reserved.
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
use MTT::Values;
use Data::Dumper;

# who we're e-mailing to
my $to;

# what the subject should be
my $subject;

# any extra header lines
my @headers;

# my mail program
my $mail_agent;

# cache a copy of the environment
my %ENV_original;

#--------------------------------------------------------------------------

sub Init {
    my ($ini, $section) = @_;

    # Extract data from the ini fields

    $to = Value($ini, $section, "to");
    if (!$to) {
        Warning("Not enough information in Email Reporter section [$section]; must have to; skipping this section");
        return undef;
    }
    $subject = Value($ini, $section, "subject");
    $subject = "MPI test results"
        if (!$subject);

    # Find a mail agent

    $mail_agent = FindProgram(qw(Mail mailx mail));
    if (!defined($mail_agent)) {
        Warning("Could not find a mail agent for Email Reporter section [$section]; skipping this section");
        return undef;
    }

    # Save a copy of the environment; we use this later

    %ENV_original = %ENV;

    Debug("Email reporter initialized ($to, $subject)\n");

    1;
}

#--------------------------------------------------------------------------

sub _invoke_mail_agent {
    my ($subject, $to, $body) = @_;

    # Use our "good" environment (e.g., one with TMPDIR set properly)

    my %ENV_now = %ENV;
    %ENV = %ENV_original;

    # Invoke the mail agent to send the mail

    open MAIL, "|$mail_agent -s \"$subject\" \"$to\"" ||
        die "Could not open pipe to output e-mail\n";
    print MAIL "$body\n";
    close MAIL;

    # Restore the old environment

    %ENV = %ENV_now;
}

#--------------------------------------------------------------------------

sub Submit {
    my ($phase, $section, $info, $report) = @_;

    Debug("E-mail reporter\n");
    my $body = MTT::Reporter::MakeReportString($report);

    # Trivial e-mail reporter now -- we could do something much
    # prettier later...

    my $date = strftime("%m%d%Y", localtime);
    my $time = strftime("%H%M%S", localtime);
    my $mpi_name = $report->{mpi_name} ? $report->{mpi_name} : "Unknown-MPI";
    my $mpi_version = $report->{mpi_version} ? $report->{mpi_version} : "Unknown-MPI-Version";

    my $s;
    my $str = "\$s = \"$subject\"";
    eval $str;

    _invoke_mail_agent($s, $to, $body);
}

1;
