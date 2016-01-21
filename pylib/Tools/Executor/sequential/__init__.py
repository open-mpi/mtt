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
import sys
import ConfigParser
import importlib
import logging
import imp
import datetime
from yapsy.PluginManager import PluginManager

from ExecutorMTTTool import *

# Theory of Operation
#
# The sequential executor executes a single, ordered pass thru the
# provided test description. By ordered we mean that execution starts
# with the first provided step and continues until it reaches the end.
# Thus, the user is responsible for ensuring that the order of execution
# is correct.
#
class SequentialEx(ExecutorMTTTool):

    def __init__(self):
        # initialise parent class
        ExecutorMTTTool.__init__(self)


    def activate(self):
        # use the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "Sequential executor"

    def execute(self, testDef):
        for title in testDef.config.sections():
            print title
            if "MTTDefaults" == title.strip():  # handled this in the TestDef
                continue
            if "STOP" == title.strip():
                return
            # extract the stage and stage name from the title
            stage,name = title.split(':')
            stage = stage.strip()
            # get the list of key-value tuples provided in this stage
            # by the user and convert it to a dictionary for easier parsing
            # Yes, we could do this automatically, but we instead do it
            # manually so we can strip all the keys and values for easier
            # parsing later
            keyvals = {'section':title.strip()}
            for kv in testDef.config.items(title):
                keyvals[kv[0].strip()] = kv[1].strip()
            # extract the name of the plugin to use
            try:
                module = keyvals['plugin']
                # see if this plugin exists
                plugin = None
                for pluginInfo in testDef.stages.getPluginsOfCategory(stage):
                    if module == pluginInfo.plugin_object.print_name():
                        plugin = pluginInfo.plugin_object
                        break
                if plugin is None:
                    # this plugin doesn't exist, or it may not be a stage as
                    # sometimes a stage consists of executing a tool.
                    # so let's check the tools too, noting that those
                    # are not stage-specific.
                    availTools = testDef.loader.tools.keys()
                    for tool in availTools:
                        for pluginInfo in testDef.tools.getPluginsOfCategory(tool):
                            if module == pluginInfo.plugin_object.print_name():
                                plugin = pluginInfo.plugin_object
                                break
                        if plugin is not None:
                            break;
                    if plugin is None:
                        print "Specified plugin",module,"does not exist in stage",stage,"or in the available tools"
                        return
                    else:
                        # activate the specified plugin
                        testDef.tools.activatePluginByName(module, tool)
                else:
                    # activate the specified plugin
                    testDef.stages.activatePluginByName(module, stage)
            except KeyError:
                # if they didn't specify a plugin, use the default if one
                # is available and so designated
                default = "Default{0}".format(stage)
                for pluginInfo in testDef.stages.getPluginsOfCategory(stage):
                    if default == pluginInfo.plugin_object.print_name():
                        plugin = pluginInfo.plugin_object
                        break
                if plugin is None:
                    # we really have to way of executing this
                    print "Plugin",module,"for stage",stage,"was not specified, and no default is available"
                    stageLog = {'stage':title}
                    stageLog["parameters"] = testDef.config.items(title)
                    stageLog['status'] = 1
                    return

            # execute the provided test description and capture the result
            stageLog = {'stage':title}
            stageLog["parameters"] = testDef.config.items(title)
            plugin.execute(stageLog, keyvals, testDef)
            testDef.logger.logResults(title, stageLog)
            # if this step failed, then we don't want to continue
            try:
                if 0 != stageLog['status']:
                    # it failed
                    print "Stage ",stage," failed with status ",str(stageLog['status'])
                    return
            except KeyError:
                print "Stage ",stage," plugin ",module," failed to return a status"
                return
        return
