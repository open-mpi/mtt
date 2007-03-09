#!/usr/bin/env perl

#
# Monitor disk usage of MTT database
#

use Getopt::Std qw(getopts);
use Data::Dumper;
getopts('dvhb:u:f:m:t:');

my $user = "mtt";
my $db = "mtt3";
my $logfile;

# Grab command-line options
if ($opt_d) { $debug   = 1; }
if ($opt_v) { $verbose = 1; }
if ($opt_h) { $help    = 1; }
if ($opt_b) { $db      = $opt_b; }
if ($opt_u) { $user    = $opt_u; }
if ($opt_f) { $logfile = $opt_f; }
if ($opt_m) { $method  = $opt_m; }
if ($opt_t) { @tables  = split /,/, $opt_t; }

# Default to using SQL
$method = 'sql' if (! $method);

# Choose which tables to report on (presumably,
# these are the *big* ones)
if (! @tables) {
    @tables = (
        'results',
        'test_run',
        'speedy_results',
        'speedy_test_run',
    );
}
$tables_csv = join(',', @tables);

# Display help menu
if ($help) {
    print "$0:
         b (dataBase) : Database to use (default: $db)
         u (User)     : Postgres user to execute commands as (default: $user)
         f (logFile)  : Filename to write to (default: stdout)
         m (Method)   : { oid2name | sql } (default: $method)
         t (Tables)   : Tables in $db to monitor (default: $tables_csv)
         h (Help)     : This help
         d (Debug)    : Debug mode (default: off)
         v (Verbose)  : Verbose mode (default: off)
";
    exit;
}

# Setup logfile to write to
if ($logfile) {
    open(logfile, ">> $logfile");
} else {
    open(logfile, ">-");
}

# Monitor using oid2name
if ($method =~ /oid2name/i) {
    monitor_using_oid2name();
}
# Monitor using SQL
if ($method =~ /sql/i) {
    monitor_using_sql();
}

# Monitor using SQL
if ($method =~ /dbsize/i) {
    monitor_using_dbsize();
}

# Monitor row counts
if ($method =~ /rows/i) {
    monitor_rows();
}

exit;

# ---

sub monitor_using_oid2name {

    #
    # To setup oid2name:
    # 
    # * Download postgres tarball here:
    #       http://www.postgresql.org/ftp/source/v7.4.13/
    # * gzip -dc postgresql-7.4.13.tar.gz | tar xvf -
    # * cd postgresql-7.4.13
    # * ./configure
    # * cd src/port; gmake all
    # * cd ../../contrib/oid2name; gmake all
    #

    my $home     = $ENV{HOME};
    my $oid2name = "$home/bin/oid2name";
    my $pg_base  = "/var/lib/pgsql/data/base";
    my $awk1     = "awk '{print \$1}'";
    my $awk3     = "awk '{print \$3}'";

    # Get OID of database
    $db_oid = `$oid2name -U $user | grep -w $db | $awk1`;
    chomp($db_oid);

    # Assign directory where $db's data
    my $pg_data = "/var/lib/pgsql/data/base/$db_oid";

    # Timestamp the log entry
    print logfile `date`;

    # Do a du for each table ...
    foreach my $table (@tables) {

        # Get OID of table
        $cmd = "\n$oid2name -q -U $user -d $db -t $table | $awk1";
        debug($cmd);
        $oid = `$cmd`;
        chomp $oid;

        # Do the du
        $cmd = "\ndu -hs $pg_data/$oid | $awk1";
        debug($cmd);
        $du_out = `$cmd`;
        chomp $du_out;

        # Translate OID to table_name
        $cmd = "\n$oid2name -q -d $db -U mtt -o $oid | $awk3";
        debug($cmd);
        $oid2name_out = `$cmd`;
        chomp $oid2name_out;

        # Write to the logfile
        print logfile
                  "$du_out\t" . 
                  "$oid2name_out\n";
    }
}

sub monitor_using_sql {

    my $query = <<EOT;
        SELECT 
             now() as timestamp,
             relname,
             ((8 * relpages) / 1024) || ' MB' as size 
        FROM pg_class 
        WHERE 
EOT

    my @wheres;
    foreach my $table (@tables) {
        push(@wheres, "\n" . ("\t" x 3) . "relname = '$table'");
    }

    $query .= join(' OR ', @wheres) . ';';

    my $cmd = "\npsql -d $db -U $user -c \"$query\"";
    debug($cmd);
    print logfile `$cmd`;
}

sub monitor_rows {

    my $selections_str =
             
            "\n\tnow() as timestamp," .
            "\n\t" .
                join(",\n\t",
                      (map { "count_$_" . ".* AS count_$_" } @tables)
                );

    my $query = "\nSELECT $selections_str FROM \n\t";

    my @wheres;
    my $format = "(SELECT COUNT(*) AS count_%s FROM %s) AS count_%s";
    foreach my $table (@tables) {
        push(@selects, sprintf($format, $table, $table, $table));
    }
    $query .= "\n\t" . join(",\n\t", @selects) . "\n";
    $query .= "\n;";

    my $cmd = "\npsql -d $db -U $user -c \"$query\"";
    debug($cmd);
    print logfile `$cmd`;
}


sub monitor_using_dbsize {

    #
    # To setup dbsize:
    # 
    # * Download postgres tarball here:
    #       http://www.postgresql.org/ftp/source/v7.4.13/
    # * gzip -dc postgresql-7.4.13.tar.gz | tar xvf -
    # * cd postgresql-7.4.13
    # * ./configure
    # * cd contrib/dbsize; make; make all;
    # * Manually edit dbsize.sql so that it points to
    #   dbsize.so (use absolute path)
    # * psql -d <mtt_db> -U postgres -f dbsize.sql;
    #

    my $query = "SELECT database_size('$db') as $db ";

    my @selects;
    foreach my $table (@tables) {
        push(@selects, "\n" . ("\t" x 3) .  "relation_size('$table') as $table");
    }

    $query .= ', ' . join(', ', @selects) . ';';

    my $cmd = "\npsql -d $db -U $user -c \"$query\"";
    debug($cmd);
    print logfile `$cmd`;
}

sub debug {
    $str = shift;
    print $str . "\n" if ($debug or $verbose);
}
