#!/bin/bash
set -e

python /opt/mtt/server/php/cherrypy/bin/mtt_server_service.py start
# Loop here so docker container does not exit
tail -f /dev/null
