#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2007      Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Reporter;

use strict;
use Carp;
use File::Basename;
use MTT::Messages;
use MTT::FindProgram;
use MTT::Values;
use Data::Dumper;

#--------------------------------------------------------------------------

# Cache of info about the system
my $cache;

# Queued requests
my $queue;

# modules to invoke (module => INI section)
my $modules;

#--------------------------------------------------------------------------

sub MakeReportString {
    my ($report, $delimiter) = @_;

    my $str;
    _stringify(\$str, $cache, $delimiter);
    _stringify(\$str, $report, $delimiter);
    return $str;
}

sub _stringify {
    my ($str, $hash, $delimiter) = @_;

    $delimiter = ": "
        if (!$delimiter);

    my @to_delete;
    foreach my $k (sort(keys(%$hash))) {
        # Huersitic: if there are any newlines in the original string,
        # we want this to be a multi-line output.  
        my $val = $hash->{$k};
        next
            if (!defined($val));
        my $want_multi = ($val =~ /\n/);

        # We currently have 2 conventions (bonk!) for field names --
        # lower case (i.e., as-is) for single-line fields and upper
        # case for multi-line fields.
        $$str .= ($want_multi ? uc($k) . "_BEGIN" : $k . $delimiter);

        # Trim off leading and trailing blank lines and any final \n's
        # (from perlfaq4(1))
        for ($val) {
            s/^\s+//;
            s/\s+$//;
        }

        # Double check that we have anything left in the string
        if ($val ne "") {
            if ($want_multi) {
                $$str .= "\n$val\n";
                # If we are multi-line, then be sure to end the text
                # with a "END" marker (same upper case rule as above)
                $$str .= uc($k) . "_END\n"
                    if ($want_multi);
            } else {
                $$str .= "$val\n";
            }
        } else {
            # If we have nothing left, mark this key to be removed
            # (it's a bad idea to remove a key while we're iterating
            # over it, per perlfaq4(1))
            push(@to_delete, $k);
        }
    }

    foreach my $d (@to_delete) {
        delete $hash->{$d};
    }
}

#--------------------------------------------------------------------------

sub Init {
    my ($ini) = @_;

    Verbose("*** Reporter initializing\n");

    # Record start time for the overall MTT run
    $cache->{start_timestamp} = gmtime;

    # Go through all the sections in the ini file looking for section
    # names that begin with "reporter:"

    foreach my $section ($ini->Sections()) {
        if ($section =~ /^reporter:/) {
            my $m = MTT::Values::Value($ini, $section, "module");
            if (!$m) {
                Warning(">> Reporter [$section] has no module; skipping\n");
                next;
            }
            Verbose(">> Initializing reporter module: $m\n");
            my $ret = MTT::Module::Run("MTT::Reporter::$m", "Init", $ini,
                                       $section);
            if ($ret) {
                $modules->{$m} = $section;
            }
        }
    }

    Verbose("*** Reporter initialized\n");
}

#--------------------------------------------------------------------------

sub Finalize {
    Verbose("*** Reporter finalizing\n");

    foreach my $m (keys %$modules) {
        MTT::Module::Run("MTT::Reporter::$m", "Finalize");
    }

    Verbose("*** Reporter finalized\n");
}

#--------------------------------------------------------------------------

sub Submit {
    my ($phase, $section, $report) = @_;
    my ($serials, $x);

    # Make the INI file globally accessible
    my $ini = $MTT::Globals::Internals->{ini};

    # Make the common report entry
    my $entries;
    push(@{$entries->{$phase}->{$section}}, $report);

    # Call all the reporters
    foreach my $m (keys %$modules) {

        # Grab the INI section
        my $reporter_section = $modules->{$m};

	my $skip_mpi_get = MTT::Values::Value($ini, $reporter_section, 
					      "skip_mpi_get");
	my $go_next = 0;
	foreach my $skip_one_mpi_get (MTT::Util::split_comma_list($skip_mpi_get)) {
	    if (lc($report->{mpi_get_section_name}) eq lc($skip_one_mpi_get)) {
		Verbose("   Skipping reporter [$reporter_section]\n");
		$go_next = 1;
		last;
	    }
	}
	next
	    if ($go_next);

	my $skip_mpi_install = MTT::Values::Value($ini, $reporter_section, 
						  "skip_mpi_install");
	$go_next = 0;
	foreach my $skip_one_mpi_install (MTT::Util::split_comma_list($skip_mpi_install)) {
	    if (lc($report->{mpi_install_simple_section_name}) eq lc($skip_one_mpi_install)) {
		Verbose("   Skipping reporter [$reporter_section]\n");
		$go_next = 1;
		last;
	    }
	}
	next
	    if ($go_next);

        # For INI consistency, process setenv, unsetenv, prepend-path, and
        # append-path, but no need to record these settings for the results. It
        # is just a convenience (e.g., changing TMPDIR for MTTDatabase).
        my %ENV_SAVE = %ENV;

        # Process environment for given Reporter
        my @save_env;
        my $config;
        $config->{setenv}       = MTT::Values::Value($ini, $reporter_section, "setenv");
        $config->{unsetenv}     = MTT::Values::Value($ini, $reporter_section, "unsetenv");
        $config->{prepend_path} = MTT::Values::Value($ini, $reporter_section, "prepend_path");
        $config->{append_path}  = MTT::Values::Value($ini, $reporter_section, "append_path");
        MTT::Values::ProcessEnvKeys($config, \@save_env);

        $x = MTT::Module::Run("MTT::Reporter::$m", "Submit", $cache, $entries);
        # Some reporters are not yet returning serials (e.g., text file)
        if (ref($x) ne "") {
            foreach my $k (keys %$x) {
                $serials->{$m}->{$k} = $x->{$k};
            }
        }

        # Restore the environment
        %ENV = %ENV_SAVE;
    }

    return $serials;
}

#--------------------------------------------------------------------------

sub QueueAdd {
    my ($phase, $section, $report) = @_;

    push(@{$queue->{$phase}->{$section}}, $report);
}

#--------------------------------------------------------------------------

sub QueueSubmit {

    # Call all the reporters
    foreach my $m (keys %$modules) {
        MTT::Module::Run("MTT::Reporter::$m", "Submit", $cache, $queue);
    }

    # Empty the queue

    $queue = undef;
}

1;
