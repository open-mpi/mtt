#!/usr/bin/env perl

use strict;
use Env qw(HOME PATH USER);

# Perform flush after each write to STDOUT
$| = 1;

#
# MTT Working Dir to find scripts
#
my $mtt_base_dir = "/l/osl/www/mtt.open-mpi.org/mtt/server/php/cron/";

#
# Stats collection script
#
my $stats_script = $mtt_base_dir . "stats/collect-stats.pl";
my $stats_args   = " -past 2 -v 2 -no-db ";

#
# Output file to collect debugging output
#
my $stats_output = $mtt_base_dir . "mtt-update-stats-output.txt";

#
# Change to the working directory, and run the command
#
chdir($mtt_base_dir);
system("echo >> ". $stats_output);
system("echo Start Time >> ". $stats_output);
system("date >> ". $stats_output);
system("echo >> ". $stats_output);

my $cmd = $stats_script . " " . $stats_args . " >> " . $stats_output;
system($cmd);

system("echo >> ". $stats_output);
system("echo End Time >> ". $stats_output);
system("date >> ". $stats_output);
system("echo >> ". $stats_output);
system("echo >> ". $stats_output);

exit 0;
