#!/bin/sh
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

export LOCAL=/u/afriedle/local
export PB_DBUSER="postgres"
export PB_DBPASSWD="3o4m5p6i"
export PATH=/u/afriedle/pb-bin:/opt/python-2.4/bin:$PATH
export PYTHONPATH=$LOCAL/lib/python:/u/afriedle/local/lib/python2.4:/u/afriedle/local/lib/python2.4/site-packages

env
echo

perfbase input -u -d $1 $2 2>&1

