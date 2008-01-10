#!/usr/bin/env perl

use strict;

#
# Script requires the following software packages installed:
# - psql (with access to the mtt database)
# - gnuplot (with postscript terminal)
# - ps2pdf
#

# Directory containing scripts to execute
my $working_dir = "/u/jjhursey/work/mtt-stuff/mtt-trunk/server/sql/stats";
# Directory to place the contribution graph
my $output_dir  = "/l/osl/www/www.open-mpi.org/mtt/stats/";
# Temporary directory to store data files
my $tmp_dir = "/tmp/";

my $cmd;

if(!chdir($working_dir) ) {
  print "Error: Cannot chdir to <$working_dir>\n";
  exit(-1);
}

#
# Gather the raw data
#
$cmd = "./make-raw-data.pl -year > ".$tmp_dir."mtt-raw-year.data";
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

$cmd = "./make-raw-data.pl -month > ".$tmp_dir."mtt-raw-month.data";
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

$cmd = "./make-raw-data.pl -week > ".$tmp_dir."mtt-raw-week.data";
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

$cmd = "./make-raw-data.pl -day > ".$tmp_dir."mtt-raw-day.data";
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

#
# Graph the data
#
$cmd = "gnuplot graph-raw-data.plot 2> /dev/null 1> /dev/null";
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

#
# Convert the ps -> pdf
#
$cmd = "ps2pdf ".$tmp_dir."/mtt-contrib.ps ".$tmp_dir."/mtt-contrib.pdf";
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

#
# Cleanup
#
$cmd = ("rm ".$tmp_dir."/mtt-contrib.ps ".
        $tmp_dir."mtt-raw-year.data ".
        $tmp_dir."mtt-raw-month.data ".
        $tmp_dir."mtt-raw-week.data ".
        $tmp_dir."mtt-raw-day.data");
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

#
# Post the graph
#
$cmd = "mv ".$tmp_dir."/mtt-contrib.pdf ".$output_dir."/";
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

exit(0);
