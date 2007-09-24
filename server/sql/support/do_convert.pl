#!/usr/bin/env perl

use strict;

# Perform flush after each write to STDOUT
$| = 1;

my $conv_script = "./convert-v2-to-v3.pl";
#my $conv_script = "./simple.pl";

my $total_start_time;
my $script_start_time;
my $script_end_time;
my $total_end_time;

my @interval_next = ();
my @interval_cur  = ();
my @interval_prev = ();

# Past 12 hours
#my $start_interval = "start_timestamp > now() - interval '1 day' - interval '12 hours' and start_timestamp < now() - interval '1 day'";
# mtt_epoch - Feb 2007
#my $start_interval = "start_timestamp < DATE '2007-02-01'";
# Feb 2007 - Mar 2007
#my $start_interval = "start_timestamp >= DATE '2007-02-01' and start_timestamp < DATE '2007-03-01'";

###################################
# Series of ranges to insert when converting data
###################################
# mtt_epoch - Dec 2006
push(@interval_prev, "start_timestamp < DATE '2006-12-01'");
# Dec 2006 - Jan 2007 (62935)
push(@interval_prev, "start_timestamp >= DATE '2006-12-01' and start_timestamp < DATE '2007-01-01'");
# Jan 2007 - Feb 2007 (964166)
push(@interval_prev, "start_timestamp >= DATE '2007-01-01' and start_timestamp < DATE '2007-02-01'");

# Feb 2007 - Feb + 2 weeks (617497)
push(@interval_prev, "start_timestamp >= DATE '2007-02-01' and start_timestamp < DATE '2007-02-01' + interval '2 weeks'");
# Feb + 2 weeks -> Mar 2007 (839301)
push(@interval_prev, "start_timestamp >= DATE '2007-02-01' + interval '2 weeks' and start_timestamp < DATE '2007-03-01'");

# Mar 2007 - Mar + 2 weeks (859526)
push(@interval_prev, "start_timestamp >= DATE '2007-03-01' and start_timestamp < DATE '2007-03-01' + interval '2 weeks'");
# Mar + 2 weeks -> April 2007 (919403)
push(@interval_prev, "start_timestamp >= DATE '2007-03-01' + interval '2 weeks' and start_timestamp < DATE '2007-04-01'");

# Apr 2007 - Apr + 1 weeks (321207)
push(@interval_prev, "start_timestamp >= DATE '2007-04-01' and start_timestamp < DATE '2007-04-01' + interval '1 weeks'");
# Apr 2007 + 1 wk - Apr + 2 wks (730316)
push(@interval_prev, "start_timestamp >= DATE '2007-04-01' + interval '1 weeks' and start_timestamp < DATE '2007-04-01' + interval '2 weeks'");
# Apr 2007 + 2 wk - Apr + 3 wks (723485)
push(@interval_prev, "start_timestamp >= DATE '2007-04-01' + interval '2 weeks' and start_timestamp < DATE '2007-04-01' + interval '3 weeks'");
# Apr + 3 weeks -> May 2007 (767480)
push(@interval_prev, "start_timestamp >= DATE '2007-04-01' + interval '3 weeks' and start_timestamp < DATE '2007-05-01'");

# May 2007 - May + 1 weeks (694621)
push(@interval_prev, "start_timestamp >= DATE '2007-05-01' and start_timestamp < DATE '2007-05-01' + interval '1 weeks'");
# May 2007 + 1 wk - May + 2 wks (527013)
push(@interval_prev, "start_timestamp >= DATE '2007-05-01' + interval '1 weeks' and start_timestamp < DATE '2007-05-01' + interval '2 weeks'");
# May 2007 + 2 wk - May + 3 wks (759602)
push(@interval_prev, "start_timestamp >= DATE '2007-05-01' + interval '2 weeks' and start_timestamp < DATE '2007-05-01' + interval '3 weeks'");
# May 2007 + 3 wk - May + 4 wks (745606)
push(@interval_prev, "start_timestamp >= DATE '2007-05-01' + interval '3 weeks' and start_timestamp < DATE '2007-05-01' + interval '4 weeks'");
# May 2007 + 4 wk - June 2007 (432868)
push(@interval_prev, "start_timestamp >= DATE '2007-05-01' + interval '4 weeks' and start_timestamp < DATE '2007-06-01'");

# June 2007 - June + 1 weeks (811239)
push(@interval_prev, "start_timestamp >= DATE '2007-06-01' and start_timestamp < DATE '2007-06-01' + interval '1 weeks'");
# June 2007 + 1 wk - June + 2 wks (661049)
push(@interval_prev, "start_timestamp >= DATE '2007-06-01' + interval '1 weeks' and start_timestamp < DATE '2007-06-01' + interval '2 weeks'");
# June 2007 + 2 wk - June + 3 wks - 4 days (474144)
push(@interval_prev, ("start_timestamp >= DATE '2007-06-01' + interval '2 weeks' and " .
                      "start_timestamp <  DATE '2007-06-01' + interval '3 weeks' - interval '4 days'"));
# June 2007 + 3 wks - 4 days -> June + 3 wks (567893)
push(@interval_prev, ("start_timestamp >= DATE '2007-06-01' + interval '3 weeks' - interval '4 days' and " .
                      "start_timestamp <  DATE '2007-06-01' + interval '3 weeks'"));
# June 2007 + 3 wk - June + 4 wks - 4 days (629416)
push(@interval_prev, ("start_timestamp >= DATE '2007-06-01' + interval '3 weeks' and " .
                      "start_timestamp <  DATE '2007-06-01' + interval '4 weeks' - interval '4 days'"));
# June 2007 + 4 wks - 4 days -> June + 4 wks (763639)
push(@interval_prev, ("start_timestamp >= DATE '2007-06-01' + interval '4 weeks' - interval '4 days' and " .
                      "start_timestamp <  DATE '2007-06-01' + interval '4 weeks'"));
# June 2007 + 4 wk - July 2007 (429851)
push(@interval_prev, "start_timestamp >= DATE '2007-06-01' + interval '4 weeks' and start_timestamp < DATE '2007-07-01'");

# July 2007 - July + 1 wks - 4 days (404708)
push(@interval_prev, ("start_timestamp >= DATE '2007-07-01' and " .
                      "start_timestamp <  DATE '2007-07-01' + interval '1 weeks' - interval '4 days'"));
# July 2007 + 1 wks - 4 days -> July + 1 wks (1018539)
push(@interval_prev, ("start_timestamp >= DATE '2007-07-01' + interval '1 weeks' - interval '4 days' and " .
                     "start_timestamp <  DATE '2007-07-01' + interval '1 weeks' - interval '2 days'"));
push(@interval_prev, ("start_timestamp >= DATE '2007-07-01' + interval '1 weeks' - interval '2 days' and " .
                     "start_timestamp <  DATE '2007-07-01' + interval '1 weeks'"));
# July 2007 + 1 wk - July + 2 wks - 4 days (606427)
push(@interval_prev, ("start_timestamp >= DATE '2007-07-01' + interval '1 weeks' and " .
                     "start_timestamp <  DATE '2007-07-01' + interval '2 weeks' - interval '4 days'"));
# July 2007 + 2 wks - 4 days -> July + 2 wks (792623)
push(@interval_prev, ("start_timestamp >= DATE '2007-07-01' + interval '2 weeks' - interval '4 days' and " .
                     "start_timestamp <  DATE '2007-07-01' + interval '2 weeks'"));
# July 2007 + 2 wk - July + 3 wks (324043 + 638919 = 962962)
push(@interval_prev, ("start_timestamp >= DATE '2007-07-01' + interval '2 weeks' and " .
                     "start_timestamp <  DATE '2007-07-01' + interval '3 weeks' - interval '4 days'"));
push(@interval_prev, ("start_timestamp >= DATE '2007-07-01' + interval '3 weeks' - interval '4 days' and " .
                     "start_timestamp <  DATE '2007-07-01' + interval '3 weeks'"));
# July 2007 + 3 wk - July + 4 wks (307338 + 658955 = 966293)
push(@interval_prev, ("start_timestamp >= DATE '2007-07-01' + interval '3 weeks' and " .
                     "start_timestamp <  DATE '2007-07-01' + interval '4 weeks' - interval '4 days'"));
push(@interval_prev, ("start_timestamp >= DATE '2007-07-01' + interval '4 weeks'  - interval '4 days' and " .
                     "start_timestamp <  DATE '2007-07-01' + interval '4 weeks'"));
# July 2007 + 4 wk - Aug 2007 (324737)
push(@interval_prev, "start_timestamp >= DATE '2007-07-01' + interval '4 weeks' and start_timestamp < DATE '2007-08-01'");


# Aug 2007 - Aug + 1 wks - 4 days (527627)
push(@interval_prev, ("start_timestamp >= DATE '2007-08-01' and " .
                      "start_timestamp <  DATE '2007-08-01' + interval '1 weeks' - interval '4 days'"));
# Aug 2007 + 1 wks - 4 days -> Aug + 1 wks (278940 + 155511)
push(@interval_prev, ("start_timestamp >= DATE '2007-08-01' + interval '1 weeks' - interval '4 days' and " .
                      "start_timestamp <  DATE '2007-08-01' + interval '1 weeks' - interval '1 day'"));
push(@interval_prev, ("start_timestamp >= DATE '2007-08-01' + interval '1 weeks' - interval '1 day' and " .
                      "start_timestamp <  DATE '2007-08-01' + interval '1 weeks'"));
######## JJH BREAK #######################
# Aug 2007 + 1 wk - Aug + 2 wks - 4 days (--JJH--)
push(@interval_next, ("start_timestamp >= DATE '2007-08-01' + interval '1 weeks' and " .
                      "start_timestamp <  DATE '2007-08-01' + interval '2 weeks' - interval '4 days'"));
# Aug 2007 + 2 wks - 4 days -> Aug + 2 wks (--JJH--)
push(@interval_next, ("start_timestamp >= DATE '2007-08-01' + interval '2 weeks' - interval '4 days' and " .
                      "start_timestamp <  DATE '2007-08-01' + interval '2 weeks'"));
# Aug 2007 + 2 wk - Aug + 3 wks - 4 days (--JJH--)
push(@interval_next, ("start_timestamp >= DATE '2007-08-01' + interval '2 weeks' and " .
                      "start_timestamp <  DATE '2007-08-01' + interval '3 weeks' - interval '4 days'"));
# Aug 2007 + 3 wks - 4 days -> Aug + 3 wks (--JJH--)
push(@interval_next, ("start_timestamp >= DATE '2007-08-01' + interval '3 weeks' - interval '4 days' and " .
                      "start_timestamp <  DATE '2007-08-01' + interval '3 weeks'"));
# Aug 2007 + 3 wk - Aug + 4 wks - 4 days (--JJH--)
push(@interval_next, ("start_timestamp >= DATE '2007-08-01' + interval '3 weeks' and " .
                      "start_timestamp <  DATE '2007-08-01' + interval '4 weeks' - interval '4 days'"));
# Aug 2007 + 4 wks - 4 days -> Aug + 4 wks (--JJH--)
push(@interval_next, ("start_timestamp >= DATE '2007-08-01' + interval '4 weeks' - interval '4 days' and " .
                      "start_timestamp <  DATE '2007-08-01' + interval '4 weeks'"));
# Aug 2007 + 4 wk - Sept 2007 (--JJH--)
push(@interval_next, "start_timestamp >= DATE '2007-08-01' + interval '4 weeks' and start_timestamp < DATE '2007-09-01'");

#
# Special selects
#
# Past 2 days
push(@interval_next, ("start_timestamp >= DATE 'now' - interval '2 days' and ".
                      "start_timestamp <  DATE 'now' - interval '0 hours'"));
push(@interval_cur, ("start_timestamp >= DATE 'now' - interval '2 days' and ".
                     "start_timestamp <  TIMESTAMP 'now' - interval '12 hours'"));
# Day before yesterday
push(@interval_prev, ("start_timestamp >= DATE 'now' - interval '2 days' and ".
                      "start_timestamp <  DATE 'now' - interval '1 day'"));
# Yesterday:
push(@interval_prev, ("start_timestamp >= DATE 'now' - interval '1 day' and ".
                     "start_timestamp <  DATE 'now' - interval '0 hours'"));
# Today
push(@interval_next, ("start_timestamp >= DATE 'now' - interval '0 days'"));

###################################
# End Time series
###################################

$total_start_time = time();

my $iv;
my $tt;

# Currently Needed
foreach $iv (@interval_cur) {
  $script_start_time = time();

  system($conv_script . " \"$iv\"");

  $script_end_time = time();

  printf("===========================\n");
  printf("Finished: $iv\n");
  $tt = (($script_end_time - $script_start_time)/60.0);
  printf("Time Segment: %5.2f min.\n", $tt);
}

$total_end_time = time();

printf("===========================\n");
$tt = (($total_end_time - $total_start_time)/60.0);
printf("Finished Everything in Time: %5.2f min. [%5.2f days]\n",
       $tt, ($tt/(60*24.0)) );

exit 0;
