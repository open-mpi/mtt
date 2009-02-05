#!/usr/bin/env perl
#
# Copyright (c) 2009 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::EnvImporter;

use strict;

use MTT::Messages;
use MTT::FindProgram;
use MTT::Files;
use File::Temp qw(tempfile);
use Data::Dumper;

#--------------------------------------------------------------------------

# Global hash table of saved env snapshots
my $ENV_SAVE;

#--------------------------------------------------------------------------

sub load {
    my @env_importer_files = @_;
    Debug("Loading shell environment files: @_\n");

    # Grab the shell flavor from the file extension 
    my $shell;
    my $source_syntax;

    # Iterate over the list of shell env importer files
    foreach my $env_importer_file (@env_importer_files) {

        # Csh-based shells
        if ($env_importer_file =~ /\.(tcsh|csh|ksh)\s*$/) {
            $shell = $1;
            $source_syntax = "source";
        # Bourne-based shells
        } elsif ($env_importer_file =~ /\.(zsh|bash|sh)\s*$/) {
            $shell = $1;
            $source_syntax = ".";
        # Default to plain vanilla Bourne shell
        } else {
            $shell = "sh";
            $source_syntax = ".";
        }

        # Grab the full path to env and the shell
        my $shell_prog = FindProgram(($shell));
        my $env_prog = FindProgram(qw(env printenv));
        if (! defined($env_prog)) {
            Error("Could not find \"env\" or \"printenv\". Exiting.");
            return undef;
        }

        # Is there a hashbang already in the file?
        my $matches = MTT::Files::Grep("^\#\!", $env_importer_file);

        # If we find a hashbang in the env import file, use the same
        # one for the outer printenv script. Otherwise, use a hashbang
        # based on the filename extension.
        my $hashbang = "#!$shell_prog";
        if (@$matches) {
            $hashbang = shift @$matches;
        }

        # Write and run a temporary script to print the env
        my ($fh, $filename) = tempfile(DIR => MTT::DoCommand::cwd(), SUFFIX => "-printenv");
        my $script = "$hashbang
$source_syntax $env_importer_file
$env_prog
";
        print $fh $script;
        close($fh);
        chmod(0700, $filename);
        my $x = MTT::DoCommand::Cmd(1, "$filename");
        unlink($filename);
        Error("Failed to load shell environment files $env_importer_file\n")
            if (0 != $x->{exit_status});

        # Save the environment for the unload step
        %{$ENV_SAVE->{$env_importer_file}} = %ENV;

        # Parse the env output, and set %ENV
        foreach my $line (split(/\n/, $x->{result_stdout})) {
            if ($line =~ /^\s*(\w+)\=(.*$)/) {
                $ENV{$1} = $2;
            }
        }
    }
}

#--------------------------------------------------------------------------

# This unload subroutine is not like unload in the environment module
# model, e.g., specific environment variables are not unset. Instead,
# we just revert to a previous environment setting snapshot.
sub unload {
    my @env_importer_files = @_;

    foreach my $env_importer_file (@env_importer_files) {
        Debug("Unloading shell environment files: $env_importer_file\n");
        %ENV = %{$ENV_SAVE->{$env_importer_file}};
    }
}

1;
