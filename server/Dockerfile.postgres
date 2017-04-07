FROM postgres

MAINTAINER Noah van Dresser <daniel.n.van.dresser@intel.com>

# Pull in the MTT DB server configuration files
ADD sql /opt/mtt/server/sql
RUN chown -R postgres /opt/mtt/server/sql
ADD docker/mtt_db.sh /docker-entrypoint-initdb.d/mtt_db.sh
