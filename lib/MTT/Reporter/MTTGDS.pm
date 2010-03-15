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

package MTT::Reporter::MTTGDS;

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
use YAML::XS;

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

    Debug("[MTTGDS reporter] Init\n");

    # Have we been initialized already?  If so, error -- per #261,
    # this module can currently only handle submitting to one database
    # in a given run.

    if (defined($username)) {
        Error("The MTTGDS plugin can only be used once in an INI file.\n");
    }

    # Extract data from the ini fields

    $username = Value($ini, $section, "mttdatabase_username");
    $password = Value($ini, $section, "mttdatabase_password");
    $url = Value($ini, $section, "mttdatabase_url").'client';
    $realm = Value($ini, $section, "mttdatabase_realm");
    $hostname = Value($ini, $section, "mttdatabase_hostname");
    $local_username = Value($ini, "mtt", "local_username");

    if (!$url) {
        Warning("Need URL in MTTGDS Reporter section [$section]\n");
        return undef;
    }
    my $count = 0;
    ++$count if ($username);
    ++$count if ($password);
    ++$count if ($realm);
    if ($count > 0 && $count != 3) {
        Warning("MTTGDS Reporter section [$section]: if password, username, or realm is specified, they all must be specified.\n");
        return undef;
    }
    $platform = Value($ini, $section, "mttdatabase_platform");

    # Extract the host and port from the URL.  Needed for the
    # credentials section.

    my $dir;
    my $host = $url;
    if ($host =~ /(http:\/\/[-a-zA-Z0-9.]+):(\d+)\/?(.*)?$/) {
        $host = $1;
        $port = $2;
        $dir = $3;
    } elsif ($host =~ /(http:\/\/[-a-zA-Z0-9.]+)\/?(.*)?$/) {
        $host = $1;
        $dir = $2;
        $port = 80;
    } elsif ($host =~ /(https:\/\/[-a-zA-Z0-9.]+)\/?(.*)?$/) {
        $host = $1;
        $dir = $2;
        $port = 443;
    } elsif  ($host =~ /(https:\/\/[-a-zA-Z0-9.]+):(\d+)\/?(.*)?$/) {
        $host = $1;
        $port = $2;
        $dir = $3;
    } else {
        Warning("MTTGDS Reporter did not get a valid url: $url .\n");
        return undef;
    }
    $url = "$host:$port/$dir";

    # Setup proxies
    my $scheme = (80 == $port) ? "http" : "https";

    # Create the Perl LWP stuff to setup for HTTP requests later.
    # Make one for each proxy (we'll always have at least one proxy
    # entry, even if it's empty).
    my $proxies = \@{$MTT::Globals::Values->{proxies}->{$scheme}};
    foreach my $p (@{$proxies}) {
        my %params = { env_proxy => 0 };
        my $ua = LWP::UserAgent->new(%params);
        
        # @#$@!$# LWP proxying for https *does not work*.  So
        # don't set $ua->proxy() for it.  Instead, we'll set
        # $ENV{https_proxy} whenever we process requests that
        # require SSL proxying, because that is obeyed deep down
        # in the innards underneath LWP.
        $ua->proxy([$scheme], $p->{proxy})
            if ($p->{proxy} ne "" && $scheme ne "https");
        $ua->agent("MPI Test MTTGDS Reporter");
        push(@lwps, {
            scheme => $scheme,
            agent => $ua,
            proxy => $p->{proxy},
            source => $p->{source},
        });
    }
    if ($realm && $username && $password) {
        Verbose("   Set HTTP credentials for realm \"$realm\"\n");
    }

    # Do a test ping to ensure that we can reach this URL.

    Debug("MTTGDS client pinging a server...\n");
    my $form = {
        PING => 1,
        Description => 'Pinging a server'
    };
    my $req = POST ($url, $form);
    $req->authorization_basic($username, $password);
    my $response = _do_request($req);
    if (! $response->is_success()) {
        Warning(">> Failed test ping to MTTGDS URL: $url\n");
        Warning(">> Error was: " . $response->status_line . "\n" . 
                $response->content);
        Error(">> Do not want to continue with possible bad submission URL -- aborting\n");
    }

    Debug("MTTGDS reporter initialized ($realm, $username, XXXXXX, $url, $platform)\n");
    Debug("MTTGDS reporter respond content ($response->content)\n");

    # Extract data from the ini fields

    $dirname = MTT::DoCommand::cwd();

    Debug("Collect cluster information...\n");
    my $clusterinfo_module = MTT::Values::Value($ini, "vbench", "clusterinfo_module");
    $clusterinfo_module = "ClusterInfo" if (!defined($clusterinfo_module) || $clusterinfo_module eq "");
    Debug("Use $clusterinfo_module module to collect information.\n");
    
    $clusterInfo = MTT::Module::Run("MTT::Reporter::Utils::$clusterinfo_module", "get_cluster_info", MTT::Values::Functions::env_hosts(2));
    if (!defined($clusterInfo)) {
        Error("Fatal: Can't collect cluster information\n");
    }
    Debug("Collect cluster information Finished\n");
    
    Debug("File reporter initialized ($dirname)\n");

    return 1;
}

#--------------------------------------------------------------------------

my $entries;

sub Submit {
    my ( $info, $newentries ) = @_;

    Debug("[MTTGDS reporter] Submit\n");

    if (!defined($newentries)) {
        Warning("[MTTGDS reporter]: Submit parameter is undef. Skip.\n");
        return;
    }
    
    if ( !defined($entries) ) {
        %$entries = ();
    }

    foreach my $phase (keys(%$newentries)) {
        my $phase_obj = $newentries ->{$phase};

        foreach my $section ( keys(%$phase_obj) ) {
           Debug("Phase: $phase Section: $section\n");

           my $new_section_obj = $phase_obj->{$section};

           my $section_obj = $entries->{$phase}->{$section};

           foreach my $report (@$new_section_obj) {
               Debug("  add report\n");
               push(@$section_obj, $report);
           }

           $entries->{$phase}->{$section} = $section_obj;
       }
    }

    Verbose(">> Reporter MTTGDS: cached for later submit\n");
    Debug("[MTTGDS reporter] Exit from Submit\n");
}

sub Finalize {
    Debug("[MTTGDS reporter] Finalize\n");
    
    _do_submit();
    undef $entries;
	
    undef $username;
    undef $password;
    undef $realm;
    undef $url;
    undef $platform;
    undef @lwps;    
}

#--------------------------------------------------------------------------

sub _do_submit {
    # Make a default form that will be used to seed all the forms that
    # will be sent
    my $default_form = {
        product => 'mtt-gds',
        version => "0.1",
        app_id  => 'submit',
    };

    my $ini = $MTT::Globals::Internals->{ini};
    my $submit_failed_results = MTT::Values::Value( $ini, "VBench", 'submit_failed_results_to_gds' );

    # mtt ini flag to control what mtt results to submit to GDS
    if (!defined($submit_failed_results) || $submit_failed_results eq '')
    {
        $submit_failed_results = 1;
    }
    
    #foreach my $phase (keys(%$entries)) {
    foreach my $phase ( "MPI Install", "Test Build", "Test Run" ) {
        my $submitted = 0;
        my $phase_obj = $entries->{$phase};

        foreach my $section ( keys(%$phase_obj) ) {
            my $section_obj = $phase_obj->{$section};

            foreach my $report_original (@$section_obj) {

                # Each section of a phase gets its own report to the
                # database.  Make a deep copy of the default form to start
                # with.
                my $form;
                %$form = %{$default_form};
                $form->{modules} = {};
 
                # Ensure to do a deep copy of the report (vs. just
                # copying the reference) because we want to locally
                # change some values
                my $report;
                %$report = %{$report_original};
                %$report->{files_to_copy} = {} if (!exists($report->{files_to_copy}));

                $MTT::Values::Functions::current_report = $report;
                
                my $attachment = {};
                
                if ( $phase eq "Test Run" ) {
                    my $mpi_install = $entries->{"MPI Install"}->{$report->{mpi_install_section_name}};
                    my $mpi_report = @$mpi_install[0];
                    
                    _process_phase_mpi_install("MPI Install", $report->{mpi_install_section_name}, $mpi_report, $form->{modules});

                    my $test_build = $entries->{"Test Build"}->{$report->{test_build_section_name}};
                    my $build_report = @$test_build[0];
                    _process_phase_test_build("Test Build", $report->{test_build_section_name}, $build_report, $form->{modules});

                    _process_phase_test_run($phase, $section, $report, $form->{modules});
                    $attachment = $report->{files_to_copy};
                }
                elsif ( $phase eq "Test Build" ) {
                    my $mpi_install = $entries->{"MPI Install"}->{$report->{mpi_install_section_name}};
                    my $mpi_report = @$mpi_install[0];
                    _process_phase_mpi_install("MPI Install", $report->{mpi_install_section_name}, $mpi_report, $form->{modules});

                    _process_phase_test_build($phase, $section, $report, $form->{modules});
                }
                elsif ( $phase eq "MPI Install" ) {
                    _process_phase_mpi_install($phase, $section, $report, $form->{modules});
                }
                else {
                    Debug("Phase: $phase Section: $section SKIPPED\n");
                    next;
                }
                
                $MTT::Values::Functions::current_report = undef;

                Debug("Submitting to MTTGDS...\n");
	            
                my ($req, $file) = _prepare_request($phase, $report, $form, $attachment);
                
                # do not submit result with non PASS status in case 'submit_failed_results_to_gds' key is set as '0'
                if ( ($submit_failed_results == 0) && ($report->{test_result} != 1) )
                {
                    Debug("MTT ini-file has key \'submit_failed_results_to_gds\'=$submit_failed_results and phase: $phase test_result: $report->{test_result}\n");
                    next;
                }
                
                my $response = _do_request($$req);
                #unlink($file);            
                $submitted = 1;
            }
        }
        Verbose(">> Submitted $phase to GDS\n")
            if ($submitted);
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
    while ( $phase_form->{cmdline} =~ m/\s+-x\s+(custom_\w+)\=([^\s\"\']+)/g){
        $phase_form->{$1} = $2;
    }
    while ( $phase_form->{cmdline} =~ m/\s+-x\s+(custom_\w+)\=\"([^\"]*)\"/g ){
        $phase_form->{$1} = $2;
    }
    while ( $phase_form->{cmdline} =~ m/\s+-x\s+\"(custom_\w+)\=([^\"]*)\"/g){
        $phase_form->{$1} = $2;
    }
    while ( $phase_form->{cmdline} =~ m/\s+-x\s+(custom_\w+)\=\'([^\']*)\'/g ){
        $phase_form->{$1} = $2;
    }
    while ( $phase_form->{cmdline} =~ m/\s+-x\s+\'(custom_\w+)\=([^\']*)\'/g){
        $phase_form->{$1} = $2;
    }
    
    # filling cached fields with prefix "cached_"
    _fill_cached_info( $form );
                           
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

            $info_form->{cluster_name} = $platform;

            my $node_count =
                _get_value( "vbench:cluster_node_count", @sections );

            %$info_form = (%$info_form, %$clusterInfo);

            delete $info_form->{total_mhz};

            if (defined($node_count) && $node_count ne "") {
                $info_form->{node_count} = $node_count;     
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
        open(SHELL, $mpi_path . "/bin/mpirun --version 2>&1|") || ($error = 1);
        $info_form->{oma_version} = "";
        if ($error == 0) {
            while (<SHELL>) {
                if ( $_ =~ m/OMA\s+([r\d\.]+)\s/) {
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
        $info_form->{mtt_version} = "TODO";
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

#--------------------------------------------------------------------------

sub _do_request {
    my $req = shift;

    # Ensure that the environment is clean so that nothing happens
    # that we're unaware of.
    my %ENV_SAVE = %ENV;
    delete $ENV{http_proxy};
    delete $ENV{https_proxy};
    delete $ENV{HTTP_PROXY};
    delete $ENV{HTTPS_PROXY};

    # Go through each ua and try to get a good connection.  If we get
    # connection refused from any of them, try another.
    my $response;
    foreach my $ua (@lwps) {
        Debug("MTTGDS client trying proxy: $ua->{proxy} / $ua->{source}\n");
        $ENV{https_proxy} = $ua->{proxy}
            if ("https" eq $ua->{scheme});

        # Do the HTTP request
        $response = $ua->{agent}->request($req);

        # If it succeeded, or if it failed with something other than
        # code 500, return (code 500 = can't connect)
        if ($response->is_success() ||
            $response->code() != 500) {
            Debug("MTTGDS proxy successful / not 500\n");
            %ENV = %ENV_SAVE;
            return $response;
        }
        Debug("MTTGDS proxy unsuccessful -- trying next\n");

        # Otherwise, loop around and try again
        Debug("Proxy $ua->{proxy} failed code: " .
              $response->status_line . "\n" . $response->content . "\n");
    }

    # Sorry -- nothing got through...
    Debug("MTTGDS proxy totally unsuccessful\n");
    %ENV = %ENV_SAVE;
    return $response;
}

#--------------------------------------------------------------------------

# Create test file results, and prepare the HTTP file upload
# request

my $request_count = 0;

sub _prepare_request {
    my ($phase, $report, $form, $attachment )=@_;

    my $ini = $MTT::Globals::Internals->{ini};
    my $repository_path = MTT::Values::Value( $ini, "VBench", 'repository_tempdir' );
    my $repository_name = MTT::Values::Value( $ini, "VBench", 'repository_dirname_prefix' );
    my ($fh, $filename);
    my $tmpdir;

    # Find a temporary directory for files
    if (!defined($repository_path) || $repository_path eq '')
    {
        $tmpdir = tempdir( CLEANUP => 1);
        ($fh, $filename) = tempfile( DIR => $tmpdir, SUFFIX => '.yaml' );
    }
    elsif  (!defined($repository_name) || $repository_name eq '')
    {
    	MTT::Files::mkdir($repository_path) if (! -d $repository_path);
    	$tmpdir = tempdir( DIR => "$repository_path", CLEANUP => 0);
        ($fh, $filename) = tempfile( DIR => $tmpdir, SUFFIX => '.yaml' );
    }
    else
    {
        $request_count++;
        MTT::Files::mkdir($repository_path) if (! -d $repository_path);
        $tmpdir = "${repository_path}/${repository_name}_${request_count}";    
        $filename = "$tmpdir/${repository_name}_${request_count}.yaml";    
    }
        
    my $raw_filename = ();

    MTT::Files::mkdir($tmpdir);
    
    if ( keys %$attachment ) {
        foreach my $file (keys %$attachment) {
            Debug ("    Attachment: $file\n");
            MTT::Values::Functions::shell("cp -r $file $tmpdir/$attachment->{$file}");
            }
        $raw_filename = "$tmpdir/data_file.zip";
    }

    # Generate YAML file contents
    YAML::XS::DumpFile("$filename", $form);
    
    if ( $raw_filename ne '')
    {
        MTT::Values::Functions::shell(
                   "cd $tmpdir; zip -9 -r $raw_filename *");
    }
       
    # Chech Google Datastore put entity limitation
    $raw_filename = '' if  1048576 <= ((-s "$raw_filename") + (-s "$filename"));

    my $req;
    # Create the "upload" POST request
    if (-e $raw_filename)
    {
	    $req = POST $url,
	        Content_Type => 'form-data',
	        Content => [
	            SUBMIT      => 1,
	            data        => ["$filename"],
	            raw         => ["$raw_filename"],
	            description => "Submit data and raw on the phase <$phase>"
	         ];
    }
    else
    {
        $req = POST $url,
            Content_Type => 'form-data',
            Content => [
                SUBMIT      => 1,
                data        => ["$filename"],
                description => "Submit data only on the phase <$phase>"
             ];
    }

    $req->authorization_basic($username, $password);

    return (\$req, $filename);
}

1;
