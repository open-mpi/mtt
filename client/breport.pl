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
use Spreadsheet::WriteExcel;
use Spreadsheet::WriteExcel::Format;
use GD::Graph::lines;
use GD::Graph::bars;
use File::Temp;
use File::Basename;
use Config::IniFiles;   
use YAML::XS;


use constant Type_Line => 0;
use constant Type_Column => 1;
use constant Type_External => 2;


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
my @opt_dir;
my @opt_src;
my $opt_dest;
my $opt_ini;
my $opt_section;
my $opt_title;
my $opt_mailto;
my @opt_axis_x;
my @opt_axis_y;
my @opt_label_x;
my @opt_label_y;
my $opt_legend;
my @opt_chartex;
my $opt_tab_title = 1;
my $opt_tab_view = 1;
my $opt_tab_data = 1;


my $report_file = ();
my $report_title = ();
my @dir = ();
my @files = ();
my @axis_x = ();
my @axis_y = ();
my @label_x = ();
my @label_y = ();
my @legend = ();
my @chartex = ();


GetOptions ("help|h"=>\$opt_help,
            "dir|d=s" => \@opt_dir,
            "src|s=s" => \@opt_src,
            "dest|o=s" => \$opt_dest,
            "ini|i=s" => \$opt_ini,
            "section|t=s" => \$opt_section,
            "title|T=s" => \$opt_title,
            "tab_title!" => \$opt_tab_title,
            "tab_view!" => \$opt_tab_view,
            "tab_data!" => \$opt_tab_data,
            "axis_x|AX=s" => \@opt_axis_x,
            "axis_y|AY=s" => \@opt_axis_y,
            "label_x|LX=s" => \@opt_label_x,
            "label_y|LY=s" => \@opt_label_y,
            "legend|L=s" => \$opt_legend,
            "chart_ex|CH=s" => \@opt_chartex,
            "email|m|e=s" => \$opt_mailto
            );


# Print help by request or in case invalid options
if ( (!@opt_dir && !@opt_src && !($opt_ini && $opt_section)) || $opt_help ) 
{
    help();
    exit;
}


if ($opt_ini && $opt_section)
{   
    # Use ini-file in case it is set in command line
    my $cfg = new Config::IniFiles( -file => "$opt_ini", -nocase => 1 );
    if (not defined $cfg or $@) 
    {
        die "$!";
    }
    
    $opt_dest = $cfg->val("$opt_section", 'dest') if ($cfg->val("$opt_section", 'dest'));
    $opt_title = $cfg->val("$opt_section", 'title') if ($cfg->val("$opt_section", 'title'));

    @opt_dir = $cfg->val("$opt_section", 'dir') if ($cfg->val("$opt_section", 'dir'));   
    @opt_src = $cfg->val("$opt_section", 'src') if ($cfg->val("$opt_section", 'src'));
    @opt_axis_x = $cfg->val("$opt_section", 'axis_x') if ($cfg->val("$opt_section", 'axis_x'));
    @opt_axis_y = $cfg->val("$opt_section", 'axis_y') if ($cfg->val("$opt_section", 'axis_y'));
    @opt_label_x = $cfg->val("$opt_section", 'label_x') if ($cfg->val("$opt_section", 'label_x'));
    @opt_label_y = $cfg->val("$opt_section", 'label_y') if ($cfg->val("$opt_section", 'label_y'));
    
    $opt_legend = $cfg->val("$opt_section", 'legend');
    @opt_chartex = $cfg->val("$opt_section", 'chartex');
}

# Parse command line
$report_file = $opt_dest ? $opt_dest : "${module_path}report.xls";
$report_title = $opt_title ? $opt_title : "List of objects";


@dir=split(/,/,join(',',@opt_dir)) if (@opt_dir);

if ($#dir != (-1))
{
    # Process --dir option
    my %h_temp = ();
    foreach (@dir)
    {
    	$h_temp{$_} = undef;
    }

    foreach my $cur_dir (keys %h_temp)
    {
        opendir (DIR, "$cur_dir") or die "$!";
        my @temp_files = grep {/.*?\.yaml/}  readdir DIR;
        close DIR;
        foreach (@temp_files) 
        {
            push(@files, "$cur_dir/$_");
        }
    }   
}
else
{
    # Process --src option
    @files=split(/,/,join(',',@opt_src));
}
    
# Split the string into a list of axis_x properties
@axis_x=split(/,/,join(',',@opt_axis_x)) if (@opt_axis_x);
    
# Split the string into a list of axis_y properties
@axis_y=split(/,/,join(',',@opt_axis_y)) if (@opt_axis_y);
    
# Split the string into a list of label_x properties
@label_x=split(/,/,join(',',@opt_label_x)) if (@opt_label_x);
    
# Split the string into a list of label_y properties
@label_y=split(/,/,join(',',@opt_label_y)) if (@opt_label_y);
    
# Split the string into a list of properties that should be in legend
my $pattern = qr/\$(\w+)/;
@legend = $opt_legend =~ m/$pattern/ig if (defined($opt_legend));

# Split the string into a list of chart_ex properties
@chartex=split(/,/,join(',',@opt_chartex)) if (@opt_chartex);

# Check different arguments    
if (@axis_x != @axis_y)
{
    die "pairs axis_x & axis_y should have valid values";
}

# Check different arguments    
if ( (scalar(@dir) > 1) && (@dir != @axis_x) )
{
    die "set --dir option for every pair axis_x & axis_y";
}

# Check if files existed
verify_opt_file( @files );

# Create report file
my %report_conf = ('title' => $report_title, 
                   'dest' => $report_file,
                   'src' => \@files,
                   'data_count' => ($#axis_x + 1),
                   'match' => ((scalar(@dir) > 1) ? \@dir : undef),
                   'axis_x' => \@axis_x,
                   'axis_y' => \@axis_y,
                   'label_x' => \@label_x,
                   'label_y' => \@label_y,
                   'legend' => \@legend,
                   'chart_ex' => \@chartex
                    );
create_report( \%report_conf ); 

# Send notification by e-mail
if ( $opt_mailto ) {
    send_results_by_mail($opt_mailto, $report_file);
}

if(-e $report_file)
{
    print ("Report file $report_file has been prepared\n");
}

exit 0;


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
    print ("Usage: $module_name [OPTION...]\n");
    print ("\'$module_name\' Google MTT Datastore report utility.\n\n");

    print ("\nOptions:\n");
    printf (" %-5s %-10s\t%-s\n", '-h,', '--help', "Show the help message and exit.");
    printf (" %-5s %-10s\t%-s\n", '-d,', '--dir=[DIR]', "Input directory with results collection.");
    printf (" %-5s %-10s\t%-s\n", '-s,', '--src=[FILE]', "Input file.");
    printf (" %-5s %-10s\t%-s\n", '-o,', '--dest=[FILE]', "Output Excel file name (default is 'report.xls').");
    printf (" %-5s %-10s\t%-s\n", '-i,', '--ini=[FILE]', "Configuration file.");
    printf (" %-5s %-10s\t%-s\n", '-t,', '--section', "Name of configuration file section.");

    printf (" %-5s %-10s\t%-s\n", '-T,', '--title', "Title of report (default is 'List of objects').");

    printf (" %-5s %-10s\t%-s\n", '', '--tab_title', "Include 'objects' tabsheet (default ON).");
    printf (" %-5s %-10s\t%-s\n", '', '--tab_view', "Include 'view' tabsheet (default ON).");
    printf (" %-5s %-10s\t%-s\n", '', '--tab_data', "Include 'data' tabsheet (default ON).");

    printf (" %-5s %-10s\t%-s\n", '-AX,', '--axis_x', "Property name of data that should be displayed on axis X or 'none'.");
    printf (" %-5s %-10s\t%-s\n", '-AY,', '--axis_y', "Property name of data that should be displayed on axis Y or 'none'.");

    printf (" %-5s %-10s\t%-s\n", '-LX,', '--label_x', "Axis X label.");
    printf (" %-5s %-10s\t%-s\n", '-LY,', '--label_y', "Axis Y label.");

    printf (" %-5s %-10s\t%-s\n", '-L,', '--legend', "Template to legend in the following format: '\$<property1>\$<property2>...'");

    printf (" %-5s %-10s\t%-s\n", '-CH,', '--chart_ex', "External chart template binary file.");

    printf (" %-5s %-10s\t%-s\n", '-e,', '--email', "e-mail address to get notification");
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
# Is data loaded from yaml file valid
#
###############################################################################
sub is_valid
{
    my ($data)=@_;   
    my $temp_value = 0;
    
   if ($data->{product} eq 'mtt-gds')
   {
       $temp_value = 1;
   }

    return $temp_value;
}


############################################################
#
# Test subroutine to check the regexp performs as advertised
#
############################################################
sub check_list_to_regexp
{
    my ($pattern, $list) = @_;

    foreach (@{$list}) 
    {
        if ($_)
        {
            if  ( !($_ =~ m/$pattern/i) )
            {
            	return 0;            	
            }
        }
        else
        {
        	return 0;
        }
    }

    return 1;
}


###############################################################################
#
# str_wrap
#
###############################################################################
sub str_wrap
{
    my ($str, $width)=@_;   
    my $str_width = 0;
    my $i = 0;
    
    $str_width = length($str);
    $width = 21 if !defined($width);
    
    for ( $i = 0; $i < ($str_width/$width-1); $i++ )
    {
    	substr($str, $i * ($width + 1), 0) = "\n";
    }
    
    return $str;
}


###############################################################################
#
# Is string an array
#
###############################################################################
sub is_array
{
    my ($data_str)=@_;   
    my $temp_value = 0;
    
    $temp_value = 1 if (defined($data_str) && index( $data_str, "{") == 0 && index( $data_str, "}") != -1) ;

    return $temp_value;
}


###############################################################################
#
# Find max string length in 2D array
#
###############################################################################
sub max_len_2D
{
    my ($temp_array_ref, $offset, $to)=@_;   
    my $temp_value;
    my $i = 0;
    
    $offset = 0 unless (defined($offset));   
    $to = scalar (@$temp_array_ref) unless (defined($to));   
    
    foreach (@$temp_array_ref) 
    {
        $i++;
        
        next if ($i <= $offset);

        last if ($i > $to);
        
        foreach (@$_) 
        {
           $temp_value = length($_) if  (!defined($temp_value) || length($_) > $temp_value );
        }
    }

    return $temp_value;
}


###############################################################################
#
# Find max in 2D array
#
###############################################################################
sub max_2D
{
    my ($temp_array_ref, $offset)=@_;   
    my $temp_value;
    
    $offset = 0 unless (defined($offset));   
    
    foreach (@$temp_array_ref) 
    {
    	if ($offset)
    	{
    	   $offset--;
    	   next;	
    	}
    	
        foreach (@$_) 
        {
        	if ($_)
        	{
                $temp_value = $_ if  (!defined($temp_value) || $_ > $temp_value );
        	}
        }
    }

    return $temp_value;
}


###############################################################################
#
# Find min in 2D array
#
###############################################################################
sub min_2D
{
    my ($temp_array_ref, $offset)=@_;   
    my $temp_value;
    
    $offset = 0 unless (defined($offset));   
    
    foreach (@$temp_array_ref) 
    {
        if ($offset)
        {
           $offset--;
           next;    
        }
        
        foreach (@$_) 
        {
            if ($_)
            {
                $temp_value = $_ if  (!defined($temp_value) || $_ < $temp_value );
            }
        }
    }

    return $temp_value;
}


###############################################################################
#
# Create worksheet <Title>
#
###############################################################################
sub create_sheet_title
{
    my ($workbook, $title, $a_data_object_ref )=@_;
    my $temp_str = '';
    my $temp_format = ();
    my $i=0;
        
    my $sheet = $workbook->add_worksheet("objects");

    my $frow = 2;
    my $fcol = 1;
    my $hrow = 2;

    my $format = $workbook->add_format(
                                font  => 'Arial',
                                size  => 16,
                                color => 'black',
                                bold  => 1,
                                valign  => 'top',
                                align   => 'center'
                                );

    $sheet->merge_range($frow - 2, $fcol - 1, $frow - 2, $fcol + 6, $title, $format);

    my $format1 = $workbook->add_format(
                                font  => 'Arial',
                                size  => 10,
                                color => 'black',
                                bold  => 1,
                                valign  => 'top',
                                align   => 'left',
                                bg_color => 'gray',
                                pattern  => 0
                                );

    $sheet->write($frow, $fcol, "FILE:", $format1);
    $sheet->write($frow, $fcol + 1, "SUITE:", $format1);
    $sheet->write($frow, $fcol + 2, "", $format1);
    $sheet->write($frow, $fcol + 3, "MPI:", $format1);
    $sheet->write($frow, $fcol + 4, "", $format1);
    $sheet->write($frow, $fcol + 5, "CLUSTER:", $format1);
    $sheet->write($frow, $fcol + 6, "", $format1);

    my $format2 = $workbook->add_format(
                                font  => 'Arial',
                                size  => 10,
                                color => 'black',
                                valign  => 'top',
                                align   => 'left',
                                bg_color => 'silver',
                                pattern  => 0,
                                num_format => '@'   # Format as a string. Doesn't change to a number when edited
                                );

    my $format3 = $workbook->add_format(
                                font  => 'Arial',
                                size  => 10,
                                color => 'black',
                                valign  => 'top',
                                align   => 'left',
                                bg_color => 'white',
                                pattern  => 0,
                                num_format => '@'   # Format as a string. Doesn't change to a number when edited
                                );

        
    # Add a handler to store the width of the longest string written to a column.
    $sheet->add_write_handler(qr[\w], \&store_string_widths);

    my $h_modules_ref = 0;                                
    for($i=0; $i < @{$a_data_object_ref}; $i++)
    {
        $h_modules_ref = $a_data_object_ref->[$i]->{modules};
        $temp_format = ( $i%2 ? $format2 : $format3);
        $sheet->write($frow + ($i * $hrow) + 1, $fcol - 1, "$i", $temp_format);

        $temp_str = $a_data_object_ref->[$i]->{file_name};
        $sheet->write_url($frow + ($i * $hrow) + 1, $fcol, "internal:'${temp_str}'!A1", $temp_str, $temp_format);

        $sheet->write($frow + ($i * $hrow) + 1, $fcol + 1, "Name:", $temp_format);
        $sheet->write($frow + ($i * $hrow) + 1, $fcol + 2, $h_modules_ref->{TestRunPhase}->{cached_suiteinfo_suite_name}, $temp_format);
        $sheet->write($frow + ($i * $hrow) + 2, $fcol + 1, "Version:", $temp_format);
        $sheet->write($frow + ($i * $hrow) + 2, $fcol + 2, $h_modules_ref->{TestRunPhase}->{cached_suiteinfo_suite_version}, $temp_format);

        $sheet->write($frow + ($i * $hrow) + 1, $fcol + 3, "Name:", $temp_format);
        $sheet->write($frow + ($i * $hrow) + 1, $fcol + 4, $h_modules_ref->{TestRunPhase}->{cached_mpiinfo_mpi_name}, $temp_format);
        $sheet->write($frow + ($i * $hrow) + 2, $fcol + 3, "Version:", $temp_format);
        $sheet->write($frow + ($i * $hrow) + 2, $fcol + 4, $h_modules_ref->{TestRunPhase}->{cached_mpiinfo_mpi_version}, $temp_format);

        $sheet->write($frow + ($i * $hrow) + 1, $fcol + 5, "Organization:", $temp_format);
        $sheet->write($frow + ($i * $hrow) + 1, $fcol + 6, $h_modules_ref->{TestRunPhase}->{cached_submitinfo_http_username}, $temp_format);
        $sheet->write($frow + ($i * $hrow) + 2, $fcol + 5, "Name:", $temp_format);
        $sheet->write($frow + ($i * $hrow) + 2, $fcol + 6, $h_modules_ref->{TestRunPhase}->{cached_clusterinfo_cluster_name}, $temp_format);
    }
    
    # Run the autofit after you have finished writing strings to the workbook.
    autofit_columns($sheet);    
} 


###############################################################################
#
# Create one or few worksheets with table and graph data
#
###############################################################################
sub create_sheet_view
{
    my ($workbook, $a_data_view_ref)=@_;
    my $img;
    my $temp_str;
    my $temp_format;
    my $temp_image;    
    my $i=0;
    my $j=0;
    my $k=0;
    
    my $frow = 3;
    my $fcol = 1;
    my $hrow = 1;
    my $wcol = 1;
    
    my $format1 = $workbook->add_format(
                                font  => 'Arial',
                                size  => 10,
                                color => 'black',
                                bold  => 1,
                                valign  => 'top',
                                align   => 'center',
                                bg_color => 'gray',
                                pattern  => 0,
                                text_wrap => 1
                                );

    my $format2 = $workbook->add_format(
                                font  => 'Arial',
                                size  => 10,
                                color => 'black',
                                valign  => 'top',
                                align   => 'left',
                                bg_color => 'silver',
                                pattern  => 0
                                );

    my $format3 = $workbook->add_format(
                                font  => 'Arial',
                                size  => 10,
                                color => 'black',
                                valign  => 'top',
                                align   => 'left',
                                bg_color => undef,
                                pattern  => 0
                                );

    my $format4 = $workbook->add_format(
	                            font  => 'Arial',
	                            size  => 10,
	                            color => 'black',
	                            bold  => 1,
	                            valign  => 'top',
	                            align   => 'center',
	                            bg_color => 'gray',
	                            pattern  => 0,
                                text_wrap => 1
	                            );

    my $format5 = $workbook->add_format(
                                font  => 'Arial',
                                size  => 10,
                                color => 'black',
                                bold  => 1,
                                valign  => 'top',
                                align   => 'center',
                                bg_color => undef,
                                pattern  => 0,
                                text_wrap => 1
                                );
            
    my $a_data_ref = 0;
    my $a_legend_ref = 0;
    my $a_label_ref = 0;
    for($i=0; $i < @{$a_data_view_ref}; $i++)
    {
        $frow = 4;
        $fcol = 1;
        $frow = $a_data_view_ref->[$i]->{position}->[1];
        $fcol = $a_data_view_ref->[$i]->{position}->[0];
        $a_data_ref = $a_data_view_ref->[$i]->{a_data};
        $a_legend_ref = $a_data_view_ref->[$i]->{a_legend};
        $a_label_ref = $a_data_view_ref->[$i]->{a_label};
        $temp_str = $a_data_view_ref->[$i]->{caption};
        
        $temp_str = (length($temp_str) > 31) ? substr($temp_str, 0, 31) : $temp_str;
        
        my $sheet = undef;
        foreach ($workbook->sheets()) {
            if ($temp_str eq $_->get_name())
            {
                $sheet = $_;
                last;
            }
        }
        $sheet = $workbook->add_worksheet($temp_str) if (!defined($sheet));  
    
        # Show title of a table
        if (defined($a_data_view_ref->[$i]->{title}))
        {
            $sheet->merge_range($frow - 3, $fcol,
                                $frow - 3, $fcol + @{$a_data_ref->[0]},
                                $a_data_view_ref->[$i]->{title},
                                $format5);
        }
        # Set the first head level
        if (defined($a_label_ref->[1]))
        {
            if (@{$a_data_ref->[0]} > 1)
            {
                $sheet->merge_range($frow - 2, $fcol + 1,
                                    $frow - 2, $fcol + @{$a_data_ref->[0]},
                                    $a_label_ref->[1],
                                    $format4);
                                    
                # Add a handler to store the width of the longest string written to a column.
                $sheet->add_write_handler(qr[\w], \&store_string_widths);
            }
            else
            {       
                # Add a handler to store the width of the longest string written to a column.
                $sheet->add_write_handler(qr[\w], \&store_string_widths);
            
                $sheet->write($frow - 2, $fcol + 1,
                              $a_label_ref->[1],
                              $format1);
            }
        }
        else
        {
            # Add a handler to store the width of the longest string written to a column.
            $sheet->add_write_handler(qr[\w], \&store_string_widths);
        }

        # Set the second head level
        if (defined($a_label_ref->[0]))
        {
            $sheet->write($frow - 1, $fcol,
                          $a_label_ref->[0],
                          $format1);
        }
        for($k=0; $k < @{$a_data_ref->[0]}; $k++)
        {
            $sheet->write($frow - 1, $fcol + ($k * $wcol) + 1,
                          $a_data_ref->[0]->[$k],
                          $format1);
        }
            
        # Fill the table with values
        for($j=0; $j < @{$a_legend_ref}; $j++)
        {
            $temp_format = ( $j%2 ? $format2 : $format3);
            $sheet->write($frow + ($j * $hrow), $fcol,
                          $a_legend_ref->[$j],
                          $temp_format);
            for($k=0; $k < @{$a_data_ref->[0]}; $k++)
            {
                $sheet->write($frow + ($j * $hrow), $fcol + ($k * $wcol) + 1,
                              $a_data_ref->[$j + 1]->[$k],
                              $temp_format);
            }
        }
        # Run the autofit after you have finished writing strings to the workbook.
        autofit_columns($sheet);    

        # Create graph
        if ($a_data_view_ref->[$i]->{view_type} != Type_External)
        {
	        #create graph object for canvas 800 X 500 pixels by default
	        my $img_width = 800;
	        $img_width += (scalar(@{$a_data_ref->[0]}) - 30) * 10 if (scalar(@{$a_data_ref->[0]}) > 30);
	        my $img_height = 500;
	        $img_height += (scalar(@{$a_legend_ref}) - 50) * 10 if (scalar(@{$a_legend_ref}) > 50);
	        if ($a_data_view_ref->[$i]->{view_type} == Type_Column)
	        {
	            $img= GD::Graph::bars->new($img_width, $img_height) or die GD::Graph->error;
	        }
	        elsif ($a_data_view_ref->[$i]->{view_type} == Type_Line)
	        {
	            $img= GD::Graph::lines->new($img_width, $img_height) or die GD::Graph->error;
	        }
		    else
		    {
		        printf("Error: Invalid data view - %s\n", $a_data_view_ref->[$i]->{view_type});
		        return ;
		    }
	
	        #set graph options required 
	        $img->set(
	                    # graph title 
	                    title       => $a_data_view_ref->[$i]->{title},
	                    x_label     => $a_label_ref->[0],
	                    y_label     => $a_label_ref->[1],
	                    # position of both X axis labels
	                    x_label_position => 1,
	                    # position of both Y axis labels
	                    y_label_position => 1,
	#                    y_min_value => min_2D($a_data_ref, 1) - (max_2D($a_data_ref, 1) - min_2D($a_data_ref, 1)) / 100,
	#                    y_max_value => max_2D($a_data_ref, 1) + (max_2D($a_data_ref, 1) - min_2D($a_data_ref, 1)) / 100,
	                    # use transparent background
	                    transparent   => 0,
	                    # background colour
	                    bgclr         => '#e6e6e6',
	                    # draw border around graph
	                    box_axis => 0,
	                    # put legend to the centre right of chart 
	                    legend_placement =>'BC',
	                    # width of lines
	                    line_width => 2,
	                    # Show the grid
	                    long_ticks  => 0,
	                    # Set the length for the 'short' ticks on the axes.
	                    x_tick_length => 4,
	                    y_tick_length => 4,
	                    # vertical printing of x labels in case 1 - there are a lot of data
	                    x_labels_vertical   => ((max_len_2D($a_data_ref, 0, 1) < 10) && (scalar(@{$a_data_ref->[0]}) > 20)? 1 : 0),
	                    # Show values on top of each bar
	                    show_values => ($a_data_view_ref->[$i]->{view_type} == Type_Column ? 1 : 0),
	                    values_vertical => ($a_data_view_ref->[$i]->{view_type} == Type_Column ? 1 : 0),
	                    dclrs  => [GD::Graph::colour::colour_list]
	                ) or warn $img->error and return;
	                
	        # Number of pixels to leave between groups of bars when multiple datasets are being displayed
	        $img->set(bargroup_spacing   => 30) if $img->_has_default('bargroup_spacing');
	                
	        # set legend
	        $img->set_legend(@$a_legend_ref);
	           
	        # plot graph with table data
	        my $gd = $img->plot($a_data_ref) or warn $img->error and return;
	        $temp_image = new File::Temp();
	        open(fh_temp, ">$temp_image") or warn ("Failed to write file: $!") and return;
	        binmode fh_temp;
	        print fh_temp $gd->png;
	        close fh_temp;
	    
	        $sheet->insert_image( 21, $fcol, $temp_image);
        }
        else
        {
            $sheet->embed_chart( 21, $fcol, $a_data_view_ref->[$i]->{chart_ex}, 3, 3, 1.08, 1.21);
            
            $temp_str = '=' . $sheet->get_name() . '!A1';
            $sheet->store_formula($temp_str);        	
        }
    }
} 


###############################################################################
#
# Create worksheet with raw data
#
###############################################################################
sub create_sheet_data
{
    my ($workbook, $a_data_object_ref )=@_;
    my $temp_str = '';
    my $temp_format = ();
    my $i=0;
        
    my $frow = 2;
    my $fcol = 1;
    my $hrow = 1;

    my $format1 = $workbook->add_format(
                                font  => 'Arial',
                                size  => 10,
                                color => 'black',
                                bold  => 1,
                                valign  => 'top',
                                align   => 'left',
                                bg_color => 'gray',
                                pattern  => 0
                                );

    my $format2 = $workbook->add_format(
                                font  => 'Arial',
                                size  => 10,
                                color => 'black',
                                valign  => 'top',
                                align   => 'left',
                                bg_color => 'silver',
                                pattern  => 0,
                                text_wrap => 1
                                );

    my $format3 = $workbook->add_format(
                                font  => 'Arial',
                                size  => 10,
                                color => 'black',
                                valign  => 'top',
                                align   => 'left',
                                bg_color => 'white',
                                pattern  => 0,
                                text_wrap => 1
                                );

    my $h_modules_ref = 0;                                
    for($i=0; $i < @{$a_data_object_ref}; $i++)
    {
        $h_modules_ref = $a_data_object_ref->[$i]->{modules};

    	$temp_str = "$a_data_object_ref->[$i]->{file_name}";
    	$temp_str = (length($temp_str) > 31) ? substr($temp_str, 0, 31) : $temp_str;
    	
        my $sheet = $workbook->add_worksheet($temp_str);
        
        $sheet->write(0, 1, "Raw data location:", $format3);
        if ($a_data_object_ref->[$i]->{raw_data} eq 'none')
        {
        	$sheet->write(0, 2, "none", $format3);
        }
        else
        {
            $sheet->write_url(0, 2, "external:$a_data_object_ref->[$i]->{raw_data}" );
        }
                

        # Add a handler to store the width of the longest string written to a column.
        $sheet->add_write_handler(qr[\w], \&store_string_widths);

        my $j = 0;
        my $key;
        my $value;
        my $temp_str = '';
        foreach my $key_module (sort(keys(%{$h_modules_ref}))) 
        {
            $sheet->write($frow + ($j * $hrow) + 1, $fcol, "$key_module", $format1);
            $sheet->write($frow + ($j * $hrow) + 1, $fcol + 1, "", $format1);
            $j++;
            foreach $key (sort(keys(%{$h_modules_ref->{$key_module}}))) 
	        {
	        	$value = $h_modules_ref->{$key_module}->{$key};
	        	$temp_str = "$value";
	        	$temp_str = sprintf("@$value") if ref($value) eq 'ARRAY';
                $temp_str = sprintf("%$value") if ref($value) eq 'HASH';
	            $temp_format = ( $j%2 ? $format2 : $format3);
	            $sheet->write($frow + ($j * $hrow) + 1, $fcol, "$key", $temp_format);
	            $sheet->write($frow + ($j * $hrow) + 1, $fcol + 1, $temp_str, $temp_format);
	            $j++;
	        }
        }
        # Run the autofit after you have finished writing strings to the workbook.
        autofit_columns($sheet);    
    }
} 


###############################################################################
#
# Create xls report
#
###############################################################################
sub create_report 
{
    my ($report_conf )=@_;

    my $view_type = Type_Line;
    my @a_raw_data = ();
    my @a_data;
    my @a_legend;
    my @a_data_object;
    my @a_data_view;
    my $temp_str = '';
    my $i=0;
    my $j=0;
    my $k=0;

    # Load YAML file into hash
    $i = 0;
    foreach my $file (sort(@{$report_conf->{src}})) 
    {
        my $data = eval {YAML::XS::LoadFile($file)};
        if (not defined $data or $@) 
        {
            die "$!";
        }
        
        if ( !is_valid($data) )
        {
            next;
        }

		if ($data)
		{
			my($filename, $directory, $suffix) = fileparse("$file", qr/\.[^.]*/);
		    my $temp_file = "$directory$filename.zip";
            $data->{file_name} = $filename;
            $data->{file_path} = $directory;
		    $data->{raw_data} = (! -e $temp_file) ? 'none' : $temp_file;

	        # Construct legend
	        $temp_str = "$i";
	        if (!@{$report_conf->{legend}})
	        {
	            my($filename, $directory, $suffix) = fileparse("$file", qr/\.[^.]*/);
	            $temp_str = "$temp_str-$filename";
	        }
	        else
	        {
	            foreach (@{$report_conf->{legend}})
	            {
	                if (exists($data->{modules}->{TestRunPhase}->{$_})) 
	                {
	                    $temp_str = "$temp_str-$data->{modules}->{TestRunPhase}->{$_}";
	                }
	                elsif ($_ eq 'filename')
	                {
	                    my($filename, $directory, $suffix) = fileparse("$file", qr/\.[^.]*/);
	                    $temp_str = "$temp_str-$filename";
	                }
	            }
	        }   
            $data->{legend} = $temp_str;
		}
        
        # Parse source file and save data in special structure
        push (@a_data_object, $data);
        
        $i++;                
    }

    if ($#a_data_object == (-1))
    {
    	return ;
    }

    my $workbook = Spreadsheet::WriteExcel->new($report_conf->{dest});
    if (!defined($workbook))
    {
        die "$!\n";
    }
            
    # Create 'Title' tab
    if ( $opt_tab_title )
    {
        create_sheet_title($workbook, $report_conf->{title}, \@a_data_object);
    }

    # Create data for 'View' tabs
    for($i=0; $i < $report_conf->{data_count}; $i++)
    {   	
        # Check input data
        if (!defined($report_conf->{axis_x}->[$i]))
        {
        	die "incorrect view condition (axis_x is not set)\n";
        }
        elsif (!defined($report_conf->{axis_y}->[$i]))
        {
        	die "incorrect view condition (axis_y is not set)\n";
        }
            
        # create array of arrays for graph
        # first array is assumed to be the x-axis labels 
        $report_conf->{label_x}->[$i] = $report_conf->{axis_x}->[$i] if (!defined($report_conf->{label_x}->[$i]));
        $report_conf->{label_y}->[$i] = $report_conf->{axis_y}->[$i] if (!defined($report_conf->{label_y}->[$i]));
        $report_conf->{label_x}->[$i] = "" if ($report_conf->{label_x}->[$i] eq 'none');
        $report_conf->{label_y}->[$i] = "" if ($report_conf->{label_y}->[$i] eq 'none');

        @a_data = ();
        @a_legend = ();
        my $a_data_ref = 0;
        my $graph_type = Type_Column;

#        {
            # Prepare data for axis X and axis Y
            $j=0;
            foreach (@a_data_object)
            {
                $a_data_ref = $_->{modules}->{TestRunPhase};

                # Check error condition
                if (defined($report_conf->{match}) && !($_->{file_path} =~ /^$report_conf->{match}->[$i]/))
                {
                    next;
                }
                
                if ($report_conf->{axis_x}->[$i] ne 'none' &&
                      !exists($a_data_ref->{$report_conf->{axis_x}->[$i]}))
                {
                    #die "incorrect view condition (axis_x=$report_conf->{axis_x}->[$i] data is not found in file)\n";
                    next;
                }
                elsif ($report_conf->{axis_y}->[$i] ne 'none' &&
                      !exists($a_data_ref->{$report_conf->{axis_y}->[$i]}))
                {
                    #die "incorrect view condition (axis_y=$report_conf->{axis_y}->[$i] data is not found in file)\n";
                    next;
                }
                elsif (is_array( $a_data_ref->{$report_conf->{axis_x}->[$i]}) &&
                      !is_array( $a_data_ref->{$report_conf->{axis_y}->[$i]}))
                {
                    #die "incorrect view condition (axis_x=$report_conf->{axis_x}->[$i] is an array while axis_y=$report_conf->{axis_y}->[$i] is value)\n";
                    next;
                }
                elsif (!is_array( $a_data_ref->{$report_conf->{axis_x}->[$i]}) &&
                      is_array( $a_data_ref->{$report_conf->{axis_y}->[$i]}))
                {
                    #die "incorrect view condition (axis_x=$report_conf->{axis_x}->[$i] is value while axis_y=$report_conf->{axis_y}->[$i] is an array)\n";
                    next;
                }


	            # Fill data
		        if ($report_conf->{axis_x}->[$i] eq 'none')
		        {
		            if ($j == 0)
		            {
		            	$a_data[0][0] = '';	
		            }
	           
	                    $a_data[$j+1][0] = $a_data_ref->{$report_conf->{axis_y}->[$i]};
		        }		        
		        elsif (is_array( $a_data_ref->{$report_conf->{axis_x}->[$i]}) &&
		            is_array( $a_data_ref->{$report_conf->{axis_y}->[$i]}))
		        {
	                    if ($j == 0)
	                    {
	                        $temp_str = $a_data_ref->{$report_conf->{axis_x}->[$i]};
	                        $temp_str =~ s/^\{//i;
	                        $temp_str =~ s/\}$//i;
	                        push (@{$a_data[0]}, split(/,/,$temp_str));
	
	                        $graph_type = Type_Line;
	                    }
	                    $temp_str = $a_data_ref->{$report_conf->{axis_y}->[$i]};
	                    $temp_str =~ s/^\{//i;
	                    $temp_str =~ s/\}$//i;
	                    push (@{$a_data[$j+1]}, split(/,/,$temp_str));
                }
	            else
	            {
	                for($k=0; (defined($a_data[0]) && $k < @{$a_data[0]}); $k++)
	                {
	                	if ($a_data[0][$k] eq $a_data_ref->{$report_conf->{axis_x}->[$i]})
	                	{
	                        last;
	                    }
	                }
		                
	                if (!defined($a_data[0]) || $k == @{$a_data[0]})
	                {
	                    $a_data[0][$k] = $a_data_ref->{$report_conf->{axis_x}->[$i]};
	                }
	
	                for($k=0; $k < @{$a_data[0]}; $k++)
	                {
	                    if ($a_data[0][$k] eq $a_data_ref->{$report_conf->{axis_x}->[$i]})
	                    {
	                        $a_data[$j+1][$k] = $a_data_ref->{$report_conf->{axis_y}->[$i]};
	                    }
	                    else
	                    {
	                        $a_data[$j+1][$k] = undef;
	                    }
	                }
	            }
                push (@a_legend, $_->{legend});
                $j++;

            }

            # error processing in case a_data array is empty            
            next if ($#a_data == (-1));
            
            # Sort numeric axis_x labels
            my $re = qr/^\d+$/;
            if (check_list_to_regexp($re, $a_data[0]))
            {
            	my @a_temp = @a_data;

            	
            	@{$a_data[0]} = sort { $a <=>$b } @{$a_data[0]};
            	for($j=0; $j < @{$a_data[0]}; $j++)
            	{
                    for($k=0; $k < @{$a_data[0]}; $k++)
                    {
                        if ($a_data[0][$j] == $a_temp[0][$k])
                        {
                            for(my $l=1; $l < scalar(@a_data); $l++)
                            {
                                $a_data[$l][$j] = $a_temp[$l][$k]; 
                            }
                            last;
                        }
                    }
                }
            }
#        }
            
        # We do not display sheet if all data is '0' or the display the same property by both axises
        if ((min_2D(\@a_data, 1) == 0 && max_2D(\@a_data, 1) == 0) ||
            $report_conf->{axis_x}->[$i] eq $report_conf->{axis_y}->[$i])
        {
            printf("Warn: Can not create 'View' tab '$report_conf->{axis_x}->[$i]-$report_conf->{axis_y}->[$i]'\n");            
            next;
        }
        
        # wrap long axis X label string 
        # (GD library does not support wrapped string as a result
        # following code is disabled before another way will be found)    
#        foreach (@{$a_data[0]})
#        {
#        	
#            $_ = str_wrap($_);
#        } 
        
        my $chart_ex = undef;
        if (defined($report_conf->{chart_ex}->[$i]) && $report_conf->{chart_ex}->[$i] ne 'none')
        {
            $graph_type = Type_External;
            $chart_ex = $report_conf->{chart_ex}->[$i];
        }
      	$temp_str = "view\#$i";

        push (@a_data_view, 
                { view_type => $graph_type, 
                  a_label => [$report_conf->{label_x}->[$i], $report_conf->{label_y}->[$i]],
                  a_legend => [@a_legend],
                  a_data => [@a_data],
                  caption => $temp_str,
                  title => "$report_conf->{axis_x}->[$i]-$report_conf->{axis_y}->[$i]",
                  position => [1, 3],
                  chart_ex => $chart_ex
                });
    }

    # Create 'View' tabs
    if ( $opt_tab_view )
    {
        create_sheet_view($workbook, \@a_data_view);
    }

    # Create 'Data' tabs
    if ( $opt_tab_data )
    {
        create_sheet_data($workbook, \@a_data_object);
    }
    
    $workbook->close();
}


###############################################################################
#
# Send generated xls report as an attachment by e-mail
#
###############################################################################
sub send_results_by_mail 
{
    my ($mail_to, $mail_file) = @_;
    system("echo report is attached | /usr/bin/mutt -s 'breport $mail_file' -a $mail_file $mail_to");
}


##############################################################################
#
# Simuluate Excel's autofit for colums widths.
#
#
# Excel provides a function called Autofit (Format->Columns->Autofit) that
# adjusts column widths to match the length of the longest string in a column.
# Excel calculates these widths at run time when it has access to information
# about string lengths and font information. This function is *not* a feature
# of the file format and thus cannot be implemented by Spreadsheet::WriteExcel.
#
# However, we can make an attempt to simulate it by keeping track of the
# longest string written to each column and then adjusting the column widths
# prior to closing the file.
#
# We keep track of the longest strings by adding a handler to the write()
# function. See add_handler() in the S::WE docs for more information.
#
# The main problem with trying to simulate Autofit lies in defining a
# relationship between a string length and its width in a arbitrary font and
# size. We use two aproaches below. The first is a simple direct relationship
# obtrained by trial and error. The second is a slightly more sophisticated
# method using an external module. For more complicated applications you will
# probably have to work out your own methods.
#
# reverse('©'), May 2006, John McNamara, jmcnamara@cpan.org
#



###############################################################################
###############################################################################
#
# Functions used for Autofit.
#

###############################################################################
#
# Adjust the column widths to fit the longest string in the column.
#
sub autofit_columns {

    my $worksheet = shift;
    my $col       = 0;

    for my $width (@{$worksheet->{__col_widths}}) {

        $worksheet->set_column($col, $col, $width) if $width;
        $col++;
    }
}


###############################################################################
#
# The following function is a callback that was added via add_write_handler()
# above. It modifies the write() function so that it stores the maximum
# unwrapped width of a string in a column.
#
sub store_string_widths {

    my $worksheet = shift;
    my $col       = $_[1];
    my $token     = $_[2];

    # Ignore some tokens that we aren't interested in.
    return if not defined $token;       # Ignore undefs.
    return if $token eq '';             # Ignore blank cells.
    return if ref $token eq 'ARRAY';    # Ignore array refs.
    return if $token =~ /^=/;           # Ignore formula

    # Ignore numbers
#    return if $token =~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/;

    # Ignore various internal and external hyperlinks. In a real scenario
    # you may wish to track the length of the optional strings used with
    # urls.
    return if $token =~ m{^[fh]tt?ps?://};
    return if $token =~ m{^mailto:};
    return if $token =~ m{^(?:in|ex)ternal:};

    # We store the string width as data in the Worksheet object. We use
    # a double underscore key name to avoid conflicts with future names.
    #
    my $old_width    = $worksheet->{__col_widths}->[$col];
    my $string_width = string_width($token);

    if (not defined $old_width or $string_width > $old_width) {
        # You may wish to set a minimum column width as follows.
        #return undef if $string_width < 10;

        $worksheet->{__col_widths}->[$col] = $string_width;
    }

    # Return control to write();
    return undef;
}


###############################################################################
#
# Very simple conversion between string length and string width for Arial 10.
# See below for a more sophisticated method.
#
sub string_width {

    return 1.1 * length($_[0]);
}


