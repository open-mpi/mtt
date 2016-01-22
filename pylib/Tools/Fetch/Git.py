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
from urlparse import urlparse
from FetchMTTTool import *
from distutils.spawn import find_executable

class Git(FetchMTTTool):

    def __init__(self):
        # initialise parent class
        FetchMTTTool.__init__(self)
        self.activated = False
        # track the repos we have processed so we
        # don't do them multiple times
        self.done = {}
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
        return "Git"

    def print_options(self, testDef, prefix):
        print prefix + "None"
        return

    def execute(self, log, keyvals, testDef):
        # check that they gave us a URL
        try:
            if keyvals['url'] is not None:
                url = keyvals['url']
        except KeyError:
            log['status'] = 1
            log['stderr'] = "No repository URL was provided"
            return
        # the path component of the parser output contains
        # the name of the repo
        repo = os.path.basename(urlparse(url).path)
        # check to see if we have already processed this repo
        try:
            if self.done[repo] is not None:
                log['status'] = self.done[repo][0]
                log['location'] = self.done[repo][1]
                return
        except KeyError:
            pass
        # check to see if they specified a module to use
        # where git can be found
        usedModule = False
        try:
            if keyvals['modules'] is not None:
                status,stdout,stderr = testDef.modcmd.loadModules(log, keyvals['modules'], testDef)
                if 0 != status:
                    log['status'] = status
                    log['stderr'] = stderr
                    return
                usedModule = True
        except KeyError:
            pass
        # now look for the executable in our path
        if not find_executable("git"):
            log['status'] = 1
            log['stderr'] = "Executable git not found"
            if usedModule:
                # unload the modules before returning
                testDef.modcmd.unloadModules(log, keyvals['modules'], testDef)
            return
        # see if they asked for a specific branch
        branch = None
        try:
            if keyvals['branch'] is not None:
                branch = keyvals['branch']
        except KeyError:
            pass
        # or if they asked for a specific PR
        pr = None
        try:
            if keyvals['pr'] is not None:
                pr = keyvals['pr']
        except KeyError:
            pass
        # see if we have already serviced this one
        for rep in self.done:
            if rep[0] == repo:
                # log the status from that attempt
                log['status'] = rep[1]
                if 0 != rep[1]:
                    log['stderr'] = "Prior attempt to clone or update repo {0} failed".format(repo)
                if usedModule:
                    # unload the modules before returning
                    testDef.modcmd.unloadModules(log, keyvals['modules'], testDef)
                return
        # record our current location
        cwd = os.getcwd()
        # change to the scratch directory
        os.chdir(testDef.options.scratchdir)
        # see if this software has already been cloned
        if os.path.exists(repo):
            if not os.path.isdir(repo):
                log['status'] = 1
                log['stderr'] = "Cannot update or clone repository {0} as a file of that name already exists".format(repo)
                # track that we serviced this one
                self.done.append((repo, 1))
                if usedModule:
                    # unload the modules before returning
                    testDef.modcmd.unloadModules(log, keyvals['modules'], testDef)
                return
            # since it already exists, let's just update it
            os.chdir(repo)
            status, stdout, stderr = testDef.execmd.execute(["git", "pull"], testDef)
        else:
            # clone it
            status, stdout, stderr = testDef.execmd.execute(["git", "clone", url], testDef)
            # move into it
            os.chdir(repo)
        # record the result
        log['status'] = status
        log['stdout'] = stdout
        log['stderr'] = stderr
        # log our absolute location so others can find it
        log['location'] = os.getcwd()
        # if they indicated that a specific subdirectory was
        # the target, then modify the location accordingly
        try:
            if keyvals['subdir'] is not None:
                log['location'] = os.path.join(log['location'], keyvals['subdir'])
        except KeyError:
            pass
        # track that we serviced this one
        self.done[repo] = (status, log['location'])
        # change back to the original directory
        os.chdir(cwd)
        if usedModule:
            # unload the modules before returning
            testDef.modcmd.unloadModules(log, keyvals['modules'], testDef)
        return
