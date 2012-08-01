#!/usr/bin/perl
#
# Copyright (c) 2009
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#
# Now that @INC is setup, bring in the modules

#use strict;
#use warnings;
use LWP::UserAgent;
use HTTP::Request::Common;
use Data::Dumper;
use File::Basename;
use File::Temp;
use Config::IniFiles;
use YAML::XS;
use MongoDB;
use MongoDB::OID;
use YAML;
use YAML::Syck;
use DateTime;

###########################################################
# Set variables
###########################################################
my $module_name=$0;
my $module_path=$0;

$module_name=~s/([^\/\\]+)$//;
$module_name=$1;
 
$module_path=~s/([^\/\\]+)$//;


###########################################################
# Main block
###########################################################
use Getopt::Long qw(:config no_ignore_case);

my $opt_help;
my $opt_server;
my $opt_username;
my $opt_password;

my $opt_ping;
my $opt_upload;
my $opt_query;
my $opt_view;
my $opt_admin;

my @opt_data;
my @opt_raw;

my $opt_gqls;
my @opt_gqlf;
my @opt_section;
my $opt_dir;
my $opt_no_raw;

my $opt_dstore;
my $opt_info;
my $opt_format;
my $opt_mailto;
my $opt_regression_from;
my $opt_regression_to;
my $opt_regression_step;

my @opt_newuser;

GetOptions ("help|h" => \$opt_help,
            "server|a=s" => \$opt_server,
            "username|u=s" => \$opt_username,
            "password|p=s" => \$opt_password,
            "ping" => \$opt_ping,
            "upload" => \$opt_upload,
            "query" => \$opt_query,
            "view" => \$opt_view,
            "admin" => \$opt_admin,
            
            "data|S=s" => \@opt_data,
            "raw|R=s" => \@opt_raw,         
            
            "gqls|L=s" => \$opt_gqls,
            "gqlf|F=s" => \@opt_gqlf,
            "section|T=s" => \@opt_section,
            "dir|O=s" => \$opt_dir,
            "no-raw" => \$opt_no_raw,

            "dstore|D" => \$opt_dstore,
            "info|I=s" => \$opt_info,
            "format|V=s" => \$opt_format,
            "email|e=s" => \$opt_mailto,

            "newuser=s{3,5}" => \@opt_newuser,

			"regression-from=s" => \$opt_regression_from,
			"regression-to=s" => \$opt_regression_to,
			"regression-step=s" => \$opt_regression_step
            );


my $url = ();
my $username = ();
my $password = ();

$url = $opt_server ? $opt_server : "http://bgate.mellanox.com:27017";
$url =~ s/http:\/\///;
$username = $opt_username ? $opt_username : "admin";
$password = $opt_password ? $opt_password : "";

my %conf = ('url' => "$url\/client",
            'username' => $username,
            'password' => $password
            );

if ($opt_help)
{
    my $action = '';
	
    $action = 'ping' if ($opt_ping);
    $action = 'upload' if ($opt_upload);
    $action = 'query' if ($opt_query);
    $action = 'view' if ($opt_view);
    $action = 'admin' if ($opt_admin);

    help($action);
    
    exit;
}
elsif ($opt_ping)
{
	#ping( \%conf ); 
	#print $url," url\n";
	my $conn = MongoDB::Connection->new(host => $url );
	if($conn != 0)
	{
		print"\n\nping: success\n\n";
	}
}
elsif ($opt_upload)
{
    if ($#opt_data < 0) 
    {
        help('upload');
    }
	my @data = split(/,/,join(',',@opt_data)) if (@opt_data);
	my @raw = split(/,/,join(',',@opt_raw)) if (@opt_raw);
    
    # Check if files existed
	verify_opt_file( @data );
	verify_opt_file( @raw );

	$conf{data} = \@data;
	$conf{raw} = \@raw;  

	upload( \%conf ); 
}
elsif ($opt_query)
{
    my $gql = ();
    if ($opt_gqls) 
    {
        $gql = $opt_gqls;
    }
    else
    {
        help('query');
    }
	#print $gql, " before\n";
	$gql =~ s/\s+/ /g;
	$gql =~ s/ /#/g;
	$gql =~ s/And/AND/g;
	$gql =~ s/and/AND/g;
	$gql =~ s/Or/OR/g;
	$gql =~ s/or/OR/g;
	$gql =~ s/#In#/IN/g;
	$gql =~ s/#in#/IN/g;
	$gql =~ s/Not/NOT/g;
	$gql =~ s/not/NOT/g;
	$gql =~ s/#AND#/ AND /g;
	$gql =~ s/#OR#/ \| /g;
	#$gql =~ s/#IN#/IN/g;
	$gql =~ s/#NOT/NOT/g;
	$gql =~ s/#=#/=/g;
	$gql =~ s/#>#/>/g;
	$gql =~ s/#>=#/>=/g;
	$gql =~ s/#<#/</g;
	$gql =~ s/#<=#/<=/g;
	#print $gql," after\n";
	#exit;

	my @date_array;
	if($gql =~ m/=>|=</)
	{
			print "\nError:\nInvalid format: \"=>\" or \"=<\"\nUse \">=\" or \"<=\" instead\n";
			exit;
	}

	if($opt_regression_step)
	{
		if($opt_regression_step =~ m/^\d{4}-\d{2}-\d{2}$/)
		{
			#print "ok $opt_regression_step \n";
		}else
		{
			die "\nparametr \"regression-step\" has invalid format. YYYY-MM-DD\nexample --regression-step=\'0000-01-03\'";
		}
	
		if($gql =~ m/TestRunPhase\.start_time/)
		{
			$str_start_time = $';
			if($str_start_time =~ m/\d{4}-\d{2}-\d{2}#\d{2}:\d{2}:\d{2}/)
			{
				$str_start_time = $&;
			}else
			{
				die "synrax error";
			}
		}else
		{
			die "syntax error";
		}
	
		if($gql =~ m/TestRunPhase\.end_time/)
		{
			$str_end_time = $';
			if($str_end_time =~ m/\d{4}-\d{2}-\d{2}#\d{2}:\d{2}:\d{2}/)
			{
				$str_end_time = $&;
			}else
			{
				die "syntax error";
			}
		}else
		{
			die "syntax error";
		}
	
		#print "start_time $str_start_time end_time $str_end_time \n";
	
		my $timezone = DateTime->now;

		@numbers = split(/:|-|#/,$str_start_time);
		#print @numbers[0],"-year " , @numbers[1], "-month ",  @numbers[2], "-day ",  @numbers[3],"-hour " ,  @numbers[4] ,"-min ",   @numbers[5],"-sec\n";
		my %hash_start_time = (year => @numbers[0],month => @numbers[1],day => @numbers[2],hour => @numbers[3],minute => @numbers[4],second => @numbers[5],nanosecond => 0,time_zone=> $timezone->time_zone());
		my $DateTime_start_time = DateTime->new(%hash_start_time);

		@numbers = split(/:|-|#/,$str_end_time);
		#print @numbers[0],"-year " , @numbers[1], "-month ",  @numbers[2], "-day ",  @numbers[3],"-hour " ,  @numbers[4] ,"-min ",   @numbers[5],"-sec\n";
		my %hash_end_time = (year => @numbers[0],month => @numbers[1],day => @numbers[2],hour => @numbers[3],minute => @numbers[4],second => @numbers[5],nanosecond => 0,time_zone=> $timezone->time_zone());
		my $DateTime_end_time = DateTime->new(%hash_end_time);


		print "\n\nacceptable dates:\n";
		my $count = 1;
		my @arg_to_subtract = split(/-/,$opt_regression_step);
		#print "\n\n@arg_to_subtract\n\n";
		while(DateTime->compare( $DateTime_start_time, $DateTime_end_time )!=1)
		{

			$DateTime_end_time->subtract(years=> @arg_to_subtract[0],months=>@arg_to_subtract[1],days =>@arg_to_subtract[2]);
			my $month = $DateTime_end_time->month();
			my $day = $DateTime_end_time->day();
			if(!($day =~ m/\d{2}/))
			{
				$day = "0".$day;
			}
			if(!($month =~ m/\d{2}/))
			{
				$month = "0".$month;
			}
			$str = $DateTime_end_time->year() . "-" . $month . "-" . $day; 
			push(@date_array,$str);
			print "$str  ";
			if($count % 7  == 0)
			{
				print"\n";
			}
			$count++;

		}
		#print"\n\n @date_array\n\n";
	}
	#print "hash start_time ", $DateTime_start_time,  " hash end_time ", $DateTime_end_time, "\n";
	#print "time zone ",$timezone,"\n";

	my $query_to_mongo = string2query($gql);
	$query_to_mongo .= ";";
	print "\n\n**********************************************************************query to mongo*************************************************************************";
	print "\n",$query_to_mongo,"\n";
	print "*************************************************************************************************************************************************************\n";
	######################################################################
	#mongo
	#######################################################################
	my $conn = MongoDB::Connection->new(host => $url);
	my $db = $conn->mtt;
	my $mtt_result = $db->TestRunPhase;
	my $all_result = $mtt_result->find(eval $query_to_mongo);	
	my $i = 0;
	if($opt_regression_step)
	{
		while (my $doc = $all_result->next)
		{
			if($doc->{"modules"}->{"TestRunPhase"}->{"start_time"} =~ m/\d{4}-\d{2}-\d{2}/)
			{
				if ($& ~~ @date_array)
				{
					open F, '>', "$i.yaml";
					print F YAML::Syck::Dump( $doc );
					close F;
					$i++;
				}
			}
			else
			{
				die "something strange happened";
			}

		}
	}else
	{
		while (my $doc = $all_result->next)
		{
	
			open F, '>', "$i.yaml";
			print F YAML::Syck::Dump( $doc );
			close F;
			$i++;
		}

	}
	print "found $i documents\n";
	######################################################################
	#mongo
	######################################################################

}
elsif ($opt_view)
{
	if ($opt_gqls) 
	{
	#    $conf{gql} = $opt_gqls;
	}
	elsif (@opt_gqlf && @opt_section && (@opt_gqlf == @opt_section)) 
	{
	#    my $gql = ();
	#    my @a_select;
	#    my $v_from;
	#    my @a_where;
	#    my @a_order;
	#    my $v_limit;
	#    my $v_offset;
	#    my $i = 0;
	#   
	#   my @files=split(/,/,join(',',@opt_gqlf)) if (@opt_gqlf);
	#   my @sections=split(/,/,join(',',@opt_section)) if (@opt_section);
	#   
	#   # Check if files existed
	#   verify_opt_file( @files );
	#   
	#   for($i=0; $i < @files; $i++)
	#   {
	#       # Use ini-file in case it is set in command line
	#       my $cfg = new Config::IniFiles( -file => "$files[$i]", -nocase => 1 );
	#       if (not defined $cfg or $@) 
	#       {
	#           die "$!";
	#       }
	#       $opt_format = $cfg->val("$sections[$i]", 'format') if ($cfg->val("$sections[$i]", 'format'));
	#
	#       my @a_temp_select = $cfg->val("$sections[$i]", 'select') if ($cfg->val("$sections[$i]", 'select'));
	#       my $v_temp_from = $cfg->val("$sections[$i]", 'from') if ($cfg->val("$sections[$i]", 'from'));
	#       my @a_temp_where = $cfg->val("$sections[$i]", 'where') if ($cfg->val("$sections[$i]", 'where'));
	#       my @a_temp_order = $cfg->val("$sections[$i]", 'order') if ($cfg->val("$sections[$i]", 'order'));
	#       my $v_temp_limit = $cfg->val("$sections[$i]", 'limit') if ($cfg->val("$sections[$i]", 'limit'));
	#        my $v_temp_offset = $cfg->val("$sections[$i]", 'offset') if ($cfg->val("$sections[$i]", 'offset'));

	#       @a_select = @a_temp_select if ($#a_temp_select != (-1)); 
	#       $v_from = $v_temp_from if ($v_temp_from); 
	#       my $j = 0;
	#       my $k = 0;
	#       for ($j = 0; $j < scalar(@a_where); $j++)
	#       {
	#           for ($k = 0; $k < scalar(@a_temp_where); $k++)
	#           {
	#               if ($a_temp_where[$k])
	#               {
	#                   $a_temp_where[$k] =~ m/^\s*(\w+)/i;
	#                   if (grep /^\s*$1/, $a_where[$j])
	#                   {
	#                       $a_where[$j] = $a_temp_where[$k];
	#                       delete($a_temp_where[$k]);
	#                       next;
	#                   }
	#               }
	#           }
	#       }
	#       foreach (@a_temp_where)
	#       {
	#           push(@a_where, $_) if ($_);
	#       }
	#
	#       @a_order = @a_temp_order if ($#a_temp_order != (-1)); 
	#       $v_limit = $v_temp_limit if ($v_temp_limit); 
	#       $v_offset = $v_temp_offset if ($v_temp_offset); 
	#   }
	#   
	#   $gql = '';
	#   $gql .= ' select ' . join(',',@a_select) if (@a_select); 
	#   $gql .= ' from ' . $v_from if ($v_from); 
	#   $gql .= ' where ' . join(' and ',@a_where) if (@a_where); 
	#   $gql .= ' order by ' . join(',',@a_order) if (@a_order); 
	#   $gql .= ' limit ' . $v_limit if ($v_limit); 
	#   $gql .= ' offset ' . $v_offset if ($v_offset); 
	#
	#   $conf{gql} = $gql;
	#
	
	print "this feature temporarily unavailable\n";
	exit;
	}
    elsif ($opt_dstore) 
    {
        $conf{kind} = 'all';
    }
    elsif ($opt_info) 
    {
        $conf{kind} = $opt_info;
    }
    else
    {
        help('view');
    }

    if ($opt_format)
    {
        foreach my $format qw(raw txt html yaml) 
        {
            $conf{format} = $format if ($opt_format eq $format) ;
        }
    }
    $conf{format} = 'raw' if (!exists($conf{format})) ;
        
    view( \%conf ); 
}
elsif ($opt_admin)
{ 

	print "this feature temporarily unavailable\n";
	exit;
	#if ($#opt_newuser > 0) 
	#{
	#    $conf{newuser} = \@opt_newuser;
	#}
	#admin( \%conf ); 
}
else
{
    help();
    exit;
}


# Send notification by e-mail
if ( $opt_mailto ) {
#    send_results_by_mail($opt_mailto, @files);
}


###############################################################################
# Define functions
###############################################################################

###############################################################################
#
#convert string to query
#
###############################################################################

sub string2query
{
	my $gql = $_[0];
	my $before;
	my $after;
	my $match_case;
	while($gql =~ m/\([^\(\)]+(=|>=|<=|<|>|IN\([^\(\)]+\))+[^\(\)]+\)/)
	{
		$before = $`;
		$after = $';
		$match_case = $&;
		chop($match_case);
		$match_case = reverse($match_case);
		chop($match_case);
		$match_case = reverse($match_case);
		#print "() before: ",$before," after: ",$after," match case: ",$match_case,"\n";
		#<STDIN>;
		$gql = $before . string2query($match_case) . $after;
		#print "gql after: ",$gql,"\n";
	}
	if($gql =~ m/\|/ && $gql =~ m/AND/)
	{

		while($gql =~ m/[^\|]+(AND)+[^\|]+/)
		{
			$before = $`;
			$after = $';
			$match_case = $&;
			#chop($match_case);
			#$match_case = reverse($match_case);
			#chop($match_case);
			#$match_case = reverse($match_case);
			
			#print "AND OR before: ",$before," after: ",$after," match case: ",$match_case,"\n";
			#<STDIN>;
			$gql = $before . string2query($match_case) . $after;
			#print "gql after: ",$gql,"\n";
		}
	}
	
	#print "lowest level: ",$gql,"\n";
	#<STDIN>;
	$gql = string2query_lowest($gql);
	#print "gql after: ",$gql,"\n";
	
	return $gql;
}

###############################################################################
#
#convert string to query (lowest level)
#
###############################################################################
sub string2query_lowest
{
	my $input_string = $_[0];
	my @subs = split(/\s/,$input_string);
	my $arg;
	my $query_to_mongo = " {";
	my $before;
	my $after;
	my $match_case;
	#my $prefix = "modules.TestRunPhase.";
	my $prefix = "modules.";
	if($input_string =~ m/AND/ && $input_string =~ m/\|/)
	{
		print "error: bquery lowest level\n";
		print "input string: ",$input_string,"\n";
		die;
	}elsif($input_string =~ m/\|/)
	{
		$query_to_mongo .= "\'\$or\'=>[";
	}else
	{
		$query_to_mongo .= "\'\$and\'=>[";
	}
	foreach $arg(@subs)
	{
		#print $arg," subs\n";
	}
	foreach $arg(@subs)
	{
		$arg =~ s/#/ /g;

		if($arg =~m/>=|<=|NOTIN/)
		{
			#print "before match: ", $before,", after match: ",$after," match case: ",$match_case,"\n";
			$before ="{\'$prefix" . $` . "\'=>";
			$after = $';
			$match_case = $&;
			if($match_case eq ">=")
			{
				#print "bolshe ili ravno\n";
				$query_to_mongo .=  $before . "{\'\$gte\'=>" . $after . "}},"; 
	
			}elsif($match_case eq "<=")
			{
				#print "menshe ili ravno\n";
				$query_to_mongo .=  $before . "{\'\$lte\'=>" . $after . "}},"; 

			}else
			{
				#print "NIN\n";
				$after =~ s/\(/\[/g;
				$after =~ s/\)/\]/g;
				$query_to_mongo .= $before . "{\'\$nin\'=>" . $after . "}},"; 
			}
		}
		elsif($arg =~ m/{.+=>.+}/)
		{
			$query_to_mongo .= $arg . ",";
		}
		elsif($arg =~ m/>|=|<|IN/)
		{
			#print "before match1: ", $before," after match: ",$after," match case: ",$match_case,"\n";
			
			$before ="{\'$prefix" . $` . "\'=>";
			$after = $';
			$match_case = $&;
			
			if($match_case eq ">")
			{
				#print "bolshe\n";
				$query_to_mongo .= $before . "{\'\$gt\'=>" . $after . "}},"; 
	
			}elsif($match_case eq "=")
			{
				#print "ravno\n";
				$query_to_mongo .= $before . $after ."},"; 
			}elsif($match_case eq "<")
			{	
				#print "menshe\n";
				$query_to_mongo .=  $before . "{\'\$lt\'=>" . $after . "}},"; 
			}
			else
			{
				#print "IN\n";
				$after =~ s/\(/\[/g;
				$after =~ s/\)/\]/g;
				$query_to_mongo .= $before . "{\'\$in\'=>" . $after . "}},"; 
			}
		}
	}
	chop($query_to_mongo);
	$query_to_mongo .= "]} ";
	return $query_to_mongo;
}

###############################################################################
#
# Show help to tool
#
###############################################################################
sub help 
{
    my ($action)=@_;

    print ("Usage: $module_name [options...] <action> [arguments...]\n");
    print ("\'$module_name\' communicate with datastore .\n\n");
	
    print ("\nOptions:\n");
    printf (" %-5s %-10s\t%-s\n", '-h,', '--help', "Show the help message and exit.");
    printf (" %-5s %-10s\t%-s\n", '-a,', '--server', "The server to connect to.");
    printf (" %-5s %-10s\t%-s\n", '-u,', '--username', "User name.");
    printf (" %-5s %-10s\t%-s\n", '-p,', '--password', "Password.");

    print ("\nActions:\n");
    
    if (!defined($action) || $action eq '' || $action eq 'ping')
    {
        print (" --ping\t The 'ping' command check connection with datastore.\n");
    }
    if (!defined($action) || $action eq '' || $action eq 'upload')
    {
        print (" --upload\t The 'upload' command translates input data into datastore entities and uploads them into your application's datastore.\n");
    }
    if (!defined($action) || $action eq '' || $action eq 'query')
    {
        print (" --query\t The 'query' command translates input string in special request to datastore and download data form query set.\n");
    }
    if (!defined($action) || $action eq '' || $action eq 'view')
    {
        print (" --view\t The 'view' command requests information from datastore.\n");
    }
    if (!defined($action) || $action eq '' || $action eq 'admin')
    {
        print (" --admin\t The 'admin' admin of datastore operations.\n");
    }

    print ("\nArguments:\n");
    
    if (!defined($action) || $action eq '' || $action eq 'upload')
    {
        printf (" %-5s %-10s\t%-s\n", '-S,', '--data', "The name of the file containing the data to upload.");
        printf (" %-5s %-10s\t%-s\n", '-R,', '--raw', "Raw file associated with data.");
    }
    if (!defined($action) || $action eq '' || $action eq 'query')
    {
        printf (" %-5s %-10s\t%-s\n", '-L,', '--gqls', "String with GQL query.");
        printf (" %-5s %-10s\t%-s\n", '-F,', '--gqlf', "The path to file inclusive query.");
        printf (" %-5s %-10s\t%-s\n", '-T,', '--section', "Section of configuration file with query.");
        printf (" %-5s %-10s\t%-s\n", '-O,', '--dir', "The path to the directory that will store retrieved data.");
        printf (" %-5s %-10s\t%-s\n", '', '--no-raw', "Don't download Raw file associated with data.");
    }
    if (!defined($action) || $action eq '' || $action eq 'view')
    {    
        printf (" %-5s %-10s\t%-s\n", '-D,', '--dstore', "Retrieve Google Data store detailed organization with names of models and properties.");
        printf (" %-5s %-10s\t%-s\n", '-I,', '--info', "Show information about clusters, compilers, bench applications and mpi. One of following as 'suite','mpi','compiler','cluster'");
        printf (" %-5s %-10s\t%-s\n", '-L,', '--gqls', "String with GQL query.");
        printf (" %-5s %-10s\t%-s\n", '-F,', '--gqlf', "The path to file inclusive query.");
        printf (" %-5s %-10s\t%-s\n", '-T,', '--section', "Section of configuration file with query.");
        printf (" %-5s %-10s\t%-s\n", '-V,', '--format', "Output format. One of following as 'txt','html','yaml','raw'. Default is 'raw'");
    }
    if (!defined($action) || $action eq '' || $action eq 'admin')
    {
        printf (" %-5s %-10s\t%-s\n", '', '--newuser', "User information as username, password, email (mandatory) and first_name, last_name (optinal). Keep order");
    }
    printf (" %-5s %-10s\t%-s\n", '-e,', '--email', "e-mail address");
    
    exit;
}
      
      
###############################################################################
#
# Check if files directed in command line exists
#
###############################################################################
sub verify_opt_file
{
    my (@files)=@_;
    foreach my $file (@files) 
    {
        if( ! -e $file)
        {
            die "$file doesn't exist!";
        }
    }
}
      
      
###############################################################################
#
# Ping procedure
#
###############################################################################
sub ping
{
    my ($conf_ref)=@_;
    
    my $ua = LWP::UserAgent->new();
    $ua->agent("mtt-submit");
    $ua->proxy('http', $ENV{'http_proxy'});
        
    my $request = POST(
                    $conf_ref->{url},
                    Content_Type => 'form-data',
                    Content => [
                            PING      => 1,
                            description => 'bquery ping'
                             ]);

    $request->authorization_basic($conf_ref->{username}, $conf_ref->{password});

    my $response = $ua->request($request);

    print "Error at $conf_ref->{url}\n ", $response->status_line, "\n"
        unless $response->is_success;
    print "content type at $conf_ref->{url} -- ", $response->content_type, "\n"
        unless $response->content_type eq 'text/html';

    print $response->content;
}
      
      
###############################################################################
#
# Upload procedure
#
###############################################################################
sub upload
{
    my ($conf_ref)=@_;
    my $i = 0;
    use MongoDB;
	use MongoDB::OID;
	use YAML;
	use Data::Dumper;
	use YAML::XS;
	my $conn = MongoDB::Connection->new(host => 'bgate.mellanox.com:27017');
	my $db = $conn->mtt;
	my $TestRunPhase = $db->TestRunPhase;
    for ($i=0; $i<@{$conf_ref->{data}}; $i++)
    {
        my $ua = LWP::UserAgent->new();
        $ua->agent("mtt-submit");
        $ua->proxy('http', $ENV{'http_proxy'});
        
        my $request;
        my $data_file = "$conf_ref->{data}->[$i]" if defined($conf_ref->{data}->[$i]);
        my $raw_file = "$conf_ref->{raw}->[$i]" if defined($conf_ref->{raw}->[$i]);
        if ($raw_file)
        {
			#$request = POST(
			#               $conf_ref->{url},
			#               Content_Type => 'form-data',
			#               Content => [
			#                   SUBMIT      => 1,
			#		            data        => [$data_file],
			#                   raw         => [$raw_file],
			#		            description => 'MTT Results Submission'
			#		         ]);
        }
        else
        {
			print "load $data_file\n";
			open my $fh, '<', "$data_file" 
			or die "can't open config file: $!";
		   	my $f_hash = LoadFile($fh);
			#print Dumper($f_hash), "\n";
			my $inserted_id = $TestRunPhase->insert($f_hash);
			print "inserted id $inserted_id \n";
			#$request = POST(
			#                $conf_ref->{url},
			#               Content_Type => 'form-data',
			#               Content => [
			#                   SUBMIT      => 1,
			#                   data        => [$data_file],
			#                   description => 'bquery submit'
			#                ]);
        }

		#$request->authorization_basic($conf_ref->{username}, $conf_ref->{password});

		#my $response = $ua->request($request);

		#print "Error at $conf_ref->{url}\n ", $response->status_line, "\n"
		#   unless $response->is_success;
		#print "content type at $conf_ref->{url} -- ", $response->content_type, "\n"
		#    unless $response->content_type eq 'text/html';

		#print $response->content;
    }
}


###############################################################################
#
# Query procedure
#
###############################################################################
sub query
{
    my ($conf_ref)=@_;
    
    my $ua = LWP::UserAgent->new();
    $ua->agent("mtt-submit");
    $ua->proxy('http', $ENV{'http_proxy'});
        
    my $request = POST(
                    $conf_ref->{url},
                    Content_Type => 'form-data',
                    Content => [
                            QUERY       => 1,
                            gql         => $conf_ref->{gql},
                            raw         => $conf_ref->{raw},
                            description => 'bquery view'
                             ]);

    $request->authorization_basic($conf_ref->{username}, $conf_ref->{password});

    my $response = $ua->request($request);

    die "Error at $conf_ref->{url}\n ", $response->status_line, "\n"
        unless $response->is_success;
    die "content type at $conf_ref->{url} -- ", $response->content_type, "\n"
        unless $response->content_type eq 'text/yaml';

	# Load respond into YAML hash
    use YAML::Syck ();
    $YAML::Syck::ImplicitTyping = 1;
	my $temp_str = $response->content;
    my $data = eval {YAML::Syck::Load($temp_str)};
#    use YAML::XS ();
#    my $temp_str = $response->content;
#    my $data = eval {YAML::XS::Load($temp_str)};
    if (not defined $data or $@)
    {
        die "$!";
    }

    MTT::Files::mkdir($conf_ref->{dir}) || die "cannot mkdir $conf_ref->{dir}: $!";
    
    my $default_form = {
        product => 'mtt-gds',
        version => "0.1",
        app_id  => 'query'
    };
    
    foreach my $respond_form (@{$data->{data}}) 
    {
    	my $filename = "$conf_ref->{dir}\/$respond_form->{key}";
    	my $raw_filename = $filename.'.zip';
    	$filename = $filename.'.yaml';
     	
     	my %form = (%$respond_form, %$default_form);

	    if (int($conf_ref->{raw}) == 1 && exists($form{raw}))
	    {
	    	open(fh_temp, ">$raw_filename") || die "cannot create $raw_filename: $!";
	    	binmode fh_temp;
	    	print fh_temp $form{raw};
	    	close fh_temp;
            
            delete $form{raw};
	    }
	    
        delete $form{key};
         
        # Generate YAML file contents
        YAML::XS::DumpFile($filename, \%form);
    }
}


###############################################################################
#
# View procedure
#
###############################################################################
sub view
{
    my ($conf_ref)=@_;
    
    my $ua = LWP::UserAgent->new();
    $ua->agent("mtt-submit");
    $ua->proxy('http', $ENV{'http_proxy'});
        
    my $request;
    if (exists($conf_ref->{kind}))
    {
        $request = POST(
                    $conf_ref->{url},
                    Content_Type => 'form-data',
                    Content => [
                            VIEW      => 1,
                            kind      => $conf_ref->{kind},
                            format    => $conf_ref->{format},
                            description => 'bquery view'
                             ]);
    }
    elsif (exists($conf_ref->{gql}))
    {
        $request = POST(
                    $conf_ref->{url},
                    Content_Type => 'form-data',
                    Content => [
                            VIEW      => 1,
                            gql      => $conf_ref->{gql},
                            format    => $conf_ref->{format},
                            description => 'bquery view'
                             ]);
    }

    $request->authorization_basic($conf_ref->{username}, $conf_ref->{password});

    my $response = $ua->request($request);

    print "Error at $conf_ref->{url}\n ", $response->status_line, "\n"
        unless $response->is_success;
    print "content type at $conf_ref->{url} -- ", $response->content_type, "\n"
        unless $response->content_type eq 'text/html';

    print $response->content;
}
      
      
###############################################################################
#
# Admin procedure
#
###############################################################################
sub admin
{
    my ($conf_ref)=@_;
    
    my $ua = LWP::UserAgent->new();
    $ua->agent("mtt-submit");
    $ua->proxy('http', $ENV{'http_proxy'});

    my $request;
    if (exists($conf_ref->{newuser}) && $#{$conf_ref->{newuser}} >=2)
    {
        $request = POST(
                    $conf_ref->{url},
                    Content_Type => 'form-data',
                    Content => [
                            ADMIN       => 1,
                            _NEWUSER_   => 1,
                            username    => $conf_ref->{newuser}->[0],
                            password    => $conf_ref->{newuser}->[1],
                            email       => $conf_ref->{newuser}->[2],
                            first_name  => ($#{$conf_ref->{newuser}} >=3 ? $conf_ref->{newuser}->[3] : ''),
                            last_name   => ($#{$conf_ref->{newuser}} >=4 ? $conf_ref->{newuser}->[4] : ''),
                            description => 'bquery admin'
                             ]);
    }

    $request->authorization_basic($conf_ref->{username}, $conf_ref->{password});

    my $response = $ua->request($request);

    print "Error at $conf_ref->{url}\n ", $response->status_line, "\n"
        unless $response->is_success;
    print "content type at $conf_ref->{url} -- ", $response->content_type, "\n"
        unless $response->content_type eq 'text/html';

    print $response->content;
}
      
      
###############################################################################
#
# Send files by e-mail
#
###############################################################################
sub send_results_by_mail 
{
    my ($mail_to, @files) = @_;

    foreach my $mail_file (@files) 
    {
        system("echo report is attached | /usr/bin/mutt -s 'breport' -a $mail_file $mail_to");
    }
}
