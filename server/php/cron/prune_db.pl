#!/usr/bin/env perl

#
# Prune the MTT database
#

use Getopt::Std qw(getopts);

getopts('dvhy:b:n:');

my $user = "mtt";
my $db = "mtt3_1";

# Window (in days) to keep data in database
my $days_for_all = 30;
my $days_for_trial = 2;

# Process command-line options
if ($opt_d) { $debug        = 1; }
if ($opt_v) { $verbose      = 1; }
if ($opt_h) { $help         = 1; }
if ($opt_y) { $days_for_all = $opt_y; }
if ($opt_b) { $db           = $opt_b; }
if ($opt_n) { $now          = "TIMESTAMP '$opt_n'"; }

if (! $now) {
    $now = "now()";
}

# Print help and exit
if ($help) {
    print "Usage: $0 
        -b dataBase
        -y daYs to count back from 'now'
        -n set 'Now' timestamp to a constant
        -d Debug (commands printed, not executed)
        -v Verbose
        -h Help\n";
    exit;
}

# Define tables types, "speedy" and "archive"
my $speedy = 'speedy_';
my $archive = '';

# If CASCADE ON DELETE is set for the FOREGIN KEY
# constraints, then we would only need to delete from MPI
# Install (since the associated Test Build and Test Run rows
# would get DELETEd in the CASCADE)
my %phases = (
    'test_run'    => 3,
    'test_build'  => 2,
    'mpi_install' => 1,
);

# Timekeeping
my $start = time();

foreach my $type (($speedy, $archive)) {

    # We have to go in descending order
    # because of the FOREIGN KEY constraints
    foreach my $phase (sort keys %phases) {

        $i = $phases{$phase};

        # Only prune non-trial results for ''speedy'' TABLES
        #
        # TODO: FETCH A CONSTANT FOR NOW() IN TIMESTAMP COMPARE
        if ($type eq $speedy) {
            do_system(
                "\n psql -d $db -U $user -c \"DELETE FROM ${type}${phase} WHERE " .
                "\n     ${type}results.phase = $i AND " .
                "\n     ${type}results.phase_id = ${type}${phase}.${phase}_id AND " .
                "\n     ${type}results.start_timestamp < $now - INTERVAL '$days_for_all days' " .
                "\n     ;\"");
        }

        # Prune trial results
        do_system(
            "\n psql -d $db -U $user -c \"DELETE FROM ${type}${phase} WHERE " .
            "\n     ${type}results.phase = $i AND " .
            "\n     ${type}results.phase_id = ${type}${phase}.${phase}_id AND " .
            "\n     ${type}results.start_timestamp < $now - INTERVAL '$days_for_trial days' " .
            "\n      AND ${type}results.trial = 't';\"");

        # Run VACUUM after DELETE (to reclaim disk space)
        do_system("\n psql -d $db -U $user -c \"VACUUM ANALYZE ${type}${phase};\"");

        $i--;
    }

    # Lastly, prune results TABLE
    if ($type eq $speedy) {
        do_system(
            "\n psql -d $db -U $user -c \"DELETE FROM ONLY ${type}results WHERE " .
            "\n     start_timestamp < $now - INTERVAL '$days_for_all days' " .
            "\n     ;\"");
    }
    do_system(
        "\n psql -d $db -U $user -c \"DELETE FROM ONLY ${type}results WHERE " .
        "\n     start_timestamp < $now - INTERVAL '$days_for_trial days' " .
        "\n      AND ${type}results.trial = 't';\"");
    do_system("\n psql -d $db -U $user -c \"VACUUM ANALYZE ${type}results;\"");
}

# Timekeeping
my $end = time();
my $elapsed = $end - $start;

print "\n\nTotal elapsed time: $elapsed seconds\n";

exit;

# ---

sub do_system() {
    my ($cmd) = @_;
    my $start = time();

    print "$cmd\n" if ($verbose or $debug);
    system $cmd if (! $debug);

    my $end = time();
    my $elapsed = $end - $start;
    print "\nRunning time: $elapsed seconds\n";
}
