#!/bin/bash
#

#
# Copyright (c) 2017-2018   UT-Battelle, LLC
#                           All rights reserved.
#

set -e

PGPASSWORD="$MTTDBPWD" psql -h $OPENSHIFT_MTT_DB_IP -U mtt mtt -f ../sql/schemas-v3.sql
PGPASSWORD="$MTTDBPWD" psql -h $OPENSHIFT_MTT_DB_IP -U mtt mtt -f ../sql/summary/summary_tables.sql
PGPASSWORD="$MTTDBPWD" psql -h $OPENSHIFT_MTT_DB_IP -U mtt mtt -f ../sql/summary/summary_trigger.sql
PGPASSWORD="$MTTDBPWD" psql -h $OPENSHIFT_MTT_DB_IP -U mtt mtt -f ../sql/schemas-stats.sql
PGPASSWORD="$MTTDBPWD" psql -h $OPENSHIFT_MTT_DB_IP -U mtt mtt -f ../sql/schemas-reporter.sql
PGPASSWORD="$MTTDBPWD" psql -h $OPENSHIFT_MTT_DB_IP -U mtt mtt -f ../sql/schemas-indexes.sql
