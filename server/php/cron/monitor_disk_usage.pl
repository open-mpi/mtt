#!/usr/bin/env perl

#
# Monitor disk usage of MTT database
#

use Getopt::Std qw(getopts);
getopts('dvh');

if ($opt_d) { $debug = 1; }
if ($opt_v) { $verbose = 1; }

my $user = "mtt";
my $db = "mtt3";

$cmd = <<EOT;
    SELECT 
         now() as timestamp,
         relname,
         relfilenode,
         (8 * relpages) || ' KB' as size 
    FROM pg_class 
    WHERE 
        relname = 'mpi_install' OR 
        relname = 'test_build' OR 
        relname = 'test_run' OR 
        relname = 'results';
EOT

do_system("\npsql -d $db -U $user -c \"$cmd\"");

print "\n";

exit;

# ---

sub do_system() {
    my ($cmd) = @_;
    print $cmd if ($verbose or $debug);
    system $cmd if (! $debug);
}
