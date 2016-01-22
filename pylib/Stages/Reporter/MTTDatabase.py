# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#


from ReporterMTTStage import *

class MTTDatabase(ReporterMTTStage):

    def __init__(self):
        # initialise parent class
        ReporterMTTStage.__init__(self)
        self.options = {}
        self.options['realm'] = (None, "Database name")
        self.options['username'] = (None, "Username to be used for submitting data")
        self.options['password'] = (None, "Password for that username")
        self.options['platform'] = (None, "Name of the platform (cluster) upon which the tests were run")
        self.options['hostname'] = (None, "Name of the hosts involved in the tests (may be regular expression)")
        self.options['url'] = (None, "URL of the database server")
        self.options['debug_filename'] = (None, "Debug output file for server interaction information")
        self.options['keep_debug_files'] = (False, "Retain reporter debug output after execution")
        self.options['debug_server'] = (False, "Ask the server to return its debug output as well")


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
        # needs to be implemented
        log['status'] = 0
        return
