#!/usr/bin/perl
#
# Copyright (c) 2009 Voltaire
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

BEGIN {

    use strict;

    use Data::Dumper;
    use Getopt::Long;
    use File::Basename;
    use Cwd;
    use Storable qw(dclone);
    use POSIX qw(strftime);
    use File::Spec;
    use Text::ParseWords;

    # Try to find the MTT files.  Assume that mtt executable is in the
    # base directory for the MTT files.  Try three methods:

    # 1. With no effort; see if we can just "require" and find MTT files.
    # 2. If $0 is a path, try adding that do @INC and try "require" again.
    # 3. Otherwise, search $ENV[PATH] for mtt, and when you find it, add
    #    that directory to @INC and try again.

    my $mtt_lib = cwd() . "/lib";
    use lib cwd() . "/lib";

    my $ret;
    eval "\$ret = require MTT::Version";
    if (1 != $ret) {
        my $dir = dirname($0);
        my @INC_save = @INC;

        # Change to the dir of $0 (because it might be a relative
        # directory) and add the cwd() to @INC
        my $start_dir = cwd();
        chdir($dir);
        chdir("..");
        $mtt_lib = cwd() . "/lib";
        push(@INC, $mtt_lib);
        chdir($start_dir);
        eval "\$ret = require MTT::Version";

        # If it didn't work, restore @INC and try looking for mtt in the
        # path

        if (1 != $ret) {
            @INC = @INC_save;
            my @dirs = split(/:/, $ENV{PATH});
            my $mtt = basename($0);
            foreach my $dir (@dirs) {

                # If we found the mtt executable, add the dir to @INC and
                # see if we can "require".  If require fails, restore @INC
                # and keep trying.
                if (-x "$dir/$mtt") {
                    chdir($dir);
                    chdir("..");
                    $mtt_lib = cwd() . "/lib";
                    push(@INC, $mtt_lib);
                    chdir($start_dir);
                    eval "\$ret = require MTT::Version";
                    if (1 == $ret) {
                        last;
                    } else {
                        @INC = @INC_save;
                    }
                }
            }
        }

        # If we didn't find them, die.
#        print ("Unable to find MTT support libraries\n") if (0 == $ret);
    }

    # Point to MTT support libraries in case a test needs them
    $ENV{MTT_LIB} = $mtt_lib;
}

# Now that @INC is setup, bring in the modules

use strict;
use warnings;
use MTT::Files;
use LWP::UserAgent;
use HTTP::Request::Common;
use Data::Dumper;
use File::Basename;
use File::Temp;
use Config::IniFiles;
use YAML::XS;


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
my $opt_update;

my @opt_data;
my @opt_raw;

my $opt_gqls;
my @opt_gqlf;
my @opt_section;
my $opt_dir;
my $opt_no_limit;
my $opt_no_raw;
my $opt_no_ref;

my $opt_dstore;
my $opt_info;
my $opt_format;
my $opt_mailto;

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
            "update" => \$opt_update,
            
            "data|S=s" => \@opt_data,
            "raw|R=s" => \@opt_raw,         
            
            "gqls|L=s" => \$opt_gqls,
            "gqlf|F=s" => \@opt_gqlf,
            "section|T=s" => \@opt_section,
            "dir|O=s" => \$opt_dir,
            "no-limit" => \$opt_no_limit,
            "no-raw" => \$opt_no_raw,
            "no-ref" => \$opt_no_ref,

            "dstore|D" => \$opt_dstore,
            "info|I=s" => \$opt_info,
            "format|V=s" => \$opt_format,
            "email|e=s" => \$opt_mailto,

            "newuser=s{3,5}" => \@opt_newuser
            );


my $url = ();
my $username = ();
my $password = ();

$url = $opt_server ? $opt_server : "http://localhost:8080";
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
    $action = 'update' if ($opt_update);

    help($action);
    
    exit;
}
elsif ($opt_ping)
{
    ping( \%conf ); 
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
    elsif (@opt_gqlf && @opt_section && (@opt_gqlf == @opt_section)) 
    {
        my @a_select;
        my $v_from;
        my @a_where;
        my @a_order;
        my $v_limit;
        my $v_offset;
        my $i = 0;
        
        my @files=split(/,/,join(',',@opt_gqlf)) if (@opt_gqlf);
        my @sections=split(/,/,join(',',@opt_section)) if (@opt_section);
        
        # Check if files existed
        verify_opt_file( @files );
        
        for($i=0; $i < @files; $i++)
        {
            # Use ini-file in case it is set in command line
            my $cfg = new Config::IniFiles( -file => "$files[$i]", -nocase => 1 );
            if (not defined $cfg or $@) 
            {
                die "$!";
            }
            
            $opt_dir = $cfg->val("$sections[$i]", 'dir') if ($cfg->val("$sections[$i]", 'dir'));
            
            my @a_temp_select = $cfg->val("$sections[$i]", 'select') if ($cfg->val("$sections[$i]", 'select'));
            my $v_temp_from = $cfg->val("$sections[$i]", 'from') if ($cfg->val("$sections[$i]", 'from'));
            my @a_temp_where = $cfg->val("$sections[$i]", 'where') if ($cfg->val("$sections[$i]", 'where'));
            my @a_temp_order = $cfg->val("$sections[$i]", 'order') if ($cfg->val("$sections[$i]", 'order'));
            my $v_temp_limit = $cfg->val("$sections[$i]", 'limit') if ($cfg->val("$sections[$i]", 'limit'));
            my $v_temp_offset = $cfg->val("$sections[$i]", 'offset') if ($cfg->val("$sections[$i]", 'offset'));

            @a_select = @a_temp_select if ($#a_temp_select != (-1)); 
            $v_from = $v_temp_from if ($v_temp_from); 
            my $j = 0;
            my $k = 0;
            for ($j = 0; $j < scalar(@a_where); $j++)
            {
                for ($k = 0; $k < scalar(@a_temp_where); $k++)
                {
                    if ($a_temp_where[$k])
                    {
                        $a_temp_where[$k] =~ m/^\s*(\w+)/i;
                        if (grep /^\s*$1/, $a_where[$j])
                        {
                            $a_where[$j] = $a_temp_where[$k];
                            delete($a_temp_where[$k]);
                            next;
                        }
                    }
                }
            }
            foreach (@a_temp_where)
            {
                push(@a_where, $_) if ($_);
            }

            @a_order = @a_temp_order if ($#a_temp_order != (-1)); 
            $v_limit = $v_temp_limit if ($v_temp_limit); 
            $v_offset = $v_temp_offset if ($v_temp_offset); 
        }
        
        $gql = '';
        $gql .= ' select ' . join(',',@a_select) if (@a_select); 
        $gql .= ' from ' . $v_from if ($v_from); 
        $gql .= ' where ' . join(' and ',@a_where) if (@a_where); 
        $gql .= ' order by ' . join(',',@a_order) if (@a_order); 
        $gql .= ' limit ' . $v_limit if ($v_limit); 
        $gql .= ' offset ' . $v_offset if ($v_offset); 
    }
    else
    {
        help('query');
    }

    $conf{'gql'} = $gql;
    $conf{'dir'} = $opt_dir ? $opt_dir : "$module_path/dstore";
    $conf{'no-limit'} = undef if $opt_no_limit;
    $conf{'no-raw'} = undef if $opt_no_raw;
    $conf{'no-ref'} = undef if $opt_no_ref;

    query( \%conf ); 
}
elsif ($opt_view)
{
    if ($opt_gqls) 
    {
        $conf{gql} = $opt_gqls;
    }
    elsif (@opt_gqlf && @opt_section && (@opt_gqlf == @opt_section)) 
    {
        my $gql = ();
        my @a_select;
        my $v_from;
        my @a_where;
        my @a_order;
        my $v_limit;
        my $v_offset;
        my $i = 0;
        
        my @files=split(/,/,join(',',@opt_gqlf)) if (@opt_gqlf);
        my @sections=split(/,/,join(',',@opt_section)) if (@opt_section);
        
        # Check if files existed
        verify_opt_file( @files );
        
        for($i=0; $i < @files; $i++)
        {
            # Use ini-file in case it is set in command line
            my $cfg = new Config::IniFiles( -file => "$files[$i]", -nocase => 1 );
            if (not defined $cfg or $@) 
            {
                die "$!";
            }
            $opt_format = $cfg->val("$sections[$i]", 'format') if ($cfg->val("$sections[$i]", 'format'));

            my @a_temp_select = $cfg->val("$sections[$i]", 'select') if ($cfg->val("$sections[$i]", 'select'));
            my $v_temp_from = $cfg->val("$sections[$i]", 'from') if ($cfg->val("$sections[$i]", 'from'));
            my @a_temp_where = $cfg->val("$sections[$i]", 'where') if ($cfg->val("$sections[$i]", 'where'));
            my @a_temp_order = $cfg->val("$sections[$i]", 'order') if ($cfg->val("$sections[$i]", 'order'));
            my $v_temp_limit = $cfg->val("$sections[$i]", 'limit') if ($cfg->val("$sections[$i]", 'limit'));
            my $v_temp_offset = $cfg->val("$sections[$i]", 'offset') if ($cfg->val("$sections[$i]", 'offset'));

            @a_select = @a_temp_select if ($#a_temp_select != (-1)); 
	        $v_from = $v_temp_from if ($v_temp_from); 
            my $j = 0;
            my $k = 0;
            for ($j = 0; $j < scalar(@a_where); $j++)
            {
                for ($k = 0; $k < scalar(@a_temp_where); $k++)
                {
                    if ($a_temp_where[$k])
                    {
                        $a_temp_where[$k] =~ m/^\s*(\w+)/i;
                        if (grep /^\s*$1/, $a_where[$j])
                        {
                            $a_where[$j] = $a_temp_where[$k];
                            delete($a_temp_where[$k]);
                            next;
                        }
                    }
                }
            }
            foreach (@a_temp_where)
            {
                push(@a_where, $_) if ($_);
            }

            @a_order = @a_temp_order if ($#a_temp_order != (-1)); 
            $v_limit = $v_temp_limit if ($v_temp_limit); 
            $v_offset = $v_temp_offset if ($v_temp_offset); 
        }
        
        $gql = '';
        $gql .= ' select ' . join(',',@a_select) if (@a_select); 
        $gql .= ' from ' . $v_from if ($v_from); 
        $gql .= ' where ' . join(' and ',@a_where) if (@a_where); 
        $gql .= ' order by ' . join(',',@a_order) if (@a_order); 
        $gql .= ' limit ' . $v_limit if ($v_limit); 
        $gql .= ' offset ' . $v_offset if ($v_offset); 

        $conf{gql} = $gql;
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
    if ($#opt_newuser > 0) 
    {
        $conf{newuser} = \@opt_newuser;
    }
 
    admin( \%conf ); 
}
elsif ($opt_update)
{
    my $gql = ();

    if ($opt_gqls) 
    {
        $gql = $opt_gqls;
    }
    else
    {
        help('update');
    }

    $conf{'gql'} = $gql;

    update( \%conf ); 
}
else
{
    my $action = '';

    help($action);
    exit;
}


# Send notification by e-mail
if ( $opt_mailto ) {
    my @attachments;
    send_results_by_mail($opt_mailto, @attachments);
}


###########################################################
# Define functions
###########################################################


###############################################################################
#
# Show help to tool
#
###############################################################################
sub help 
{
    my ($action)=@_;

    print ("Usage: $module_name [options...] <action> [arguments...]\n");
    print ("\'$module_name\' Google MTT Datastore querying utility.\n\n");
	
    print ("\nOptions:\n");
    printf (" %-5s %-10s\t%-s\n", '-h,', '--help', "Show the help message and exit.");
    printf (" %-5s %-10s\t%-s\n", '-a,', '--server', "Datastore server (URL must be absolute).");
    printf (" %-5s %-10s\t%-s\n", '-u,', '--username', "User name.");
    printf (" %-5s %-10s\t%-s\n", '-p,', '--password', "Password.");

    print ("\nActions:\n");
    
    if (!defined($action) || $action eq '' || $action eq 'ping')
    {
        printf (" %-10s %-s\n", '--ping', "The 'ping' command checks connection with datastore.");
    }
    if (!defined($action) || $action eq '' || $action eq 'upload')
    {
        printf (" %-10s %-s\n", '--upload', "The 'upload' command translates input data into the datastore entities and uploads them into your application's datastore.");
    }
    if (!defined($action) || $action eq '' || $action eq 'query')
    {
        printf (" %-10s %-s\n", '--query', "The 'query' command translates input string in special request to the datastore and downloads data to the local machine.");
    }
    if (!defined($action) || $action eq '' || $action eq 'view')
    {
        printf (" %-10s %-s\n", '--view', "The 'view' command requests information from the datastore.");
    }
    if (!defined($action) || $action eq '' || $action eq 'admin')
    {
        printf (" %-10s %-s\n", '--admin', "The 'admin' command executes administrative operations.");
    }
    if (!defined($action) || $action eq '' || $action eq 'update')
    {
        printf (" %-10s %-s\n", '--update', "The 'update' command executes update operation for datastore table.");
    }

    print ("\nArguments:\n");
    
    if (!defined($action) || $action eq '' || $action eq 'upload')
    {
        printf (" %-5s %-10s\t%-s\n", '-S,', '--data', "Name of the file which contains data to upload.");
        printf (" %-5s %-10s\t%-s\n", '-R,', '--raw', "Raw file associated with the data.");
    }
    if (!defined($action) || $action eq '' || $action eq 'query')
    {
        printf (" %-5s %-10s\t%-s\n", '-L,', '--gqls', "String with GQL query.");
        printf (" %-5s %-10s\t%-s\n", '-F,', '--gqlf', "Inclusive query file path.");
        printf (" %-5s %-10s\t%-s\n", '-T,', '--section', "Section of configuration file with the query.");
        printf (" %-5s %-10s\t%-s\n", '-O,', '--dir', "Output directory with retrieved data.");
        printf (" %-5s %-10s\t%-s\n", '', '--no-limit', "Increase the number of results returned by a query. Can be used with restriction.");
        printf (" %-5s %-10s\t%-s\n", '', '--no-raw', "Don't download raw files associated with the data.");
        printf (" %-5s %-10s\t%-s\n", '', '--no-ref', "Download a short format of data.");
    }
    if (!defined($action) || $action eq '' || $action eq 'view')
    {    
        printf (" %-5s %-10s\t%-s\n", '-D,', '--dstore', "Retrieve the datastore detailed structure with names of models and their properties.");
        printf (" %-5s %-10s\t%-s\n", '-I,', '--info', "Show information about clusters, compilers, bench applications and mpi. The parameters take one of following values: 'suite', 'mpi', 'compiler', 'cluster'.");
        printf (" %-5s %-10s\t%-s\n", '-L,', '--gqls', "String with GQL query.") if $action eq 'view';
        printf (" %-5s %-10s\t%-s\n", '-F,', '--gqlf', "Inclusive query file path.") if $action eq 'view';
        printf (" %-5s %-10s\t%-s\n", '-T,', '--section', "Section of configuration file with query.") if $action eq 'view';
        printf (" %-5s %-10s\t%-s\n", '-V,', '--format', "Output format. The parameters takes one of following values: 'txt','html','yaml','raw'. Default is 'raw'");
    }
    if (!defined($action) || $action eq '' || $action eq 'admin')
    {
        printf (" %-5s %-10s\t%-s\n", '', '--newuser', "User information as username, password, email (mandatory) and first_name, last_name (optional). Keep order of values.");
    }
    if (!defined($action) || $action eq '' || $action eq 'update')
    {
        printf (" %-5s %-10s\t%-s\n", '-L,', '--gqls', "String with GQL query.");
    }
    printf (" %-5s %-10s\t%-s\n", '-e,', '--email', "e-mail address to get notification");
    
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
            die "$file doesn't exist";
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
    
    my $scheme = $conf_ref->{url};
    $scheme =~ s/^\s*(http[s]*):\/\/.*$/$1/;
    # Get the proxy corresponding to the scheme
    my $env_proxy = $ENV{"${scheme}_proxy"};
        
    my $ua = LWP::UserAgent->new();
    $ua->agent("mtt-bquery.pl");
        
    if ($env_proxy) {
        # Ensure the env proxy has the scheme at the prefix
        $env_proxy = "$scheme://$env_proxy"
            if ($env_proxy !~ /^\s*http/);
        $ua->proxy($scheme, $env_proxy);
    }

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
    
    for ($i=0; $i<@{$conf_ref->{data}}; $i++)
    {
        my $ua = LWP::UserAgent->new();
        $ua->agent("mtt-submit");
        $ua->proxy('http', $ENV{'http_proxy'});
        
        my $request;
        my $data_file = "$conf_ref->{data}->[$i]" if defined($conf_ref->{data}->[$i]);
        my $raw_file = "$conf_ref->{raw}->[$i]" if defined($conf_ref->{raw}->[$i]);

        # Chech Google Datastore put entity limitation
        $raw_file = '' if  1048576 <= ((-s "$raw_file") + (-s "$data_file"));
        if ($raw_file)
        {
            $request = POST(
                            $conf_ref->{url},
                            Content_Type => 'form-data',
                            Content => [
                                SUBMIT      => 1,
					            data        => [$data_file],
                                raw         => [$raw_file],
					            description => 'MTT Results Submission'
					         ]);
        }
        else
        {
            $request = POST(
                            $conf_ref->{url},
                            Content_Type => 'form-data',
                            Content => [
                                SUBMIT      => 1,
                                data        => [$data_file],
                                description => 'bquery submit'
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
}


###############################################################################
#
# Query procedure
#
###############################################################################
sub query
{
    my ($conf_ref)=@_;
    
    my $gql = ();
    my $data = undef;
    my $loop_threshold = 10;
    my $ua = LWP::UserAgent->new();
    $ua->agent("mtt-submit");
    $ua->proxy('http', $ENV{'http_proxy'});

    do
    {
    	$gql = $conf_ref->{gql};
    	if (exists($conf_ref->{'no-limit'}))
    	{
    		$gql = $gql . " and __key__>key('$data->{last_key}')" if ( defined($data) );
    		$gql = $gql . " order by __key__ asc limit $loop_threshold";
    	}

	    my %cntx = ( QUERY       => 1,
	                 gql         => $gql,
	                 description => 'bquery query'
	                );
	    $cntx{'no-raw'} = undef if exists($conf_ref->{'no-raw'});
	    $cntx{'no-ref'} = undef if exists($conf_ref->{'no-ref'});
	                
	    my $request = POST(
	                    $conf_ref->{url},
	                    Content_Type => 'form-data',
	                    Content => \%cntx);
	
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
	    $data = eval {YAML::Syck::Load($temp_str)};
	#    use YAML::XS ();
	#    my $temp_str = $response->content;
	#    my $data = eval {YAML::XS::Load($temp_str)};
	    if (not defined $data or $@)
	    {
	        die "$!";
	    }
	
            MTT::Files::mkdir($conf_ref->{dir}) || die "cannot mkdir $conf_ref->{dir}: $!" if (! -d $conf_ref->{dir});
	    
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
	
		    if (exists($form{raw}))
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
    } while (exists($conf_ref->{'no-limit'}) && (defined($data) && $data->{count} == $loop_threshold));
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
# Update procedure
#
###############################################################################
sub update
{
    my ($conf_ref)=@_;
    
    my $ua = LWP::UserAgent->new();
    $ua->agent("mtt-submit");
    $ua->proxy('http', $ENV{'http_proxy'});

    my %cntx = ( UPDATE       => 1,
                 gql         => $conf_ref->{gql},
                 description => 'bquery update'
                );
                
    my $request = POST(
                    $conf_ref->{url},
                    Content_Type => 'form-data',
                    Content => \%cntx);

    $request->authorization_basic($conf_ref->{username}, $conf_ref->{password});

    my $response = $ua->request($request);

    die "Error at $conf_ref->{url}\n ", $response->status_line, "\n"
        unless $response->is_success;
    die "content type at $conf_ref->{url} -- ", $response->content_type, "\n"
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
