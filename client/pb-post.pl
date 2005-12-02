#!/usr/bin/env perl
#
# Copyright (c) 2004-2005 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2004-2005 The Trustees of the University of Tennessee.
#                         All rights reserved.
# Copyright (c) 2004-2005 High Performance Computing Center Stuttgart, 
#                         University of Stuttgart.  All rights reserved.
# Copyright (c) 2004-2005 The Regents of the University of California.
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

my $URL = 'https://www.osl.iu.edu/~afriedle/perfbase/';

my $file_arg;
my $xml_arg;
my $url_arg;
my $user_arg;
my $pass_arg;
my $debug_arg;
my $help_arg;

# TODO - do i need this?
#&Getopt::Long::Configure("bundling", "require_order");

my $ok = Getopt::Long::GetOptions("file|f=s" => \$file_arg,
                                   "xml|x=s" => \$xml_arg,
                                   "username|u=s" => \$user_arg,
                                   "password|p=s" => \$pass_arg,
                                   "url|l=s" => \$url_arg,
                                   "debug|d" => \$debug_arg,
                                   "help|h" => \$help_arg
                                   );

if (!$file_arg || !$xml_arg || !$user_arg || !$pass_arg || $help_arg || !$ok) {
    print "Usage: $0 --file|-f filename\n";
    print "\t--xml|-x xmlfile\n";
    print "\t--username|-u username\n";
    print "\t--password|-p password\n";
    print "\t[--url|-l url]\n";
    print "\t[--debug|-d]\n";
    print "\t[--help|-h]\n";

    exit($ok);
}

if (!$url_arg) {
    $url_arg = $URL;
}

my $debug = ($debug_arg ? 1 : 0);
print "Debugging enabled!\n" if ($debug);

# Read in the file.
if (!open(DAT, $file_arg))
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

    $browser->credentials("$2:$port", "perfbase", $user_arg => $pass_arg);
} else {
    print "ERROR: invalid url format in $url_arg\n";
    exit(-1);
}

my $response = $browser->post($url_arg,
        [ 'PBXML' => $xml_arg,
          'PBINPUT' => $data ]);

if (!$response->is_success) {
    print "ERROR: POST to $url_arg failed\n";
    exit(-1);
}

print $response->content if ($debug);

