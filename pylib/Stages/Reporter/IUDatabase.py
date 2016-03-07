# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import os
import requests
from requests.auth import HTTPBasicAuth

from ReporterMTTStage import *

class IUDatabase(ReporterMTTStage):

    def __init__(self):
        # initialise parent class
        ReporterMTTStage.__init__(self)
        self.options = {}
        self.options['realm'] = (None, "Database name")
        self.options['username'] = (None, "Username to be used for submitting data")
        self.options['password'] = (None, "Password for that username")
        self.options['pwfile'] = (None, "File where password can be found")
        self.options['platform'] = (None, "Name of the platform (cluster) upon which the tests were run")
        self.options['hostname'] = (None, "Name of the hosts involved in the tests (may be regular expression)")
        self.options['url'] = (None, "URL of the database server")
        self.options['debug_filename'] = (None, "Debug output file for server interaction information")
        self.options['keep_debug_files'] = (False, "Retain reporter debug output after execution")
        self.options['debug_server'] = (False, "Ask the server to return its debug output as well")
        self.options['email'] = (None, "Email to which errors are to be sent")

    def activate(self):
        # get the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "MTTDatabase"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print prefix + line
        return

    def execute(self, log, keyvals, testDef):
        # parse the provided keyvals against our options
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        # quick sanity check
        sanity = 0
        if cmds['username'] is not None:
            sanity += 1
        if cmds['password'] is not None or cmds['pwfile'] is not None:
            sanity += 1
        if cmds['realm'] is not None:
            sanity += 1
        if 0 < sanity and sanity != 3:
            log['status'] = 1
            log['stderr'] = "MTTDatabase Reporter section",log['section'] + ": if password, username, or realm is specified, they all must be specified."
            return
        try:
            if cmds['pwfile'] is not None:
                if os.path.exists(cmds['pwfile']):
                    f = open(cmds['pwfile'], 'r')
                    password = f.readline().strip()
                    f.close()
                else:
                    log['status'] = 1;
                    log['stderr'] = "Password file " + cmds['pwfile'] + " does not exist"
                    return
        except KeyError:
            try:
                if cmds['password'] is not None:
                    password = cmds['password']
            except KeyError:
                pass
        # establish the sessoin
        s = requests.Session()
        headers = {}
        headers['content-type'] = 'application/x-www-form-urlencoded'

        payload = {"mtt_version_major" : "4", "mtt_version_minor" : "0", "mtt_client_version" : "4.0a1"}
        if 0 < sanity:
            r = s.post(cmds['url'], data=payload, headers=headers, auth=HTTPBasicAuth(cmds['username'], password), verify=False)
        else:
            r = s.post("https://mtt.open-mpi.org/submit/", data=payload, headers=headers, verify=False)
        print "<<<<<<<---------------- Response -------------------------->>>>>>"
        print "Result: %d: %s" % (r.status_code, r.headers['content-type'])
        print r.headers
        print r.reason
        print "<<<<<<<---------------- Raw Output (Start) ---------------->>>>>>"
        print r.text
        print "<<<<<<<---------------- Raw Output (End  ) ---------------->>>>>>"
        log['status'] = 0
        return
