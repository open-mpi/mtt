#!/usr/bin/env perl

#
# Josh Hursey
#
use strict;

my $backup_file = "jjhursey-mtt-db-backup.sql.bz2";
my $tmp_dir = "/tmp";
my $resting_place = "/scratch/jjhursey/backup/";

#
# Make sure the resting place exists
#
if( !(-e $resting_place) ) {
  system("mkdir -p $resting_place");
}

#
# Dump and Zip the file
#
my $cmd;
$cmd = "pg_dump mtt -U mtt | bzip2 - > ". $tmp_dir . "/" . $backup_file;
system($cmd);

#
# Move the file to a safe storage directory
#
$cmd = "mv ".$tmp_dir."/".$backup_file." ".$resting_place;
system($cmd);

exit 0;
