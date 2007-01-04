#!/usr/bin/env perl

#
# Prune the mtt database
#

use Getopt::Std qw(getopts);
getopts('dvh');

die "\nUsage: $0 -y days" if ($opt_h);

if ($opt_d) { $debug = 1; }
if ($opt_v) { $verbose = 1; }
if ($opt_y) { $days = $opt_y; }

$days = 30 if (! $opt_y);

my $user = "mtt";
my $db = "mtt3";

# We have to go in descending order because of the 
# FOREIGN KEY constraints
@phases = ('test_run', 'test_build', 'mpi_install');

$i = 3;
foreach my $phase (@phases) {
    $cmd = <<EOT;
        DELETE FROM $phase WHERE
            results.phase = $i AND
            results.phase_id = $phase.${phase}_id AND
            results.start_timestamp < now() - interval '$days days';
EOT
    do_system("\npsql -d $db -U $user -c \"$cmd\"");
    $i--;
}

$cmd = <<EOT;
    DELETE FROM results WHERE
        start_timestamp < now() - interval '$days days';
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
