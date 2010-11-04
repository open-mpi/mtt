#!/usr/bin/env perl

use strict;
use Env qw(HOME PATH USER);

# Perform flush after each write to STDOUT
$| = 1;

#
# MTT Working Dir to find scripts
#
my $mtt_base_dir = "$HOME/mtt/trunk/server/sql/";

#
# DB Conversion script
# Past 2 days to today - 12 hours
my $conv_script = $mtt_base_dir . "support/convert-v2-to-v3.pl";
my $conv_args   = ("start_timestamp >= DATE      'now' - interval '3 days' and ".
                   "start_timestamp <  TIMESTAMP 'now'");

#
# Output file to collect debugging output
#
my $conv_output = $mtt_base_dir . "output/mtt-update-db-output.txt";

#
# Change to the working directory, and run the command
#
chdir($mtt_base_dir);
system("echo >> ". $conv_output);
system("echo Start Time >> ". $conv_output);
system("date >> ". $conv_output);
system("echo >> ". $conv_output);

my $cmd = $conv_script . " \"" . $conv_args . "\" >> " . $conv_output;
system($cmd);

system("echo >> ". $conv_output);
system("echo End Time >> ". $conv_output);
system("date >> ". $conv_output);
system("echo >> ". $conv_output);
system("echo >> ". $conv_output);

exit 0;
