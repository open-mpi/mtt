#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2008 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Values::Functions::Icc_codecov;

use strict;
use File::Temp qw(tempfile);
use MTT::Messages;
use MTT::DoCommand;
use MTT::FindProgram;
use Data::Dumper;
use MTT::Values::Functions;
sub get_codecov_result
{
	my $enable_mongo = 1;
	my $ret_value;
	my @needed_libs = (
			"YAML", 
			"MongoDB", 
			"MongoDB::OID", 
				);
	foreach (@needed_libs)
	{
		$ret_value = eval "require $_";
		print "qqq $ret_value\n";
		if ($@ || !defined($ret_value))
		{
			Verbose("--> Not found library: $_\n");
			Verbose("cannot submit to mongo\n");
			$enable_mongo = 0;
		};
	}
	print "\nqqq\n";
	if($enable_mongo == 1)
	{
		require MongoDB;
		require MongoDB::OID;
	}
	#################################################################
	my $ini = $MTT::Globals::Internals->{ini};
	my $dbase_url = MTT::Values::Value( $ini, 'MTT', 'dbase_url' );
	if(!defined($dbase_url))
	{
		Error("Parametr dbase_url not defined in ini file!\n");
		#exit(0);
		#return 0;
		$enable_mongo = 0;
	}
	my $codecov_filtr = MTT::Values::Value( $ini, 'MTT', 'codecov_filtr');
	if(!defined($codecov_filtr))
	{
		Error("Parametr codecov_filtr not defined in ini file!\n");
		exit(0);
		return 0;
	}
	my $codecov_dir = MTT::Values::Value( $ini, 'MTT', 'codecov_dir');
	if(!defined($codecov_dir))
	{
		Error("Parametr codecov_dir not defined in ini file!\n");
		exit(0);
		return 0;
	}
	my $ini_basename = MTT::Values::Value( $ini, 'MTT', 'INI_BASENAME');
	if(!defined($ini_basename))
	{
		Error("Parametr ini_basename not defined in ini file!\n");
		exit(0);
		return 0;
	}
	my $codecov_url = MTT::Values::Value( $ini, 'MTT', 'codecov_url');
	if(!defined($codecov_url))
	{
		Error("Parametr codecov_url not defined in ini file!\n");
		exit(0);
		return 0;
	}
	my $intel_env_module = MTT::Values::Value( $ini, 'MTT', 'intel_env_module');
	if(!defined($intel_env_module))
	{
		Error("Parametr intel_env_module not defined in ini file!\n");
		exit(0);
		return 0;
	}
	#my $dbase_url = "@dbase_url@";
	#my $codecov_filtr = "@codecov_filtr@";
	#my $codecov_dir = "@codecov_dir@";
	#my $ini_basename = "@INI_BASENAME@";
	#my $codecov_url = "@codecov_url@";
	#my $intel_env_module = "@intel_env_module@";
	#################################################################
	$dbase_url =~ s/http:\/\///;
	my $conn;
	my $db;
	my $codecov_reports;
	if($enable_mongo == 1)
	{
		$conn = MongoDB::Connection->new(host => $dbase_url);
		$db = $conn->mtt;
		$codecov_reports = $db->Codecov_reports;
	}
	my $hash_to_insert = {};
	opendir(DIR,"$codecov_dir");
		my @FILES= readdir(DIR);
		foreach my $item (@FILES)
		{
			$item = "$codecov_dir" . "/" . $item;
			if((-s $item) == 0)
			{
				print "ydalil $item\n";
				unlink ($item);
				
			}
		}
		closedir(DIR);
		
		open FILE, ">$codecov_dir/tocodecov.txt";
		print FILE $codecov_filtr;
		close(FILE);
		
		print `module load $intel_env_module  && cd $codecov_dir && profmerge`;
		#print `cd $codecov_dir && echo "$codecov_filtr">>tocodecov.txt`;
		print `cd $codecov_dir && echo "$codecov_filtr">>tocodecov1.txt`;
		print `cd $codecov_dir && module load $intel_env_module && codecov -counts -comp tocodecov.txt`;		
		open FILE, "$codecov_dir" . "/CodeCoverage/__CODE_COVERAGE.HTML"  or die "$!";
		my $str;
		my @val;
		while (<FILE>) 
		{
			$str = $_;
			if ($str =~ m/<TD ALIGN=\"center\"( STYLE=\"font-weight:bold\"){0,1}>\s*\d+[\.\,]*\d*<\/TD>/)
			{
				if($str =~ m/\d+[\.\,]*\d*/)
				{
					my $t_val = $&;
					$t_val =~ s/\,//g; 
					push(@val,$t_val);
				}
			}
		}
		close FILE;
		open FILE, ">$codecov_dir/codecov_output.xml";
		print FILE "<?xml version=\"1.0\"?>";
		print FILE "<codecov_report>";
		print FILE "<product_name>";
		print FILE "$ini_basename";
		print FILE "</product_name>";
		print FILE "<report_url>";
		print FILE "$codecov_url";
		print FILE "</report_url>";
		my $report_date = `date +%F` ." ". `date +%k:%M:%S`;		
		print FILE "<report_date>";
		print FILE $report_date;
		print FILE "</report_date>";		
		print FILE "<Files>";		
		print FILE "<total>";
		print FILE @val[0];
		print FILE "</total>";
		print FILE "<cvrd>";
		print FILE @val[1];
		print FILE "</cvrd>";		
		print FILE "<uncvrd>";
		print FILE @val[2];
		print FILE "</uncvrd>";		
		print FILE "<percent>";
		print FILE (int(@val[3]))."%";
		print FILE "</percent>";		
		print FILE "</Files>";
		print FILE "<Functions>";
		print FILE "<total>";
		print FILE @val[4];
		print FILE "</total>";
		print FILE "<cvrd>";
		print FILE @val[5];
		print FILE "</cvrd>";
		print FILE "<uncvrd>";
		print FILE @val[6];
		print FILE "</uncvrd>";
		print FILE "<percent>";
		print FILE (int(@val[7]))."%";
		print FILE "</percent>";
		print FILE "</Functions>";
		print FILE "<Blocks>";
		print FILE "<total>";
		print FILE @val[8];
		print FILE "</total>";
		print FILE "<cvrd>";
		print FILE @val[9];
		print FILE "</cvrd>";
		print FILE "<uncvrd>";
		print FILE @val[10];
		print FILE "</uncvrd>";
		print FILE "<percent>";
		print FILE (int(@val[11]))."%";
		print FILE "</percent>";
		print FILE "</Blocks>";
		print FILE "</codecov_report>";
		close(FILE);
		
		if($enable_mongo == 1)
		{
			$hash_to_insert->{"codecov_report"}->{"product_name"} = "$ini_basename";
			$hash_to_insert->{"codecov_report"}->{"report_url"} = "$codecov_url";
			$hash_to_insert->{"codecov_report"}->{"files"}->{"total"} = @val[0];
			$hash_to_insert->{"codecov_report"}->{"files"}->{"cvrd"} = @val[1];
			$hash_to_insert->{"codecov_report"}->{"files"}->{"uncvrd"} = @val[2];
			$hash_to_insert->{"codecov_report"}->{"files"}->{"percent"} = (int(@val[3]))."%";
			$hash_to_insert->{"codecov_report"}->{"functions"}->{"total"} = @val[4];
			$hash_to_insert->{"codecov_report"}->{"functions"}->{"cvrd"} = @val[5];
			$hash_to_insert->{"codecov_report"}->{"functions"}->{"uncvrd"} = @val[6];
			$hash_to_insert->{"codecov_report"}->{"functions"}->{"percent"} = (int(@val[7]))."%";
			$hash_to_insert->{"codecov_report"}->{"blocks"}->{"total"} = @val[8];
			$hash_to_insert->{"codecov_report"}->{"blocks"}->{"cvrd"} = @val[9];
			$hash_to_insert->{"codecov_report"}->{"blocks"}->{"uncvrd"} = @val[10];
			$hash_to_insert->{"codecov_report"}->{"blocks"}->{"percent"} = (int(@val[11]))."%";		
			$hash_to_insert->{"codecov_report"}->{"report_date"} = $report_date;			
			
			$codecov_reports->insert($hash_to_insert);
		}
		return 0;
}
1;
