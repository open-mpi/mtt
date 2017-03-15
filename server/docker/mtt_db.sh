#!/bin/bash
set -e

psql --command "CREATE USER mtt WITH LOGIN PASSWORD 'mttuser' CREATEDB CREATEROLE;" && \
psql --command "CREATE USER mtt_viewer WITH LOGIN PASSWORD 'mttviewer';" && \
psql --command "CREATE DATABASE mtt WITH OWNER mtt;" && \
psql -U mtt mtt -f /opt/mtt/server/sql/schemas-v3.sql && \
psql -U mtt mtt -f /opt/mtt/server/sql/summary/summary_tables.sql && \
psql -U mtt mtt -f /opt/mtt/server/sql/summary/summary_trigger.sql && \
psql -U mtt mtt -f /opt/mtt/server/sql/schemas-stats.sql && \
psql -U mtt mtt -f /opt/mtt/server/sql/schemas-reporter.sql && \
psql -U mtt mtt -f /opt/mtt/server/sql/schemas-indexes.sql
