### MTT Dockerized Jenkins Console

The MTT Dockerized Jenkins Console provides an interface to control MTT through a system that allows remote execution, recurring execution, XML results reporting, among many other possibilities.

This console is a Jenkins instance that runs through a Docker container. The Dockerfile that builds the console takes in several parameters as input that allow for connecting the console to any target cluster.

##### Prerequisites

1. Install Docker (tested with version 1.12.3)
2. Pull official Jenkins Docker image
```
$ docker pull jenkins
```

##### Building the image

Assumptions in these instructions:
* The name of image is "mttconsole" (change this to desired image name)
* MTT is installed in /opt directory (change this if MTT is installed to a different directory)

1. Gain root privaleges by typing `sudo su`
2. Assuming MTT is installed in `/opt` directory, navigate to `/opt/mtt/tests/jenkins`
3. Type this into terminal, replacing sample build arguments with the desired values:
```
docker build \
--build-arg proxy_server=sample.proxy.server.com \
--build-arg proxy_port=123 \
--build-arg slave_node_name=sampleslavenode \
--build-arg slave_node_num_computes=4 \
--build-arg slave_node_ip_addr=10.20.30.40 \
--build-arg slave_node_num_executors=2 \
--build-arg slave_node_ssh_username=root \
--build-arg slave_node_exec_dir=\\/home\\/test\\/jenkins \
--build-arg master_num_executors=2 \
--build-arg compute_node_names="node1 node2 node3 node4" \
-t mttconsole .
```

##### Running the console

Assumptions in these instructions:
* The port to access the console from is 8070 (change this to desired port)
* The name of the running console instance is "mttconsolerun" (change this to desired docker instance name)

1. Type this into terminal:
```
docker run -d -p 8070:8080 --name mttconsolerun -v mttconsole:/home/jenkins mttconsole
```
2. Access the console at <host_ip>:8070 from your web browser

##### To find the volume on the docker host
```
docker volume inspect mttconsole
```
The Mountpoint path is the location where the volume is mounted, anything in here will survive a contain stop and removal.  Use `docker volume rm mttconsole` to clear it.

##### Securing console

The console starts up with one user. This user has username "admin" and password "adminpass". Login as this user, change its password to something diferent, and add any other user accounts that are needed.

##### Setting up SSH keys to slave node

1. Type `ssh-keygen` command to generate a key for use for SSHing between the console and the slave node.
2. Type `cat <name of key>.pub` to obtain the public key text. Copy that text.
3. Log in to the slave node as the user that the console is configured for connection to
4. Paste the public key into `~/.ssh/authorized_keys`
5. Navigate back to the place where the keys are stored
6. Type `cat <name of key>` to obtain the private key text. Copy that text.
7. Open up the console in the web browser and login as admin user
8. Click "Credentials" then "Global" then "root" then "Update"
9. Click "Enter directly" and paste private key into the box labeled "key". If there is a passphrase, enter the passphrase into the box labeled "Passphrase".
10. Click "Save"
11. Go back to Jenkins home screen, click on slave node, and relaunch agent
12. If the agent still does not launch, make sure that Java is installed on the slave node and then relaunch again

##### Setting up a new test

1. Open up the console in the web browser and login
2. Click "New Item"
3. Enter in name of an existing test to copy from in box labeled "Copy from". The test called "DefaultCheckProfile" is a simple one to copy from.
4. Also enter in a name for the new test
5. Click "OK"
6. Modify the path of the ini file the test is pointing to (in "Execute shell" box), and the XML file that MTT is reporting (in "Publish JUnit test result report" fields)
7. Click "Save"
8. The test can now be run on the main page of Jenkins by pressing the green-arrow-clock button by the test name
9. For the test to run successfully, MTT must be installed on the slave node.

##### Jenkins Logs
To view the jenkins logs from the running container
```
docker logs mttconsole
```

To tail the jenkins logs
```
docker logs -f mttconsole
```

##### To tear it all down
```
docker stop mttconsole
docker rm mttconsole
docker volume rm mttconsole
```
