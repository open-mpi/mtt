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
        self.options['build_in_place'] = (True, "Build tests in current location (no prefix or install)")
        self.options['merge_stdout_stderr'] = (False, "Merge stdout and stderr into one output stream")
        self.options['stdout_save_lines'] = (None, "Number of lines of stdout to save")
        self.options['stderr_save_lines'] = (None, "Number of lines of stderr to save")
        self.options['autogen_cmd'] = (None, "Command to be executed to setup the configure script, usually called autogen.sh or autogen.pl")
        self.options['configure_options'] = (None, "Options to be passed to configure. Note that the prefix will be automatically set and need not be provided here")
        self.options['make_options'] = (None, "Options to be passed to the make command")
        self.options['save_stdout_on_success'] = (False, "Save stdout even if build succeeds")

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
        testDef.logger.verbose_print("DefaultTestBuild")
        # parse any provided options - these will override the defaults
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        # add our section header back into the cmds as it will
        # be needed by autotools
        cmds['section'] = keyvals['section']
        # if this test requires middleware, the user
        # should have told us so by specifying the
        # corresponding middlewareBuild stage for it.
        # this will allow us to set the path and/or
        # obtain a list of modules that need to be
        # activated
        midpath = False
        try:
            if cmds['middleware'] is not None:
                # pass it down
                log['middleware'] = cmds['middleware']
                # get the log entry of its location
                midlog = testDef.logger.getLog(cmds['middleware'])
                if midlog is not None:
                    # get the location of the middleware
                    try:
                        if midlog['location'] is not None:
                            # prepend that location to our paths
                            try:
                                oldbinpath = os.environ['PATH']
                                pieces = oldbinpath.split(':')
                            except KeyError:
                                oldbinpath = ""
                                pieces = []
                            bindir = os.path.join(midlog['location'], "bin")
                            pieces.insert(0, bindir)
                            newpath = ":".join(pieces)
                            os.environ['PATH'] = newpath
                            # prepend the libdir path as well
                            try:
                                oldlibpath = os.environ['LD_LIBRARY_PATH']
                                pieces = oldlibpath.split(':')
                            except KeyError:
                                oldlibpath = ""
                                pieces = []
                            bindir = os.path.join(midlog['location'], "lib")
                            pieces.insert(0, bindir)
                            newpath = ":".join(pieces)
                            os.environ['LD_LIBRARY_PATH'] = newpath
                            # mark that this was done
                            midpath = True
                    except KeyError:
                        pass
                    # check for modules required by the middleware
                    try:
                        if midlog['parameters'] is not None:
                            for md in midlog['parameters']:
                                if "modules" == md[0]:
                                    try:
                                        if cmds['modules'] is not None:
                                            # append these modules to those
                                            mods = md[1].split(',')
                                            newmods = modules.split(',')
                                            for md in newmods:
                                                mods.append(md)
                                            cmds['modules'] = ','.join(mods)
                                    except KeyError:
                                        cmds['modules'] = md[1]
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
        plugin.execute(log, cmds, testDef)
        # if we added middleware to the paths, remove it
        if midpath:
            os.environ['PATH'] = oldbinpath
            os.environ['LD_LIBRARY_PATH'] = oldlibpath
        return
