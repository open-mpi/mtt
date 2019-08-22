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

## @addtogroup Tools
# @{
# @addtogroup Fetch
# @section FetchTarball
# Plugin for fetching and unpacking tarballs from the Web
# @param url    URL for the tarball
# @param cmd    Command line to use to fetch the tarball (e.g., "curl -o")
# @param subdir      Subdirectory of interest in package
# @}
class FetchTarball(FetchMTTTool):

    def __init__(self):
        # initialise parent class
        FetchMTTTool.__init__(self)
        self.activated = False
        # track the repos we have processed so we
        # don't do them multiple times
        self.done = {}
        self.options = {}
        self.options['url'] = (None, "URL to tarball")
        self.options['cmd'] = ("wget", "Command to use to fetch the tarball")
        self.options['subdir'] = (None, "Subdirectory of interest in package")
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
        return "FetchTarball"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("FetchTarball Execute")
        # parse any provided options - these will override the defaults
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        # check that they gave us a URL
        try:
            if cmds['url'] is not None:
                url = cmds['url']
        except KeyError:
            log['status'] = 1
            log['stderr'] = "No URL was provided"
            return
        testDef.logger.verbose_print("Download url " + url)
        # the path component of the parser output contains
        # the name of the tarball
        tarball = os.path.basename(urlparse(url).path)
        # the name of the package being installed is the
        # tarball name minus the .tar.xxx extension
        package = tarball.split(".tar",1)[0]
        # check to see if we have already processed this tarball
        try:
            if self.done[tarball] is not None:
                log['status'] = self.done[repo][0]
                log['location'] = self.done[repo][1]
                # if they specified a subdirectory of interest,
                # check to see if it exists
                if cmds['subdir'] is not None:
                    # check that this subdirectory actually exists
                    ckdir = os.path.join(log['location'], cmds['subdir'])
                    if not os.path.exists(ckdir):
                        log['status'] = 1
                        log['stderr'] = "Subdirectory " + cmds['subdir'] + " was not found"
                        return
                    if not os.path.isdir(ckdir):
                        log['status'] = 1
                        log['stderr'] = "Subdirectory " + cmds['subdir'] + " is not a directory"
                        return
                    # adjust the location so later stages can find it
                    log['location'] = ckdir
                return
        except KeyError:
            pass

        # if this is a path to a local file, then we use
        # the "cp" command instead of "wget"
        checkurl = url[:4]
        if checkurl.lower() == "file":
            cmds['cmd'] = "cp"
            url = urlparse(url).path
            file = True
        else:
            file = False

        # look for the executable in our path - this is
        # a standard system executable so we don't use
        # environmental modules here
        fetchcmd = cmds['cmd'].split()
        if not find_executable(fetchcmd[0]):
            log['status'] = 1
            log['stderr'] = "Executable " + fetchcmd[0] + " not found"
            return
        if not find_executable("tar"):
            log['status'] = 1
            log['stderr'] = "Executable tar not found"
            return

        # record our current location
        cwd = os.getcwd()
        # ensure the scratchdir exists
        dst = os.path.join(testDef.options['scratchdir'], log['section'].replace(":","_"))
        try:
            if not os.path.exists(dst): os.mkdir(dst)
        except:
            log['status'] = 1
            log['stderr'] = "Unable to create " + dst
            return

        # change to the scratch directory
        os.chdir(dst)
        results = {}
        # see if this software has already been fetched
        if os.path.exists(tarball):
            # was it expanded?
            if os.path.exists(package):
                # if they want us to leave it as-is, then we are done
                try:
                    if cmds['asis']:
                        results['status'] = 0
                        results['stdout'] = None
                        results['stderr'] = None
                # If not as-is clear directory and download the tarball
                except KeyError:
                    shutil.rmtree(package)
                    # untar the tarball
                    testDef.logger.verbose_print("untarring tarball " + tarball)
                    results = testDef.execmd.execute(None, ["tar", "-xf", tarball], testDef)
                    if 0 != results['status']:
                        log['status'] = 1
                        log['stderr'] = "untar of tarball " + tarball + "FAILED"
                        return
            else:
                # untar the tarball
                testDef.logger.verbose_print("untarring tarball " + tarball)
                results = testDef.execmd.execute(None, ["tar", "-xf", tarball], testDef)
                if 0 != results['status']:
                    log['status'] = 1
                    log['stderr'] = "untar of tarball " + tarball + "FAILED"
                    return
        else:
            if file:
                testDef.logger.verbose_print("copying tarball " + tarball + " using path: " + url)
                excmd = []
                for p in fetchcmd:
                    excmd.append(p)
                excmd.append(url)
                # give it the destination
                excmd.append(dst)
            else:
                # download the tarball - TODO probably need to do a try on these
                testDef.logger.verbose_print("downloading tarball " + tarball + " using url: " + url)
                excmd = []
                for p in fetchcmd:
                    excmd.append(p)
                excmd.append(url)
            results = testDef.execmd.execute(None, excmd, testDef)
            if 0 != results['status']:
                log['status'] = 1
                log['stderr'] = "download for tarball " + tarball + " url: " + url + "FAILED"
                return
            # untar the tarball
            testDef.logger.verbose_print("untarring tarball " + tarball)
            results = testDef.execmd.execute(None, ["tar", "-xf", tarball], testDef)
            if 0 != results['status']:
                log['status'] = 1
                log['stderr'] = "untar of tarball " + tarball + "FAILED"
                return
        # move into the resulting directory
        os.chdir(package)
        # record the result
        log['status'] = results['status']
        log['stdout'] = results['stdout']
        log['stderr'] = results['stderr']

        # log our absolute location so others can find it
        log['location'] = os.getcwd()
        # track that we serviced this one
        self.done[tarball] = (results['status'], log['location'])

        # if they specified a subdirectory of interest,
        # check to see if it exists
        if cmds['subdir'] is not None:
            # check that this subdirectory actually exists
            ckdir = os.path.join(log['location'], cmds['subdir'])
            if not os.path.exists(ckdir):
                log['status'] = 1
                log['stderr'] = "Subdirectory " + cmds['subdir'] + " was not found"
                return
            if not os.path.isdir(ckdir):
                log['status'] = 1
                log['stderr'] = "Subdirectory " + cmds['subdir'] + " is not a directory"
                return
            # adjust our location so later stages can find it
            log['location'] = ckdir

        testDef.logger.verbose_print("setting location to " + log['location'])
        # change back to the original directory
        os.chdir(cwd)

        return
