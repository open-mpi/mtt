# Create a docker user defined network
docker network create -d bridge --subnet 172.31.0.0/24 docker_network

# Build postgres docker image
docker build --build-arg http_proxy=$http_proxy --build-arg https_proxy=$https_proxy -t mttdb-postgres -f Dockerfile.postgres .
# Start the postgres server
docker run --name mttdb-postgres --network=docker_network --ip=172.31.0.2 -e POSTGRES_PASSWORD=mtt -d mttdb-postgres 
# Test container
PGPASSWORD="mtt" psql -a --host=172.31.0.2 --dbname=mtt --username=postgres

# Build cherrypy docker image
docker build --build-arg http_proxy=$http_proxy --build-arg https_proxy=$https_proxy -t mttdb-cherrypy -f Dockerfile.cherrypy . 
# Start the cherrypy server
docker run -e http_proxy=$http_proxy -e https_proxy=$https_proxy -e no_proxy=localhost,mttdb  --name mttdb-cherrypy --network=docker_network --ip=172.31.0.3 -dt mttdb-cherrypy /opt/mtt/server/docker/mtt_cherrypy.sh

# Test cherrypy RESTful interface
curl -H "Content-Type: application/json" -X POST -d '{"data" : [ {"bitness": 0, "endian": "test", "vpath_mode": "test", "platform_hardware": "test", "platform_type": "test", "os_name": "test", "os_version": "test", "compiler_name": "test", "compiler_version": "test", "mpi_name": "test", "mpi_version": "test", "configure_arguments": "test", "start_timestamp": "Mon Jan 1 00:00:00 2000", "duration": "0 Seconds", "result_message": "test", "test_result": 0, "exit_value": 0, "merge_stdout_stderr": 0, "result_stderr": "test"} ], "metadata" : {"client_serial": 12345, "hostname": "test.test.com", "local_username": "test", "mtt_client_version": "4.0a1", "phase": "MPI Install", "platform_name": "triton", "trial": 1}}' http://172.31.0.3:9080/submit --user mtt:mttuser
