#!/usr/bin/env python
"""
Install and configure the environment for the REST server.

Usage: ./bin/mtt_server_install.py
"""

import os
import shutil
import sys
from subprocess import call


package_name = 'webapp'

source_dir = 'src'
log_dir = 'log'
tmp_dir = 'tmp'

env_dir = source_dir + '/env'

tmpl_htaccess  = ".htaccess.tmpl"
final_htaccess = ".htaccess"

tmpl_conf  = "bin/mtt_server.cfg.tmpl"
final_conf = "bin/mtt_server.cfg"


###################################################
#
# Check if we have already installed
#
if os.path.exists(env_dir):
    print "=" * 70
    print 'Warning: Server appears to be already installed.'
    print "=" * 70

    response = raw_input('(R)emove and re-install or (A)bort? ')
    if response != 'R' and response != 'r':
        sys.exit('Aborted')
    shutil.rmtree(env_dir)
    shutil.rmtree(log_dir, True)

###################################################
#
# Create directory structure
#
print "=" * 70
print "Status: Creating Directory Structure"
print "=" * 70

#
# Create the log directory
#
if not os.path.exists(log_dir):
    os.makedirs(log_dir)


###################################################
#
# Setup the webserver configuration files
#
if os.path.exists(final_conf) is True:
    print "=" * 70
    print 'Warning: Server configuration file present.'
    print "=" * 70

    response = raw_input('(R)eplace or (K)eep? ')
    if response == 'R' or response == 'r':
        call(['rm', final_conf])
        call(['cp', tmpl_conf, final_conf])
else:
    call(['cp', tmpl_conf, final_conf])
call(['chmod', 'og+rX', final_conf])


if os.path.exists(final_htaccess) is True:
    print "=" * 70
    print 'Warning: Server .htaccess file present.'
    print "=" * 70

    response = raw_input('(R)eplace or (K)eep? ')
    if response == 'R' or response == 'r':
        call(['rm', final_htaccess])
        call(['cp', tmpl_htaccess, final_htaccess])
else:
    call(['cp', tmpl_htaccess, final_htaccess])
call(['chmod', 'og+rX', final_htaccess])



###################################################
#
# Setup virtualenv
#
print "=" * 70
print "Status: Setup the virtual environment"
print "        This may take a while..."
print "=" * 70

#
# Setup virtual environment
#
call(['virtualenv', '-p', 'python', env_dir])
call([env_dir + '/bin/pip', 'install', '-r', source_dir + '/mtt_server_requirements.txt'])

# Link Server to virtual environment
# FIXME: This assumes python2.7. Need to find a way with virtualenv/pip to
# enforce this.
cwd = os.getcwd()
call(['cp', '-rs', cwd + '/' + source_dir + '/' + package_name,
      env_dir + '/lib/python/site-packages/' + package_name])

# Use virtual environment to complete server setup
call([env_dir + '/bin/python', source_dir + '/mtt_server_install_stage_two.py'])


###################################################
print "=" * 70
print "Status: Setup Complete"
print "=" * 70

print "==>"
print "==> NOTICE: Please edit the file: " + final_conf
print "==>"

print "==>"
print "==> NOTICE: Please edit the file: " + final_htaccess
print "==>"


sys.exit(0)
