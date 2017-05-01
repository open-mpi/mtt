#!/usr/bin/env perl

use strict;
use Env qw(HOME PATH USER);
use Config::IniFiles;

#
# Script requires the following software packages installed:
# - psql (with access to the mtt database)
# - gnuplot (with postscript terminal)
# - ps2pdf
#
my $config_filename = "config.ini";
my $ini_section;

my $cmd;

my $is_limited_to_one_year = "f";

my $data_file_year  = "mtt-raw-year.data";
my $data_file_month = "mtt-raw-month.data";
my $data_file_week  = "mtt-raw-week.data";
my $data_file_day   = "mtt-raw-day.data";

my $gnuplot_file = "graph-raw-data.plot";
my $ps_file  = "mtt-contrib.ps";
my $pdf_file = "mtt-contrib.pdf";

my $extra_cmd_line_arg = "";

#
# Parse any command line arguments
#
if( 0 != parse_cmd_line() ) {
  print_usage();
  exit -1;
}

my $ini = new Config::IniFiles(-file => $config_filename,
                               -nocase => 1,
                               -allowcontinue => 1);
if( !$ini ) {
    print "Error: Failed to read: $config_filename\n";
    exit 1;
}

# Check the contents of the config file
check_ini_section($ini, "stats", ("working_dir", "output_dir", "tmp_dir") );

$ini_section = "stats";
# Directory containing scripts to execute
my $working_dir = resolve_value($ini, $ini_section, "working_dir");
# Directory to place the contribution graph
my $output_dir  = resolve_value($ini, $ini_section, "output_dir");
# Temporary directory to store data files
my $tmp_dir = resolve_value($ini, $ini_section, "tmp_dir");

if(!chdir($working_dir) ) {
  print "Error: Cannot chdir to <$working_dir>\n";
  exit(-1);
}

if( $is_limited_to_one_year eq "t" ) {
    $extra_cmd_line_arg = " -l ";

    $data_file_year  .= "-1year";
    $data_file_month .= "-1year";
    $data_file_week  .= "-1year";
    $data_file_day   .= "-1year";

    $gnuplot_file = "graph-raw-data-1year.plot";
    $ps_file  = "mtt-contrib-1year.ps";
    $pdf_file = "mtt-contrib-1year.pdf";
}

#
# Gather the raw data
#

$cmd = "./make-raw-data.pl -year ".$extra_cmd_line_arg." > ".$tmp_dir.$data_file_year;
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

$cmd = "./make-raw-data.pl -month ".$extra_cmd_line_arg." > ".$tmp_dir.$data_file_month;
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

$cmd = "./make-raw-data.pl -week ".$extra_cmd_line_arg." > ".$tmp_dir.$data_file_week;
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

$cmd = "./make-raw-data.pl -day ".$extra_cmd_line_arg." > ".$tmp_dir.$data_file_day;
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

#
# Graph the data
#
$cmd = "gnuplot ".$gnuplot_file." 2> /dev/null 1> /dev/null";
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

#
# Convert the ps -> pdf
#
$cmd = "ps2pdf ".$tmp_dir."/".$ps_file." ".$tmp_dir."/".$pdf_file;
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

#
# Cleanup
#
$cmd = ("rm ".$tmp_dir."/".$ps_file." ".
        $tmp_dir.$data_file_year." ".
        $tmp_dir.$data_file_month." ".
        $tmp_dir.$data_file_week." ".
        $tmp_dir.$data_file_day);
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

#
# Post the graph
#
$cmd = "mv ".$tmp_dir."/".$pdf_file." ".$output_dir."/";
if(0 != system($cmd) ) {
  print "Error: Cannot exec the command <$cmd>\n";
  exit(-1);
}

exit(0);

sub parse_cmd_line() {
  my $i = -1;
  my $argc = scalar(@ARGV);
  my $exit_value = 0;

  for($i = 0; $i < $argc; ++$i) {
    if( $ARGV[$i] eq "-h" ) {
      $exit_value = -1;
    }
    elsif( $ARGV[$i] eq "-l" ) {
      $is_limited_to_one_year = "t";
    }
    elsif( $ARGV[$i] =~ /-config/ ) {
      $i++;
      if( $i < $argc ) {
        $config_filename = $ARGV[$i];
      } else {
        print_update("Error: -config requires a file argument\n");
        return -1;
      }
    }
    #
    # Invalid options produce a usage message
    #
    else {
      print "ERROR: Unknown argument [".$ARGV[$i]."]\n";
      $exit_value = -1;
    }
  }

  return $exit_value;
}

sub print_usage() {
  print "="x50 . "\n";
  print "Usage: ./create-contrib-graph.pl [-h] [-l]\n";
  print "="x50 . "\n";

  return 0;
}


sub resolve_value() {
    my $ini = shift(@_);
    my $section = shift(@_);
    my $key = shift(@_);
    my $value;
    
    $value = $ini->val($section, $key);
    if( !defined($value) ) {
        print "Error: Failed to find \"$key\" in section \"$section\"\n";
        exit 1;
    }
    $value =~ s/^\"//;
    $value =~ s/\"$//;

    if( $value =~ /^run/ ) {
        $value = $';
        $value =~ s/^\(//;
        $value =~ s/\)$//;
        $value = `$value`;
        chomp($value);
    }

    return $value;
}

sub check_ini_section() {
    my $ini = shift(@_);
    my $section = shift(@_);
    my @keys = @_;

    if( !$ini->SectionExists($section) ) {
        print "Error: INI file does not contain a $section field\n";
        exit 1;
    }

    foreach my $key (@keys) {
        if( !$ini->exists($section, $key) ) {
            print "Error: INI file missing $section key named $key\n";
            exit 1;
        }
    }

    return 0;
}
