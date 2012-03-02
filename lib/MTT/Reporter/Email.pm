#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2008 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
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
use Sys::Hostname;
# who we're e-mailing to
my $to;

# global ini variables
my ( $ini, $section );

# any extra header lines
my @headers;

# separator line
my $sep;

#--------------------------------------------------------------------------

sub Init {
	( $ini, $section ) = @_;

	# Extract data from the ini fields

	$to = Value( $ini, $section, "email_to" );
	if ( !$to ) {
		Warning(
"Not enough information in Email Reporter section [$section]; must have to; skipping this section"
		);
		return undef;
	}

	$sep = Value( $ini, $section, "email_separator" );
	$sep =
"============================================================================"
	  if ( !$sep );

	# Setup the mailer
	my $agent = Value( $ini, $section, "email_agent" );
	if ( !MTT::Mail::Init($agent) ) {
		Debug("Failed to setup Email reporter\n");
		return 0;
	}

	Debug("Email reporter initialized ($to)\n");


	return 1;
}

#--------------------------------------------------------------------------

sub Finalize {
	undef $to;
	undef @headers;
	undef $sep;
}

#--------------------------------------------------------------------------

sub Submit {
	my ( $info, $entries ) = @_;

	Debug("E-mail reporter\n");

	# Assume that entries are grouped such that we can just combine
	# the reports into a single body and send it in a single mail

	# Evaluate the email subject header and from
	my $subject = Value( $ini, $section, "email_subject" );
	my $from    = Value( $ini, $section, "email_from" );
	
	my $s;
	my $body;
	foreach my $phase ( keys(%$entries) ) {
		my $phase_obj = $entries->{$phase};

		foreach my $section ( keys(%$phase_obj) ) {
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

				my $date = strftime( "%m%d%Y", localtime );
				my $time = strftime( "%H%M%S", localtime );
				my $mpi_name =
				  $report->{mpi_name} ? $report->{mpi_name} : "UnknownMPIName";
				my $mpi_version =
				    $report->{mpi_version}
				  ? $report->{mpi_version}
				  : "UnknownMPIVersion";

				my $str = "\$s = \"$subject\"";
				eval $str;
			}
		}
	}

	# Now send it
	MTT::Mail::Send( $s, $to, $from, $body );
	Verbose(">> Reported to e-mail: $to\n");
}

sub SendStartUpMail{
	my $Ini = shift;
	my $subject = "MTT test has started on ".hostname;
	my $footer = "";
	my $from = "";
	my $to = "";
	foreach my $Section ($Ini->Sections()){
		if (!$footer){
			$footer = Value($Ini, $Section , "email_footer");
		}
		if (!$from){
			$from = Value($Ini, $Section , "email_from");
		}
		if (!$to) {
			$to = Value( $Ini, $Section, "email_to" );
		}
	}
	my $body = $footer."\n";
	if ($to){
		MTT::Mail::Send($subject, $to, $from, $body );
	}
}

1;
