<?php
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

# Enable/disable extra debug output
# NOTE - Enabling this disables proper HTTP error code reporting.
#        As a result, MTT will not handle errors correctly.
define("MTT_DEBUG", 0);

# Site-specific environment configuration.
# Each key in the array is set to its value in the environment.
$mtt_pb_config = array(
        "LOCAL" => '/u/afriedle/local',
        "PATH" => '$LOCAL/bin:/opt/python-2.4/bin:$PATH',
        "PYTHONPATH" => '$LOCAL/lib/python:$LOCAL/lib/python2.4:$LOCAL/lib/python2.4/site-packages',
        "PB_DBUSER" => "postgres",
        "PB_DBPASSWD" => "set password here"
        );

?>
