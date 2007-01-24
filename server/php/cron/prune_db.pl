#!/usr/bin/env perl

#
# Prune the mtt database
#

use Getopt::Std qw(getopts);

getopts('dvhy');

my $user = "mtt";
my $db = "mtt3";

# Window (in days) to keep data in database
my $days_for_all = 30;
my $days_for_trial = 7;

die "\nUsage: $0 -y days" if ($opt_h);

# Process command-line options
if ($opt_d) { $debug = 1; }
if ($opt_v) { $verbose = 1; }
if ($opt_y) { $days_for_all = $opt_y; }

# WHERE clause to DELETE trial results
my $trial_clause = " AND results.trial = 't'";

# We have to go in descending order
# because of the FOREIGN KEY constraints
my @phases = ('test_run', 'test_build', 'mpi_install');

my @cmds;

# Run DELETE then run VACUUM (to reclaim disk space)
# (see postgresql.org/docs/7.4/interactive/sql-vacuum.html)
$cmds[0] = <<EOT;
    DELETE FROM %s WHERE
        results.phase = %d AND
        results.phase_id = %s.%s_id AND
        results.start_timestamp < now() - interval '%d days'
        %s;
EOT
$cmds[1] = "VACUUM VERBOSE ANALYZE %s;";

my $i = 3;
foreach my $phase (@phases) {
    foreach my $cmd (@cmds) {

        # Still waiting on how large a window of data to keep

        # do_system("\npsql " .
        #             "-d $db " .
        #             "-U $user " .
        #             "-c \"" .
        #                 sprintf($cmd,
        #                          $phase,
        #                          $i,
        #                          $phase,
        #                          $phase,
        #                          $days_for_all,
        #                          '') .
        #                  "\"");
        do_system("\npsql " .
                    "-d $db " .
                    "-U $user " .
                    "-c \"" .
                        sprintf($cmd,
                                 $phase,
                                 $i,
                                 $phase,
                                 $phase,
                                 $days_for_trial,
                                 $trial_clause) . 
                         "\"");
    }
    $i--;
}

$cmds[0] = <<EOT;
    DELETE FROM %s WHERE
        start_timestamp < now() - interval '%d days'
        %s;
EOT

foreach my $cmd (@cmds) {

    # do_system("\npsql " .
    #             "-d $db " .
    #             "-U $user " .
    #             "-c \"" .
    #                 sprintf($cmd,
    #                          'results',
    #                          $days_for_all) .
    #                  "\"");
    do_system("\npsql " .
                "-d $db " .
                "-U $user " .
                "-c \"" .
                    sprintf($cmd,
                             'results',
                             $days_for_trial,
                             $trial_clause) . 
                     "\"");
}

print "\n";

exit;

# ---

sub do_system() {
    my ($cmd) = @_;
    print "$cmd\n" if ($verbose or $debug);
    system $cmd if (! $debug);
}
