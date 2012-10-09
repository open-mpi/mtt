#!/usr/bin/env perl
#
# Copyright (c) 2009 Voltaire
# Copyright (c) 2010 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::Reporter::MTTMongodb;

use strict;
use MTT::Messages;
use MTT::Values;
use MTT::Values::Functions;
use MTT::Version;
use MTT::Globals;
use MTT::DoCommand;
use LWP::UserAgent;
use HTTP::Request::Common qw(POST);
use Data::Dumper;
use File::Basename;
use File::Temp qw(tempfile tempdir);
use POSIX qw(strftime);
use File::stat;


# http credentials
my $username;
my $password;
my $realm;
my $url;
my $port;

# platform common name
my $platform;

# LWP user agents (one per proxy)
my @lwps;

# Hostname string to report
my $hostname;

# User ID (can be overridden in the INI)
my $local_username;

# directory and file to write to
my $dirname;

my $testrun_files_count    = 0;
my $testbuild_files_count  = 0;
my $mpiinstall_files_count = 0;

our $clusterInfo = undef;

#--------------------------------------------------------------------------

sub Init {
    my ($ini, $section) = @_;
    Debug("MTTMongoDB Init\n");

    if (defined($username)) 
	{
        Error("MTTMongoDB reporter: The MTTMongoDB plugin can only be used once in an INI file.\n");
    }

    $username = Value($ini, $section, 'username');
    $password = Value($ini, $section, 'password');
    $url = Value($ini, $section, 'dbase_url');
    $local_username = Value($ini, "mtt", 'local_username');

    if (!$url)
	{
        Warning("MTTMongoDB reporter: dbase_url not defined\n");
        return undef;
    }

	$url =~ s/http:\/\///;
	
    $dirname = MTT::DoCommand::cwd();

    Debug("MTTMongoDB reporter: Collect cluster information...\n");
	
    my $clusterinfo_module = MTT::Values::Value($ini, "vbench", "clusterinfo_module");
	
    $clusterinfo_module = "UnknownCluster" if (!defined($clusterinfo_module) || $clusterinfo_module eq "");
	
    Debug("Use $clusterinfo_module module to collect information.\n");
    
    $clusterInfo = MTT::Module::Run("MTT::Reporter::Utils::$clusterinfo_module", "get_cluster_info", MTT::Values::Functions::env_hosts(2));
    
	if (!defined($clusterInfo))
	{
        Error("Fatal: Can't collect cluster information\n");
    }
    
	Debug("MTTMongoDB reporter: Collect cluster information Finished\n");
    
    Debug("MTTMongoDB reporter: File reporter initialized ($dirname)\n");

    return 1;
}

#--------------------------------------------------------------------------

my $entries;

sub Submit {


    my ( $info, $newentries ) = @_;

    Debug("MTTMongoDB reporter: Submit\n");

    if (!defined($newentries)) {
        Warning("MTTMongoDB reporter: Submit parameter is undef. Skip.\n");
        return;
    }
    
    if ( !defined($entries) )
	{
        %$entries = ();
    }

    foreach my $phase (keys(%$newentries)) 
	{
        my $phase_obj = $newentries ->{$phase};

        foreach my $section ( keys(%$phase_obj) ) 
		{
           Debug("Phase: $phase Section: $section\n");

           my $new_section_obj = $phase_obj->{$section};

           my $section_obj = $entries->{$phase}->{$section};

           foreach my $report (@$new_section_obj) 
		   {
               Debug("MTTMongoDB reporter: add report\n");
               push(@$section_obj, $report);
           }

           $entries->{$phase}->{$section} = $section_obj;
		   
       }
    }

    Verbose("MTTMongoDB reporter: cached for later submit\n");
    Debug("MTTMongoDB reporter: Exit from Submit\n");
}

sub Finalize {
    Debug("MTTMongoDB reporter: Finalize\n");
    
    _do_submit();
    undef $entries;
    undef $username;
    undef $password;
    undef $url;    
}

#--------------------------------------------------------------------------

sub resolve_template
{
	my ($template,@arg) = @_;
	my $i2=($#arg+1)/2;
	for(my $i=0;$i<($#arg+1)/2;$i++)
	{
		$template =~ s/\%@arg[$i]\%/@arg[$i2]/g;
		$i2++;
	}
	return $template;
}

sub _do_submit 
{
	my $enable_mongo = 1;
	my $ret_value;
	my @needed_libs = (
		'MongoDB', 
       	'MongoDB::OID', 
		'YAML::XS',
		'YAML',
		'MongoDB::GridFS'
				);
								    
			
	foreach (@needed_libs)
	{
	   	$ret_value = eval "require $_";
   	 	if ($@ || !defined($ret_value))
	    {
			Warning("MongoDB reporter: Not found library: $_\n");
			Warning("MongoDB reporter: Can't submit to mongo\n");
			$enable_mongo = 0;

		};
	}
	if($enable_mongo == 1)
	{
		require MongoDB;
		require MongoDB::OID;
		require YAML::XS;
		require YAML;
	}
	my $basis_db;
	my $MPIInstallPhase;
	my $TestBuildPhase; 
	my $summary_reports;
	my $conn;
	my $db;
	if($enable_mongo == 1)
	{
		$conn = MongoDB::Connection->new(host => $url);
		$db = $conn->mlnx_mtt;
		$basis_db = $db->Basis;
	}
	my $xml_template = "<report><mofed_version>%mofed_version%</mofed_version><report_date>%report_date%</report_date><scratch_url>%scratch_url%</scratch_url><scratch_root>%scratch_root%</scratch_root><product_name>%product_name%</product_name><product_version>%product_version%</product_version><total_duration>%duration%</total_duration><total_tests>%total_tests%</total_tests><failed_tests>%failed_tests%</failed_tests><quality>%quality%</quality></report>";
	my $i=0;
	my $to_xml;
    my $ini = $MTT::Globals::Internals->{ini};	
	my $path = MTT::Values::Value($ini, "MTT", 'xml_dir');
	my $scratch_url = MTT::Values::Value($ini, "MTT", 'scratch_url');

    my $default_form = { product => 'mttmongodb', version => '2.0'};

    my $ini = $MTT::Globals::Internals->{ini};

    my $submit_results = MTT::Values::Value( $ini, "Reporter: mongo data base", 'submit_all_results' );
	my $submit_failed_results = MTT::Values::Value( $ini, "Reporter: mongo data base", 'submit_failed_results' );
    
    if (($submit_results eq '1' || $submit_results eq 'True' || $submit_results eq 'true') && $enable_mongo == 1)
    {
        $enable_mongo = 1;
    } else 
	{
        $enable_mongo = 0;
    }
    
	
    #foreach my $phase ( "MPI Install", "Test Build", "Test Run" )
	foreach my $phase ( "Test Run" ) 
	{
        my $submitted = 0;
        my $phase_obj = $entries->{$phase};

        foreach my $section ( keys(%$phase_obj) ) 
		{
            my $section_obj = $phase_obj->{$section};

            foreach my $report_original (@$section_obj) 
			{
                my $form;
                %$form = %{$default_form};
                $form->{modules} = {};

                my $report;
                %$report = %{$report_original};
                %$report->{files_to_copy} = {} if (!exists($report->{files_to_copy}));

                $MTT::Values::Functions::current_report = $report;
                
                my $attachment = {};
                
                if ( $phase eq "Test Run" ) 
				{

                    my $mpi_install = $entries->{"MPI Install"}->{$report->{mpi_install_section_name}};
                    my $mpi_report = @$mpi_install[0];
                    
                    _process_phase_mpi_install("MPI Install", $report->{mpi_install_section_name}, $mpi_report, $form->{modules});

                    my $test_build = $entries->{"Test Build"}->{$report->{test_build_section_name}};
                    my $build_report = @$test_build[0];
                    _process_phase_test_build("Test Build", $report->{test_build_section_name}, $build_report, $form->{modules});

                    _process_phase_test_run($phase, $section, $report, $form->{modules});
                    $attachment = $report->{files_to_copy};
                }
                elsif ( $phase eq "Test Build" ) 
				{
                    my $mpi_install = $entries->{"MPI Install"}->{$report->{mpi_install_section_name}};
                    my $mpi_report = @$mpi_install[0];
                    _process_phase_mpi_install("MPI Install", $report->{mpi_install_section_name}, $mpi_report, $form->{modules});

                    _process_phase_test_build($phase, $section, $report, $form->{modules});
                }
                elsif ( $phase eq "MPI Install" ) 
				{
                    _process_phase_mpi_install($phase, $section, $report, $form->{modules});
                }
                else 
				{
                    Debug("MTTMongoDB reporter: Phase: $phase Section: $section SKIPPED\n");
                    next;
                }
                
                $MTT::Values::Functions::current_report = undef;
                
                if ( ($submit_failed_results == 0) && ($report->{test_result} != 1) )
                {
					Warning("MTTMongoDB reporter: test result skipped. Reason: submit_failed_results=$submit_failed_results\n");
                    next;
                }

				if($enable_mongo == 1)
				{
               		if ( $phase eq "Test Run" )
					{
						my $sim_sec_name = $form->{'modules'}->{'MpiInfo'}->{'mpi_name'};
						my $product_version =  MTT::Values::Value($ini, "mpi install: $sim_sec_name", 'product_version');
						$product_version =~ m/(\d+\.)+\d+/;
						Debug("MongoDB reporter: product version = $&\n");
						Debug("MongoDB reporter: simple section name = $sim_sec_name\n");
						$form->{'modules'}->{'product'}->{'version'} = $&;
						$form->{'modules'}->{'product'}->{'name'} = MTT::Values::Value($ini, "MTT", 'INI_BASENAME');
						$form->{'modules'}->{'scratch'}->{'url'} = MTT::Values::Value($ini, "MTT", 'scratch_url') . '/';
						$form->{'modules'}->{'scratch'}->{'root'} = MTT::Values::Functions::scratch_root();
						$form->{'slurm_id'} = MTT::Values::Functions::getenv('SLURM_JOBID');
						if(MTT::Values::Value( $ini, "MTT", 'mode') eq 'codecov' ||  MTT::Values::Value( $ini, "MTT", 'pkg') eq 'codecov') 
						{
							$form->{'codecov'}=1;
						}
						
						if(!defined($MTT::Globals::Values->{'group_id'}))
						{
							$MTT::Globals::Values->{'group_id'} = $basis_db->insert($form);
							my $collection = $basis_db->find( { _id => $MTT::Globals::Values->{'group_id'} } );
							$form = $collection->next;
							$form->{'group_id'} = $MTT::Globals::Values->{'group_id'};
							if($basis_db->update({ _id => $MTT::Globals::Values->{'group_id'} },$form) != 1)
							{
								print "MongoDB reporter: something strange happens. It seems to be an error.\n";
								print "MongoDB reporter: prohibit to submit to mongodb.\n";
								$enable_mongo = 0;
							}
						}else
						{
							$form->{'group_id'} = $MTT::Globals::Values->{'group_id'};
							if(!defined($basis_db->insert($form)))
							{
								print "MongoDB reporter: cannot insert to mongo.\n";
								print "MongoDB reporter: prohibit to submit to mongodb.\n";
								$enable_mongo = 0;
							}
						}
					}
                	$submitted = 1;
					
				}			
            }
        }
        Verbose("MTTMongoDB reporter: submitted $phase to MongoDB\n")
            if ($submitted);
    }
	if(defined($path) && defined($to_xml))
	{
		unless(-d $path)
		{
			mkdir $path or Warning("MongoDB reporter: cannot create dir: $path.\nSummary xml file did not generate.\n");
		}
		open FILE, ">$path/output.xml" or Warning("MongoDB reporter: cannot create file: $path/output.xml.\nSummary xml file did not generate.\n");
		print FILE resolve_template($xml_template, keys %{$to_xml}, values %{$to_xml});
		close(FILE);
	}else
	{
		Warning("MongoDB reporter: xml_dir not defined, summary xml file did not generate\n");
	}
	if($enable_mongo == 1)
	{
		my $grid = $db->get_gridfs;
		my $act_file_name = MTT::Values::Functions::scratch_root();
		print "MongoDB reporter: ";
		print `cd $act_file_name && zip data *`;
		$act_file_name .= '/data.zip';
		print "MongoDB reporter: act_file_name=$act_file_name\n";
		my $fh = IO::File->new("$act_file_name", "r");
		$grid->insert($fh, {"filename" => $MTT::Globals::Values->{'group_id'}});
	}
}

#--------------------------------------------------------------------------

sub _process_phase_mpi_install {
    my ( $phase, $section, $report, $form )=@_;
    $form->{MpiInstallPhase} = {};
    my $phase_form = $form->{MpiInstallPhase};
    
    _fill_submit_info( $phase, $section, $report, $form );
    _fill_compiler_info( $phase, $section, $report, $form );
    _fill_cluster_info( $phase, $section, $report, $form );
    _fill_mpi_info( $phase, $section, $report, $form );
    
    $phase_form->{start_time} = strftime( "%Y-%m-%d %H:%M:%S",
                        localtime $report->{start_timestamp} );

    my $duration = $report->{duration};
    $duration =~ m/^(\w+)\s(.+)/;
    $duration = $1;
    $phase_form->{duration} = $duration;

    $phase_form->{end_time} = strftime( "%Y-%m-%d %H:%M:%S",
                        localtime ($report->{start_timestamp} + $phase_form->{duration}) );

    $phase_form->{description} = $report->{description};
    $phase_form->{stdout} = $report->{result_stdout};
    $phase_form->{stderr} = $report->{result_stderr};
    $phase_form->{status} = $report->{test_result};
    $phase_form->{configuration} = $report->{configure_arguments};
            
    my $ini = $MTT::Globals::Internals->{ini};
    my $mpi_section = $report->{mpi_install_section_name};

    my $mpiget_section = MTT::Values::Value( $ini, "MPI install: " . $mpi_section, "mpi_get" );

    my $mpiget_module = MTT::Values::Value( $ini, "MPI get: " . $mpiget_section, "module" );

    if ($mpiget_module eq "AlreadyInstalled") {
        $phase_form->{mpi_path} = MTT::Values::Value( $ini, "MPI get: ". $mpiget_section, "alreadyinstalled_dir" );
        $phase_form->{mpi_path} = EvaluateString( $phase_form->{mpi_path}, $ini, "MPI get: ". $mpiget_section );
    } else {
        my $mpi_install = $MTT::MPI::installs->{$mpiget_section}->{$report->{mpi_version}}->{$mpi_section};
        $phase_form->{mpi_path} = $mpi_install->{installdir}; 
    }

    return 0;                      
}

#--------------------------------------------------------------------------

sub _process_phase_test_build {
    my ( $phase, $section, $report, $form )=@_;
    $form->{TestBuildPhase} = {};
    my $phase_form = $form->{TestBuildPhase};

    _fill_submit_info( $phase, $section, $report, $form );
    _fill_compiler_info( $phase, $section, $report, $form );
    _fill_cluster_info( $phase, $section, $report, $form );
    _fill_mpi_info( $phase, $section, $report, $form );
    _fill_suite_info( $phase, $section, $report, $form );
    
    $phase_form->{start_time} = strftime( "%Y-%m-%d %H:%M:%S",
                        localtime $report->{start_timestamp} );

    my $duration = $report->{duration};
    $duration =~ m/^(\w+)\s(.+)/;
    $duration = $1;
    $phase_form->{duration} = $duration;

    $phase_form->{end_time} = strftime( "%Y-%m-%d %H:%M:%S",
                        localtime ($report->{start_timestamp} + $phase_form->{duration}) );

    $phase_form->{description} = $report->{description};
    $phase_form->{stdout} = $report->{result_stdout};
    $phase_form->{stderr} = $report->{result_stderr};
    $phase_form->{status} = $report->{test_result};
                          
    return 0;                      
}

#--------------------------------------------------------------------------

sub _process_phase_test_run {
    my ( $phase, $section, $report, $form )=@_;
    $form->{TestRunPhase} = {};

    _pre_process_phase( $phase, $section, $report, $form );

    # copy benchmark's additional data about mpi (filled in benchmark's analyzer)
    %$form->{TestRunPhase} = ( %$report->{testphase} ) if (defined ($report->{testphase}));#!!!!!!!!!!!!
    my $phase_form = $form->{TestRunPhase};

    _fill_submit_info( $phase, $section, $report, $form );
    _fill_compiler_info( $phase, $section, $report, $form );
    _fill_cluster_info( $phase, $section, $report, $form );
    _fill_mpi_info( $phase, $section, $report, $form );
    _fill_suite_info( $phase, $section, $report, $form );

    $phase_form->{start_time} = strftime( "%Y-%m-%d %H:%M:%S",
                localtime $report->{start_timestamp} );

    my $duration = $report->{duration};
    $duration =~ m/^(\w+)\s(.+)/;
    $duration = $1;
    $phase_form->{duration} = $duration;

    $phase_form->{end_time} = strftime( "%Y-%m-%d %H:%M:%S",
                localtime ($report->{start_timestamp} + $phase_form->{duration}) );

    $phase_form->{description} = $report->{description};
    $phase_form->{stdout} = $report->{result_stdout};
    $phase_form->{stderr} = $report->{result_stderr};            
    $phase_form->{status} = $report->{test_result};
    $phase_form->{cmdline} = $report->{command};
    my @sections;
    push( @sections, "test run: " . $section );
    push( @sections, "MTT" );
    push( @sections, "VBench" );

    $phase_form->{test_name} = $report->{test_name} if (!defined($phase_form->{test_name}));

    $phase_form->{mpi_nproc}    = int($report->{np});
    $phase_form->{mpi_hlist} = MTT::Values::Functions::env_hosts(2);

    $phase_form->{net_note} = _get_value( "vbench:net_note", @sections );

    my $ini = $MTT::Globals::Internals->{ini};
    my @taglist = ();
    my @tagsections = (@sections);
    foreach my $tagsection (@tagsections) {
       my @val = MTT::Values::Value($ini,  $tagsection, "vbench:tag");
       if ( $#val != (-1) ) {
            @val = split(/\n/, $val[0]) if ($#val == 0);
            foreach (@val)
            {
                my $tag = $_;
                push( @taglist, $tag ) if ($tag);
            }
        }
    }
    @{$phase_form->{tag}} = @taglist;

    $phase_form->{test_case} = $report->{parameters}
        if ( !defined( $phase_form->{test_case} ) );

    # JMS Why do we have an mpi_mca field?  Shouldn't this kind of
    # stuff be in the MPI Details parameters and network fields?
    if (!defined($phase_form->{mpi_mca})) {
        # JMS Should generlize this to be "extract from the current
        # ::MPI::module".  There are other instances of this direct
        # call in MTT::Test::Analyze::Performance::*.
        $phase_form->{mpi_mca} = 
            MTT::Values::Functions::MPI::OMPI::find_mca_params($report->{command});

        if (!defined($phase_form->{mpi_rlist})) {
            my $rankfile = undef;
            my $cmdline  = $report->{command};
            if ( $cmdline =~ m/-rf\s([\S]+)/ ) {
                $rankfile = $1;
            }
            if ( $cmdline =~ m/--rankfile\s([\S]+)/ ) {
                $rankfile = $1;
            }
    	     $phase_form->{mpi_rlist} = $rankfile;
        }
    } else {
         if (!defined($phase_form->{mpi_rlist})) {
             $phase_form->{mpi_rlist} = "";
         }
    }

    if ( $phase_form->{mpi_rlist} ne "") {
        push(@{$report->{files_to_copy}}, $phase_form->{mpi_rlist});
    }

    # fill mpi_btl string list
    if ($phase_form->{mpi_mca} =~ m/-mca\sbtl\s(\S+)/) {
        @{$phase_form->{mpi_btl}} = split /,/, $1;
    } else {
        @{$phase_form->{mpi_btl}} = ();
    }
    
    # filling dynamic fields with prefix "data_"
    $phase_form->{data_message_size} = $report->{message_size} if (exists( $report->{message_size} ));
    $phase_form->{data_latency_min} = $report->{latency_min} if (exists( $report->{latency_min} ));
    $phase_form->{data_latency_avg} = $report->{latency_avg} if (exists( $report->{latency_avg} ));
    $phase_form->{data_latency_max} = $report->{latency_max} if (exists( $report->{latency_max} ));
    $phase_form->{data_bandwidth_min} = $report->{bandwidth_min} if (exists( $report->{bandwidth_min} ));
    $phase_form->{data_bandwidth_avg} = $report->{bandwidth_avg} if (exists( $report->{bandwidth_avg} ));
    $phase_form->{data_bandwidth_min} = $report->{bandwidth_min} if (exists( $report->{bandwidth_min} ));            

    # filling dynamic fields with prefix "custom_"

    # Special named export environment variables set in mpirun command line
    # should be stored as part of data in GDS datastore
    while ( $phase_form->{cmdline} =~ m/\s+-[x|e]\s+(custom_\w+)\=([^\s\"\']+)/g){
        my $value = $2;
        eval "\$value = \"$value\"";
        $phase_form->{$1} = $value;
    }
    while ( $phase_form->{cmdline} =~ m/\s+-[x|e]\s+(custom_\w+)\=\"([^\"]*)\"/g ){
        my $value = $2;
        eval "\$value = \"$value\"";
        $phase_form->{$1} = $value;
    }
    while ( $phase_form->{cmdline} =~ m/\s+-[x|e]\s+\"(custom_\w+)\=([^\"]*)\"/g){
        my $value = $2;
        eval "\$value = \"$value\"";
        $phase_form->{$1} = $value;
    }
    while ( $phase_form->{cmdline} =~ m/\s+-[x|e]\s+(custom_\w+)\=\'([^\']*)\'/g ){
        my $value = $2;
        eval "\$value = \"$value\"";
        $phase_form->{$1} = $value;
    }
    while ( $phase_form->{cmdline} =~ m/\s+-[x|e]\s+\'(custom_\w+)\=([^\']*)\'/g){
        my $value = $2;
        eval "\$value = \"$value\"";
        $phase_form->{$1} = $value;
    }
    
    # filling cached fields with prefix "cached_"
	#_fill_cached_info( $form );
                           
    return 0;                      
}

#--------------------------------------------------------------------------

sub _get_value {
    my $name     = shift @_;
    my @sections = @_;

    my $ini = $MTT::Globals::Internals->{ini};

    #    push (@sections, "MTT");
    #    push (@sections, "VBench");

    my $value = MTT::Values::Value( $ini, "VBench", $name );

    #   my $value = VBench::Values::getValueFromSections($ini, $name, @sections);

    return $value;
}

#--------------------------------------------------------------------------

sub _pre_process_phase {
    my ( $phase, $section, $report, $form )=@_;

    my $ini    = $MTT::Globals::Internals->{ini};
    my $module = $ini->val( "Test run: " . $section, "analyze_module" );

    # If there's no analyze module, then just return
    return $form
        if (!$module);

    $module = "MTT::Test::Analyze::Performance::$module";
    my $method = "PreReport";
    my @args   = ( $phase, $section, $report );

    Debug("Call PreReport on $module module.\n");

    my $str   = "require $module";
    my $check = eval $str;
    if ($@) {
        Warning("Could not load module $module: $@\n");
    } else {
        my $ret = undef;
        $str = "\$ret = exists(\$${module}::{$method})";
        eval $str;
        if (1 == $ret) {
            $ret = undef;
            $str   = "\$ret = \&${module}::$method(\@args)";
            $check = eval $str;
            if ($@) {
                Warning("Could not run module $module:$method: $@\n");
            }
        }
    }
    
    return $form;
}

#--------------------------------------------------------------------------

sub _fill_cached_info {
    my ( $form ) = @_;
    my $phase_form = $form->{TestRunPhase};
    my @info_list = ( "SubmitInfo", "ClusterInfo", "MpiInfo", "CompilerInfo", "SuiteInfo" );
    my @exception_list = ( "clusterinfo_net_conf", "clusterinfo_net_pci" );

    foreach my $info (@info_list) {
        foreach my $key (keys(%{$form->{$info}})) {
            $phase_form->{lc("cached\_$info\_$key")} = $form->{$info}->{$key};
        	foreach (@exception_list) {        		
        		if (lc("$_") eq lc("$info\_$key")) {
        			delete($phase_form->{lc("cached\_$info\_$key")});
        			last;
        		}
        	}
        }
    }

    $phase_form->{"cached_mpiinstallphase_mpi_path"} = $form->{MpiInstallPhase}->{mpi_path};

    return $phase_form;
}

#--------------------------------------------------------------------------

sub _fill_cluster_info {
    my ( $phase, $section, $report, $form ) = @_;
    $form->{ClusterInfo} = {};
    my $info_form = $form->{ClusterInfo};

    if ( !defined($report) ) {
        die "Runtime Error";
    }
    else {
            my @sections;
            push( @sections, "test run: " . $section );
            push( @sections, "MTT");
            push( @sections, "VBench");

            my $node_count =
                _get_value( "vbench:cluster_node_count", @sections );

            %$info_form = (%$info_form, %$clusterInfo);

            delete $info_form->{total_mhz};

            if (defined($node_count) && $node_count ne "") {
                $info_form->{node_count} = $node_count;     
            }       

			my $clust_name = `hostname`;
			$clust_name =~ m/\D+/;
			$info_form->{cluster_name} = $&;

			open FILE, '/proc/cpuinfo';
			my $cache;
			my $ncpu=0;	
			my $mhz;
			while (<FILE>) 
			{	
				if ($_ =~ m/processor/)
				{
					$ncpu++;
				}
				if($_ =~m/cpu MHz\s*:/)
				{
					$_ =~ m/\d+[\.\,]*\d*\D*/;
					$mhz = $&;
				}
				if($_ =~m/cache size\s*: /)
				{
					$_ =~ m/\d+[\.\,]*\d*\D*/;
					$cache = $&;
				}
			}
			close FILE;
			
			open FILE, '/proc/meminfo';
			my $mem;
			while (<FILE>) 
			{	
				if($_ =~m/MemTotal/)
				{
					$_ =~ m/\d+[\.\,]*\d*\D*/;
					$mem = $&;
				}
			}
			close FILE;
			
			open FILE, '/proc/net/sockstat';
			my $nsocket;
			while (<FILE>) 
			{	
				if($_ =~m/sockets: used \d+/)
				{
					$_ =~ m/\d+[\.\,]*\d*\D*/;
					$nsocket = $&;
				}
			}
			close FILE;
			
			$info_form->{node_os_vendor} = `cat /proc/version`;
			$info_form->{node_nsocket} = $nsocket; 
			$info_form->{node_mem} = $mem;
			$info_form->{node_ncpu} = $ncpu;
			$info_form->{node_cache} = $cache;
			$info_form->{node_mhz} = $mhz;
			$info_form->{node_os_kernel} = `uname -s`;
			$info_form->{node_os_release} = `uname -r -v`;
			$info_form->{node_arch} = `uname -p`;
			$info_form->{ofed_info} = `ofed_info | head -1`;
			
			my $cap_output = `ibv_devinfo | head -3`;
			if($cap_output =~m/fw_ver:\s+\d+([\.\,]\d+)*/)
			{	
				$cap_output = $&;
				$cap_output =~ m/\d+([\.\,]\d+)*/;
			    $info_form->{ib_card_firmware_version}=$&;
			}
			my $cap_output = `ibv_devinfo -v`;
			if($cap_output =~m/active_width:\s+\d+X/)
			{
				$cap_output = $&;
				$cap_output =~ m/\d+/;
			    if($& eq "1")
				{
					$info_form->{card_type} = 'sdr';
				}elsif($& eq "2")
				{
					$info_form->{card_type} = 'ddr';
							
				}elsif($& eq "4")
				{
					$info_form->{card_type} = 'qdr';

							
				}elsif($& eq "14")
				{
					$info_form->{card_type} = 'fdr';
				}else
				{
					$info_form->{card_type} = 'unknow';
				}

			}

    }

    return $info_form;
}

#--------------------------------------------------------------------------

sub _fill_mpi_info {
    my ( $phase, $section, $report, $form ) = @_;
    $form->{MpiInfo} = {};
    # copy benchmark's additional data about mpi (filled in benchmark's analyzer)
    %$form->{MpiInfo} = ( %$report->{mpi} ) if (exists ($report->{mpi}));#!!!!!!!!!!!!
    my $info_form = $form->{MpiInfo};

    if ( !defined($report) ) {
        die "Runtime Error";
    }
    else {
        my @sections;
        push( @sections, "test run: " . $section );

        my @mpi_name_parts =
              split( /:/, $report->{mpi_install_section_name}, 1 );
        $info_form->{mpi_name} = @mpi_name_parts[0];
        
        $info_form->{mpi_version} = $report->{mpi_version};

        my $mpi_path;
        my $ini = $MTT::Globals::Internals->{ini};
        my $mpi_section = $report->{mpi_install_section_name};

        my $mpiget_section = MTT::Values::Value( $ini, "MPI install: " . $mpi_section, "mpi_get" );

        my $mpiget_module = MTT::Values::Value( $ini, "MPI get: " . $mpiget_section, "module" );

        if ($mpiget_module eq "AlreadyInstalled") {
            $mpi_path = MTT::Values::Value( $ini, "MPI get: ". $mpiget_section, "alreadyinstalled_dir" );
            $mpi_path = EvaluateString( $mpi_path, $ini, "MPI get: ". $mpiget_section );
        } else {
            my $mpi_install = $MTT::MPI::installs->{$mpiget_section}->{$report->{mpi_version}}->{$mpi_section};
            $mpi_path = $mpi_install->{installdir}; 
        }

        my $error = 0;
        my $cmd = "LD_LIBRARY_PATH=" . $mpi_path . "/lib " . $mpi_path . "/bin/mpirun --version";
        open(SHELL, "$cmd 2>&1|") || ($error = 1);
        $info_form->{oma_version} = "";
        if ($error == 0) {
            while (<SHELL>) {
                if ( $_ =~ m/OMA\s+([r\d\.-]+)\s/) {
                    $info_form->{oma_version} = $1;
                    last;
                }
            }
            close SHELL;
        } # $error = 0
        else {
            $error = 0;
        }

        # Add host file to "copy list"
        if ( MTT::Values::Functions::have_hostfile() ) {
            my $hostFile = MTT::Values::Functions::hostfile();
            push(@{$report->{files_to_copy}}, $hostFile);
        }
    }
    return $info_form;
}

#--------------------------------------------------------------------------

sub _fill_suite_info {
    my ( $phase, $section, $report, $form ) = @_;
    $form->{SuiteInfo} = {};
    # copy benchmark's additional data about benchmark suite (filled in benchmark's analyzer)
    %$form->{SuiteInfo} = ( %$report->{suiteinfo} ) if (exists ($report->{suiteinfo}));#!!!!!!!!!!!!
    my $info_form = $form->{SuiteInfo};

    if ( !defined($report) ) {
        die "Runtime Error";
    }
    else {
        my @sections;
        push( @sections, "test run: " . $section );

        my $suite_name = undef;
        my $suite_version = undef;

        my $test_run = $section;
        if ( $test_run =~ m/^(\S+):(\S+)/ ) {
            $suite_name    = $1;
            $suite_version = $2;
        }
        else {
            if ( $test_run =~ m/^(\S+)\s(.+)$/ ) {
                $suite_name    = $1;
                $suite_version = "undefined";
            }
            else {
                $suite_name    = $test_run;
                $suite_version = "undefined";
            }
        }
        $info_form->{suite_name}    = $suite_name if (!defined($info_form->{suite_name}));
        $info_form->{suite_version} = $suite_version if (!defined($info_form->{suite_version}));

    }
    return $info_form;
}

#--------------------------------------------------------------------------

sub _fill_submit_info {
    my ( $phase, $section, $report, $form ) = @_;
    $form->{SubmitInfo} = {};
    my $info_form = $form->{SubmitInfo};

    if ( !defined($report) ) {
        die "Runtime Error";
    }
    else {
	    if (!$local_username) {
	        $local_username = getpwuid($<);
	    }
	
	    if (!defined($hostname) || "" eq $hostname) {
	        $hostname = `hostname`;
	        chomp($hostname);
	    }
    
        $info_form->{hostname} = $hostname;
        $info_form->{local_username} = $local_username;
        $info_form->{http_username} = $username;
        $info_form->{mtt_version} = $MTT::Version::Combined;
    }
    return $info_form;
}

#--------------------------------------------------------------------------

sub _fill_compiler_info {
    my ( $phase, $section, $report, $form ) = @_;
    $form->{CompilerInfo} = {};
    my $info_form = $form->{CompilerInfo};

    if ( !defined($report) ) {
        die "Runtime Error";
    }
    else {
        $info_form->{compiler_name} = "unknown";
        $info_form->{compiler_name} = $report->{compiler_name} if (defined($report->{compiler_name}));
        $info_form->{compiler_version} = "unknown";
        $info_form->{compiler_version} = $report->{compiler_version} if (defined($report->{compiler_version}));
   }
    return $info_form;
}
1;
