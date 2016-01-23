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
from TestBuildMTTStage import *

class DefaultTestBuild(TestBuildMTTStage):

    def __init__(self):
        # initialise parent class
        TestBuildMTTStage.__init__(self)
        self.options = {}
        self.options['middleware'] = (None, "Middleware stage that these tests are to be built against")

    def activate(self):
        # get the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "DefaultTestBuild"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print prefix + line
        return

    def execute(self, log, keyvals, testDef):
        # if this test requires middleware, the user
        # should have told us so by specifying the
        # corresponding middlewareBuild stage for it.
        # this will allow us to set the path and/or
        # obtain a list of modules that need to be
        # activated
        midpath = False
        try:
            if keyvals['middleware'] is not None:
                # pass it down
                log['middleware'] = keyvals['middleware']
                # get the log entry of its location
                midlog = testDef.logger.getLog(keyvals['middleware'])
                if midlog is not None:
                    # get the location of the middleware
                    try:
                        if midlog['location'] is not None:
                            # prepend that location to our paths
                            path = os.environ['PATH']
                            pieces = path.split(':')
                            bindir = os.path.join(midlog['location'], "bin")
                            pieces.insert(0, bindir)
                            newpath = ":".join(pieces)
                            os.environ['PATH'] = newpath
                            # prepend the libdir path as well
                            path = os.environ['LD_LIBRARY_PATH']
                            pieces = path.split(':')
                            bindir = os.path.join(midlog['location'], "lib")
                            pieces.insert(0, bindir)
                            newpath = ":".join(pieces)
                            os.environ['LD_LIBRARY_PATH'] = newpath
                    except KeyError:
                        pass
                    # check for modules required by the middleware
                    try:
                        if midlog['parameters'] is not None:
                            for md in midlog['parameters']:
                                if "modules" == md[0]:
                                    try:
                                        if keyvals['modules'] is not None:
                                            # append these modules to those
                                            mods = md[1].split(',')
                                            newmods = modules.split(',')
                                            for md in newmods:
                                                mods.append(md)
                                            keyvals['modules'] = ','.join(mods)
                                    except KeyError:
                                        keyvals['modules'] = md[1]
                                    break
                    except KeyError:
                        pass
        except KeyError:
            pass
        # use the Autotools plugin to execute the build
        plugin = None
        for pluginInfo in testDef.tools.getPluginsOfCategory("Build"):
            if "Autotools" == pluginInfo.plugin_object.print_name():
                plugin = pluginInfo.plugin_object
                break
        if plugin is None:
            log['status'] = 1
            log['stderr'] = "Autotools plugin not found"
            return
        plugin.execute(log, keyvals, testDef)
        # if we added middleware to the paths, remove it
        if midpath:
            pass
