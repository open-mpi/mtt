#!/usr/bin/env perl
#
# Copyright (c) 2007 Sun Microsystems, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

use strict;
use Cwd;
use Data::Dumper;
use Getopt::Long;
use File::Basename;

#
# Tool to synchronize an mtt SVN repository with
# the ompi-www SVN area
#

my $url = "www.open-mpi.org";
my $live_site_basedir = "/l/osl/www/$url/mtt";

my $ompi_www_dir_arg;
my $mtt_dir_arg;
my $help_arg;
my $no_execute_arg;
my $verbose_arg;

&Getopt::Long::Configure("bundling");
my $ok = Getopt::Long::GetOptions(
            "ompi-www-dir|o=s" => \$ompi_www_dir_arg,
            "mtt-dir|m=s"      => \$mtt_dir_arg,
            "help|h"           => \$help_arg,
            "no-execute|n"     => \$no_execute_arg,
            "verbose|v"        => \$verbose_arg,
);

if ($help_arg) {

    print "WARNING: $0 is a tool for MTT developers!

 -o|--ompi-www-dir  Location of an 'ompi-www' working copy
 -m|--mtt-dir       Location of an 'mtt' working copy
 -n|--no-execute    Do not execute any commands, just print them to stdout
 -v|--verbose       Print commands to stdout
 -h|--help          This help message
";
    exit;
}

# Prompt the user for some directories
my $username = getpwuid($<);
if (! $ompi_www_dir_arg) {
    print "Enter a path to an ompi-www working copy (e.g., /home/$username/ompi-www/trunk): ";
    $ompi_www_dir_arg = <>;
    print "You may skip this step next time by using --ompi-www-dir $ompi_www_dir_arg\n";
}
if (! $mtt_dir_arg) {
    print "Enter a path to an MTT working copy (e.g., /home/$username/mtt/trunk): ";
    $mtt_dir_arg = <>;
    print "You may skip this step next time by using --mtt-dir $mtt_dir_arg\n";
}

# Validate the working copies
if (! validate_working_copy($mtt_dir_arg)) {
    die "Could not validate your mtt working copy using svn info.";
}
if (! validate_working_copy($ompi_www_dir_arg)) {
    die "Could not validate your ompi-www working copy using svn info.";
}

# "svn up" on the working copies to ensure that:
#   1. We are copying over up-to-date source files from the mtt working copy
#   2. There are no svn conflicts
update_working_copies($mtt_dir_arg, $ompi_www_dir_arg);

# Gather all the files to be copied over to ompi-www
my $files = gather_versioned_files($mtt_dir_arg);

# Copy mtt files over to an ompi-www working copy
copy_to_ompi_www($files, $ompi_www_dir_arg);

# Commit changes to ompi-www repository
do_system("svn diff $ompi_www_dir_arg");
yes_or_no_prompt("\nCommit?");
do_system("svn commit -m'Sync svn/ompi-www/mtt with svn/mtt' $ompi_www_dir_arg");

# Make the changes to the live website
yes_or_no_prompt("\nRun 'svn update' on $live_site_basedir?");
do_system("svn update $live_site_basedir");

exit;

# ---------------------------------------------------------

sub validate_working_copy {
    my ($path) = @_;

    # $ svn info
    # Path: .
    # URL: https://svn.open-mpi.org/svn/mtt/trunk/server/php/submit
    # Repository Root: https://svn.open-mpi.org/svn/mtt
    # Repository UUID: 3a00f1f0-e206-0410-aee5-9638c71ae14b
    # Revision: 1029
    # Node Kind: directory
    # Schedule: normal
    # Last Changed Author: xxxxxxxx
    # Last Changed Rev: 1029
    # Last Changed Date: 2007-09-18 10:14:46 -0400 (Tue, 18 Sep 2007)

    my $svn_info = `svn info $path`;

    if ($svn_info =~ /URL:\s+https?:\/\/svn.open-mpi.org\/svn\/(?:ompi-www|mtt)/) {
        return 1;
    }

    return undef;
}

sub gather_versioned_files {
    my ($path) = @_;
    do_chdir($path);

    my $svn_status = `svn status --verbose`;

    my @lines = split(/\n/, $svn_status);

    my @files;
    foreach (@lines) {

        # $ svn st -q -v
        #    731  705 bob  .
        #    731  613 bob  .htaccess
        #    731  705 bob  index.php
        if (/\d+\s+\d+\s+\w+\s+(\S+)$/) {
            push(@files, $1) if (-f $1);
        }
    }

    return \@files;
}

sub copy_to_ompi_www {
    my($files, $destination) = @_;

    my $file_list = join(" ", @$files);

    # tar -cf - `find . -name "*.$1" -print` | ( cd ../destination && tar xBf - )
    my $str = "tar -cf - %s | ( cd %s && tar xBf - )";

    my $cmd = sprintf($str, $file_list, $destination);

    do_system($cmd);
}

sub update_working_copies {
    my @working_copies = @_;

    my $svn_update;
    foreach my $wc (@working_copies) {
        $svn_update = `svn update $wc`;

        if ($svn_update =~ /\n\bC\b/) {
            die "\nResolve the conflict in '$wc' and try again.";
        }
    }
}

sub yes_or_no_prompt {
    my ($str) = @_;
    print "$str (y/n) ";
    my $answer = <>;
    exit if ($answer =~ /n/i);
}

sub do_system {
    my ($cmd) = @_;
    print "\nExecuting: $cmd\n" if ($verbose_arg or $no_execute_arg);
    if (! $no_execute_arg) {
        system($cmd) eq 0 or die $!;
    }
}

sub do_chdir {
    my($dir) = @_;
    print "\nchdir $dir" if ($verbose_arg or $no_execute_arg);
    chdir($dir) or die $!;
}
