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
use MTT::INI;
sub get_codecov_result
{
	print("Icc codecov: funclet launched\n");
	my $ini = $MTT::Globals::Internals->{ini};
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
		if ($@ || !defined($ret_value))
		{
			Warning("Icc codecov: Not found library: $_\n");
			Warning("Icc codecov: Cannot submit to mongo\n");
			$enable_mongo = 0;
		};
	}
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
		Warning("Icc codecov: Parametr dbase_url not defined in ini file!\n");
		$enable_mongo = 0;
	}
	my $codecov_filtr = MTT::Values::Value( $ini, 'MTT', 'codecov_filtr');
	if(!defined($codecov_filtr))
	{
		Warning("Icc codecov: Parametr codecov_filtr not defined in ini file!\n");
		return 0;
	}
	my $codecov_dir = MTT::Values::Value( $ini, 'MTT', 'codecov_dir');
	if(!defined($codecov_dir))
	{
		Warning("Icc codecov: Parametr codecov_dir not defined in ini file!\n");
		return 0;
	}
	my $ini_basename = MTT::Values::Value( $ini, 'MTT', 'INI_BASENAME');
	if(!defined($ini_basename))
	{
		Warning("Icc codecov: Parametr ini_basename not defined in ini file!\n");
		return 0;
	}
	my $codecov_url = MTT::Values::Value( $ini, 'MTT', 'codecov_url');
	if(!defined($codecov_url))
	{
		Warning("Icc codecov: Parametr codecov_url not defined in ini file!\n");
		return 0;
	}
	my $intel_env_module = MTT::Values::Value( $ini, 'MTT', 'intel_env_module');
	if(!defined($intel_env_module))
	{
		Warning("Icc codecov: Parametr intel_env_module not defined in ini file!\n");
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
	opendir DIR,"$codecov_dir" or (Warning("Icc codecov: Cannot open codeocdir: $codecov_dir\n") and return 0);
		my @FILES= readdir(DIR);
		foreach my $item (@FILES)
		{
			$item = "$codecov_dir" . "/" . $item;
			if((-s $item) == 0)
			{
				print "delete $item\n";
				unlink ($item);
				
			}
		}
		closedir(DIR);
		
		open FILE, ">$codecov_dir/tocodecov.txt" or (Warning("Icc codecov: Cannot open file: $codecov_dir/tocodecov.txt\n") and return 0);
		print FILE $codecov_filtr;
		close(FILE);
		
		print `module load $intel_env_module  && cd $codecov_dir && profmerge`;
		print `cd $codecov_dir && echo "$codecov_filtr">>tocodecov.txt`;
		print `cd $codecov_dir && module load $intel_env_module && codecov -counts -comp tocodecov.txt`;		
		open FILE, "$codecov_dir" . "/CodeCoverage/__CODE_COVERAGE.HTML"  or (Warning("Icc codecov: Cannot open codeocdir: $codecov_dir/CodeCoverage/__CODE_COVERAGE.HTML\n") and return 0);
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
		my @sects = $ini->Sections();
		my $product_version;
		print("Icc codecov: sections before @sects\n");
		if ($MTT::Globals::Values->{shuffle_tests}->{sections})
		{
			MTT::Util::shuffle(\@sects);	
		}
		print("Icc codecov: sections after @sects\n");
		foreach my $section (@sects) 
		{
			print("Icc codecov: section  $section\n");
			if ($section =~ /^\s*mpi install:/) 
			{
				if($section =~ /codecov/)
				{
					my $sim_sec_name = GetSimpleSection($section);
					print("Icc codecov: simple_section  $sim_sec_name\n");
					$product_version =  MTT::Values::Value($ini, "mpi install: $sim_sec_name",'product_version');
					$product_version =~ m/(\d+\.)+\d+/;
					$product_version = $&;
					print("Icc codecov: product version: $product_version\n");
				}
			}
		}
		open FILE, ">$codecov_dir/codecov_output.xml";
		print FILE "<?xml version=\"1.0\"?>";
		print FILE "<codecov_report>";
		print FILE "<mofed_version>";
		print FILE `ofed_info | head -n 1`;
		print FILE "</mofed_version>";
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
			$hash_to_insert->{"codecov_report"}->{"product_name"} = $ini_basename;
			$hash_to_insert->{"codecov_report"}->{"product_version"} = $product_version;
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
			$hash_to_insert->{"codecov_report"}->{"mofed_version"} = `ofed_info | head -n 1`;
			$codecov_reports->insert($hash_to_insert);
		}
		return 0;
}
1;
