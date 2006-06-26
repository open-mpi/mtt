#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

use strict;
use LWP;
use Getopt::Long;
use Cwd;
use lib cwd();
use MTT::Version;

# Testing code for perfbase http submits

my $URL = 'https://www.osl.iu.edu/~afriedle/perfbase/';

my $file_arg;
my $xml_arg;
my $url_arg;
my $user_arg;
my $pass_arg;
my $ver_major = $MTT::Version::Major;
my $ver_minor = $MTT::Version::Minor;
my $debug_arg;
my $help_arg;
my $realm_arg = "perfbase";

# TODO - do i need this?
#&Getopt::Long::Configure("bundling", "require_order");

my $ok = Getopt::Long::GetOptions("file|f=s" => \$file_arg,
                                   "xml|x=s" => \$xml_arg,
                                   "username|u=s" => \$user_arg,
                                   "password|p=s" => \$pass_arg,
                                   "realm|r=s" => \$realm_arg,
                                   "version-major" => \$ver_major,
                                   "version-minor" => \$ver_minor,
                                   "url|l=s" => \$url_arg,
                                   "debug|d" => \$debug_arg,
                                   "help|h" => \$help_arg
                                   );

if(!$file_arg || !$xml_arg || !$user_arg || !$pass_arg || $help_arg || !$ok) {
    print "Usage: $0 --file|-f filename\n";
    print "\t--xml|-x xmlfile\n";
    print "\t--username|-u username (HTTP auth)\n";
    print "\t--password|-p password (HTTP auth)\n";
    print "\t--realm|-r realm (HTTP auth)\n";
    print "\t--version-major major (debugging use only)\n";
    print "\t--version-minor minor (debugging use only)\n";
    print "\t[--url|-l url]\n";
    print "\t[--debug|-d]\n";
    print "\t[--help|-h]\n";

    exit($ok);
}

if(!$url_arg) {
    $url_arg = $URL;
}

my $debug = ($debug_arg ? 1 : 0);
print "Debugging enabled!\n" if ($debug);

# Read in the file.
if(!open(DAT, $file_arg))
{
    print "ERROR: could not open file $file_arg\n";
    exit(-1);
}
    
my $data = do { local($/); <DAT> };
close(DAT);

# Push our data off to the server.
my $browser = LWP::UserAgent->new();

if($url_arg =~ m#http(s|)://([^/]*)#) {
    my $port = "80";
    $port = "443" if $1 eq "s";

    $browser->credentials("$2:$port", $realm_arg, $user_arg => $pass_arg);
} else {
    print "ERROR: invalid url format in $url_arg\n";
    exit(-1);
}

my $response = $browser->post($url_arg,
        [ 'PBXML' => $xml_arg,
          'PBINPUT' => $data,
          'MTTVERSION_MAJOR' => $ver_major,
          'MTTVERSION_MINOR' => $ver_minor ]);

if(!$response->is_success) {
    print "ERROR: POST to $url_arg failed\n";
    print $response->content;
    exit(-1);
} elsif($debug) {
    print "SUCCESS\n";
    print $response->content;
}

