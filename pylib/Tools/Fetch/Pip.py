# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2019 Intel, Inc.  All rights reserved.
# Copyright (c) 2017-2018 Los Alamos National Security, LLC. All rights
#                         reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
from future import standard_library
standard_library.install_aliases()
import os
from urllib.parse import urlparse
from FetchMTTTool import *
from distutils.spawn import find_executable
import sys
import shutil
import subprocess

## @addtogroup Tools
# @{
# @addtogroup Fetch
# @section Pip
# Plugin for fetching and locally installing pkgs from the Web
# @param pkg        Package to be installed
# @param sudo       Superuser authority required
# @param userloc    Install locally for the user instead of in system locations
# @}
class Pip(FetchMTTTool):

    def __init__(self):
        # initialise parent class
        FetchMTTTool.__init__(self)
        self.activated = False
        # track the repos we have processed so we
        # don't do them multiple times
        self.done = {}
        self.options = {}
        self.options['pkg'] = (None, "Package to be installed")
        self.options['sudo'] = (False, "Superuser authority required")
        self.options['userloc'] = (True, "Install locally for the user instead of in system locations")
        return

    def activate(self):
        if not self.activated:
            # use the automatic procedure from IPlugin
            IPlugin.activate(self)
        return

    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "Pip"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("Pip Execute")
        # parse any provided options - these will override the defaults
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        # check that they gave us an pkg namne
        try:
            if cmds['pkg'] is not None:
                pkg = cmds['pkg']
        except KeyError:
            log['status'] = 1
            log['stderr'] = "No PKG was provided"
            return
        testDef.logger.verbose_print("Install pkg " + pkg)
        # check to see if we have already processed this pkg
        try:
            if self.done[pkg] is not None:
                log['status'] = self.done[pkg]
                log['stdout'] = "PKG " + pkg + " has already been processed"
                return
        except KeyError:
            pass

        # look for the executable in our path - this is
        # a standard system executable so we don't use
        # environmental modules here
        if not find_executable("pip"):
            log['status'] = 1
            log['stderr'] = "Executable pip not found"
            return

        # see if the pkg has already been installed on the system
        testDef.logger.verbose_print("checking system for pkg: " + pkg)
        qcmd = []
        if cmds['sudo']:
            qcmd.append("sudo")
        qcmd.append("pip")
        qcmd.append("show")
        qcmd.append(pkg)
        results = testDef.execmd.execute(None, qcmd, testDef)
        if 0 == results['status']:
            log['status'] = 0
            log['stdout'] = "PKG " + pkg + " already exists on system"
            # Find the location
            for t in results['stdout']:
                if t.startswith("Location"):
                    log['location'] = t[10:]
                    break
            return

        # setup to install
        icmd = []
        if cmds['sudo']:
            icmd.append("sudo")
        icmd.append("pip")
        icmd.append("install")
        if cmds['userloc']:
            icmd.append("--user")
        icmd.append(pkg)
        testDef.logger.verbose_print("installing package " + pkg)
        results = testDef.execmd.execute(None, icmd, testDef)
        if 0 != results['status']:
            log['status'] = 1
            log['stderr'] = "install of " + pkg + " FAILED"
            return

        # record the result
        log['status'] = results['status']
        log['stdout'] = results['stdout']
        log['stderr'] = results['stderr']
        # Find where it went
        results = testDef.execmd.execute(None, qcmd, testDef)
        if 0 == results['status']:
            # Find the location
            for t in results['stdout']:
                if t.startswith("Location"):
                    log['location'] = t[10:]
                    # Add the location to PYTHONPATH
                    pypath = os.environ['PYTHONPATH'] + ":" + log['location']
                    os.environ['PYTHONPATH'] = pypath
                    break

        # track that we serviced this one
        self.done[pkg] = results['status']
        return
