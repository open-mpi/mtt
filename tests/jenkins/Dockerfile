FROM jenkins:2.32.1
MAINTAINER Richard Barella <richard.t.barella@intel.com>
# Dockerfile is built using Anton Fisher's as a template: https://antonfisher.com/posts/2017/01/16/run-jenkins-in-docker-container-with-persistent-configuration/

ARG proxy_server
ARG proxy_port
ARG slave_node_name
ARG slave_node_num_computes
ARG slave_node_ip_addr
ARG slave_node_num_executors
ARG slave_node_ssh_username
ARG slave_node_exec_dir
ARG master_num_executors
ARG compute_node_names

ENV JAVA_OPTS "-Dhttp.proxyHost=${proxy_server} -Dhttp.proxyPort=${proxy_port} -Dhttps.proxyHost=${proxy_server} -Dhttps.proxyPort=${proxy_port} -Djenkins.install.runSetupWizard=false"

ENV http_proxy  http://$proxy_server:$proxy_port/
ENV FTP_PROXY   http://$proxy_server:$proxy_port/
ENV ftp_proxy   http://$proxy_server:$proxy_port/
ENV HTTPS_PROXY https://$proxy_server:$proxy_port/
ENV https_proxy https://$proxy_server:$proxy_port/
ENV no_proxy    localhost
ENV HTTP_PROXY  http://$proxy_server:$proxy_port/
ENV TIMEZONE "America/Los_Angeles"
ENV JENKINS_HOME /home/jenkins

USER root
RUN apt-get update && apt-get install -y vim tree

# Set timezone
RUN echo $TIMEZONE > /etc/timezone &&\
    dpkg-reconfigure --frontend noninteractive tzdata &&\
    date

# Create jenkins directory
RUN mkdir -p $JENKINS_HOME &&\
    chown -R jenkins:jenkins $JENKINS_HOME

# Install jenkins plugins
RUN /usr/local/bin/install-plugins.sh ant:1.4 antisamy-markup-formatter:1.5 bouncycastle-api:2.16.0 branch-api:1.11.1 build-flow-plugin:0.20 build-user-vars-plugin:1.5 cloudbees-folder:5.14 conditional-buildstep:1.3.5 credentials:2.1.10 cvs:2.12 display-url-api:0.5 durable-task:1.12 email-ext:2.52 envinject:1.93.1 extended-read-permission:2.0 external-monitor-job:1.6 externalresource-dispatcher:1.1.0 git-client:2.1.0 git-server:1.7 git:3.0.1 github-api:1.80 github-branch-source:1.10.1 github:1.25.0 greenballs:1.15 handlebars:1.1.1 icon-shim:2.0.3 javadoc:1.4 job-import-plugin:1.6 jobConfigHistory:2.15 jquery-detached:1.2.1 junit:1.19 ldap:1.13 lockable-resources:1.10 mailer:1.18 mapdb-api:1.0.9.0 matrix-auth:1.4 matrix-project:1.7.1 maven-plugin:2.14 metadata:1.1.0b momentjs:1.1.1 multiple-scms:0.6 pam-auth:1.3 parameterized-trigger:2.32 build-timeout:1.18 plain-credentials:1.3 plugin-usage-plugin:0.3 role-strategy:2.3.2 run-condition:1.0 scm-api:1.3 script-security:1.24 ssh-credentials:1.12 ssh-slaves:1.12 structs:1.5 subversion:2.7.1 tap:2.0.1 test-results-analyzer:0.3.4 token-macro:2.0 translation:1.15 view-job-filters:1.27 windows-slaves:1.2 jenkins-multijob-plugin:1.23

############################################
# Jobs configuration step
COPY --chown=jenkins:jenkins jobs $JENKINS_HOME/jobs
RUN perl -pi -e 's/SLAVE_NODE_NAME_VAR/${slave_node_name}/g' $JENKINS_HOME/jobs/*/config.xml &&\
    perl -pi -e 's/COMPUTE_NODE_NAMES_VAR/${compute_node_names}/g' $JENKINS_HOME/jobs/*/config.xml &&\
    perl -pi -e 's/SLAVE_NODE_NUM_COMPUTES_VAR/${slave_node_num_computes}/g' $JENKINS_HOME/jobs/*/config.xml &&\
    perl -pi -e 's/SLAVE_NODE_EXEC_DIR_VAR/${slave_node_exec_dir}/g' $JENKINS_HOME/jobs/*/config.xml

# Users configuration step
COPY --chown=jenkins:jenkins users $JENKINS_HOME/users

# Nodes configuration step
COPY --chown=jenkins:jenkins nodes/SLAVE_NODE_NAME_VAR $JENKINS_HOME/nodes/SLAVE_NODE_NAME_VAR
RUN perl -pi -e "s/SLAVE_NODE_NAME_VAR/$slave_node_name/g" $JENKINS_HOME/nodes/$slave_node_name/config.xml &&\
    perl -pi -e "s/SLAVE_NODE_NUM_EXECUTORS_VAR/$slave_node_num_executors/g" $JENKINS_HOME/nodes/$slave_node_name/config.xml &&\
    perl -pi -e "s/SLAVE_NODE_IP_ADDR_VAR/$slave_node_ip_addr/g" $JENKINS_HOME/nodes/$slave_node_name/config.xml &&\
    perl -pi -e "s/SLAVE_NODE_NUM_COMPUTES_VAR/$slave_node_num_computes/g" $JENKINS_HOME/nodes/$slave_node_name/config.xml &&\
    perl -pi -e "s/SLAVE_NODE_EXEC_DIR_VAR/${slave_node_exec_dir}/g" $JENKINS_HOME/nodes/$slave_node_name/config.xml &&\
    chown -R jenkins:jenkins $JENKINS_HOME
# $slave_node_name

# Lockable resources configuration step
COPY --chown=jenkins:jenkins org.jenkins.plugins.lockableresources.LockableResourcesManager.xml $JENKINS_HOME/.lkbl.tmp.xml
RUN head -n 3 $JENKINS_HOME/.lkbl.tmp.xml > $JENKINS_HOME/org.jenkins.plugins.lockableresources.LockableResourcesManager.xml &&\
    for compute_node_name in $compute_node_names; do echo "<org.jenkins.plugins.lockableresources.LockableResource><name>$compute_node_name</name><description>$slave_node_name $compute_node_name</description><labels>$compute_node_name</labels><queueItemId>0</queueItemId><queuingStarted>0</queuingStarted><queuedContexts/></org.jenkins.plugins.lockableresources.LockableResource>" >> $JENKINS_HOME/org.jenkins.plugins.lockableresources.LockableResourcesManager.xml; done &&\
    tail -n 2 $JENKINS_HOME/.lkbl.tmp.xml >> $JENKINS_HOME/org.jenkins.plugins.lockableresources.LockableResourcesManager.xml &&\
    rm $JENKINS_HOME/.lkbl.tmp.xml &&\
    chown -R jenkins:jenkins $JENKINS_HOME/org.jenkins.plugins.lockableresources.LockableResourcesManager.xml

# Credentials configuration step
COPY --chown=jenkins:jenkins credentials.xml $JENKINS_HOME/credentials.xml
RUN perl -pi -e "s/SLAVE_NODE_NAME_VAR/$slave_node_name/g" $JENKINS_HOME/credentials.xml &&\
    perl -pi -e "s/SLAVE_NODE_SSH_USERNAME_VAR/$slave_node_ssh_username/g" $JENKINS_HOME/credentials.xml

# config.xml configuration step
COPY --chown=jenkins:jenkins config.xml $JENKINS_HOME/config.xml
RUN perl -pi -e "s/MASTER_NUM_EXECUTORS_VAR/$master_num_executors/g" $JENKINS_HOME/config.xml

# Jenkins workspace for sharing between containers
VOLUME $JENKINS_HOME

############################################
USER jenkins

# Start jenkins
ENTRYPOINT ["/usr/local/bin/jenkins.sh"]
