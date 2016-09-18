# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
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

class Git(FetchMTTTool):

    def __init__(self):
        # initialise parent class
        FetchMTTTool.__init__(self)
        self.activated = False
        # track the repos we have processed so we
        # don't do them multiple times
        self.done = {}
        self.options = {}
        self.options['module'] = (None, "Modules (or lmod modules) to be loaded for accessing this package")
        self.options['url'] = (None, "URL to access the repository")
        self.options['username'] = (None, "Username required for accessing the repository")
        self.options['password'] = (None, "Password required for that user to access the repository")
        self.options['pwfile'] = (None, "File where password can be found")
        self.options['branch'] = (None, "Branch (if not master) to be downloaded")
        self.options['pr'] = (None, "Pull request to be downloaded")
        self.options['subdir'] = (None, "Subdirectory of interest in repository")
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
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("Git Execute")
        # parse any provided options - these will override the defaults
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        # check that they gave us a URL
        try:
            if cmds['url'] is not None:
                url = cmds['url']
        except KeyError:
            log['status'] = 1
            log['stderr'] = "No repository URL was provided"
            return
        testDef.logger.verbose_print("Working repo " + url)
        username = cmds['username']
        password = None
        # see if they gave us a password
        try:
            if cmds['password'] is not None:
                password = cmds['password']
            else:
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
                    pass
        except KeyError:
            # if not, did they give us a file where we can find the password
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
                pass
        # check for sanity - if a password was given, then
        # we must have a username
        if password is not None:
            if username is None:
                log['status'] = 1;
                log['stderr'] = "Password without username"
                return
            # find the "//"
            (leader,tail) = url.split("//", 1)
            # put the username:password into the url
            url = leader + "//" + username + ":" + password + "@" + tail
        elif username is not None:
            # find the "//"
            (leader,tail) = url.split("//", 1)
            # put the username:password into the url
            url = leader + "//" + username + "@" + tail
        testDef.logger.verbose_print("Working final repo " + url)
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
            if cmds['modules'] is not None:
                status,stdout,stderr = testDef.modcmd.loadModules(cmds['modules'], testDef)
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
                status,stdout,stderr = testDef.modcmd.unloadModules(cmds['modules'], testDef)
                if 0 != status:
                    log['status'] = status
                    log['stderr'] = stderr
                    return
            return
        # see if they asked for a specific branch
        branch = None
        try:
            if cmds['branch'] is not None:
                branch = cmds['branch']
        except KeyError:
            pass
        # or if they asked for a specific PR
        pr = None
        try:
            if cmds['pr'] is not None:
                pr = cmds['pr']
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
                    status,stdout,stderr = testDef.modcmd.unloadModules(cmds['modules'], testDef)
                    if 0 != status:
                        log['status'] = status
                        log['stderr'] = stderr
                        return
                return
        # record our current location
        cwd = os.getcwd()
        # change to the scratch directory
        os.chdir(testDef.options['scratchdir'])
        # see if this software has already been cloned
        if os.path.exists(repo):
            if not os.path.isdir(repo):
                log['status'] = 1
                log['stderr'] = "Cannot update or clone repository {0} as a file of that name already exists".format(repo)
                # track that we serviced this one
                self.done.append((repo, 1))
                if usedModule:
                    # unload the modules before returning
                    status,stdout,stderr = testDef.modcmd.unloadModules(keyvals['modules'], testDef)
                    if 0 != status:
                        log['status'] = status
                        log['stderr'] = stderr
                        return
                return
            # move to that location
            os.chdir(repo)
            # if they want us to leave it as-is, then we are done
            try:
                if cmds['asis']:
                    status = 0
                    stdout = None
                    stderr = None
            except KeyError:
                # since it already exists, let's just update it
                status, stdout, stderr = testDef.execmd.execute(cmds, ["git", "pull"], testDef)
        else:
            # clone it
            status, stdout, stderr = testDef.execmd.execute(cmds, ["git", "clone", url], testDef)
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
        print("CMDS",cmds)
        try:
            if cmds['subdir'] is not None:
                log['location'] = os.path.join(log['location'], cmds['subdir'])
        except KeyError:
            pass
        # track that we serviced this one
        self.done[repo] = (status, log['location'])
        # change back to the original directory
        os.chdir(cwd)
        if usedModule:
            # unload the modules before returning
            status,stdout,stderr = testDef.modcmd.unloadModules(cmds['modules'], testDef)
            if 0 != status:
                log['status'] = status
                log['stderr'] = stderr
                return
        return
