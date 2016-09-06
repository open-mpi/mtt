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
import sys
import configparser
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
        self.options = {}


    def activate(self):
        # use the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "Sequential executor"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, testDef):
        testDef.logger.verbose_print("ExecuteSequential")
        for step in testDef.loader.stageOrder:
            for title in testDef.config.sections():
                if step not in title:
                    continue
                # see if this is a step we are to execute
                if title not in testDef.actives:
                    continue
                testDef.logger.verbose_print(title)
                # if they provided the STOP section, that means we
                # are to immediately stop processing the test definition
                # file and return
                if "STOP" in title:
                    return
                # if they included the "SKIP" qualifier, then we skip
                # this section
                if "SKIP" in title:
                    continue
                # extract the stage and stage name from the title
                if ":" in title:
                    stage,name = title.split(':')
                    stage = stage.strip()
                else:
                    stage = title
                # setup the log
                stageLog = {'section':title}
                # get the key-value tuples output by the configuration parser
                stageLog["parameters"] = testDef.config.items(title)
                # convert the list of key-value tuples provided in this stage
                # by the user to a dictionary for easier parsing.
                # Yes, we could do this automatically, but we instead do it
                # manually so we can strip all the keys and values for easier
                # parsing later
                keyvals = {'section':title.strip()}
                for kv in testDef.config.items(title):
                    keyvals[kv[0].strip()] = kv[1].strip()
                # if they included the "ASIS" qualifier, remove it
                # from the stage name
                if "ASIS" in stage:
                    # find the first non-space character
                    i = 4
                    while stage[i].isspace():
                        i = i + 1
                    stage = stage[i:]
                    stageLog['section'] = title[i:].strip()
                    keyvals['section'] = title[i:].strip()
                    keyvals['asis'] = True
                # if this stage has a parent, get the log for that stage
                # and check its status - if it didn't succeed, then we shall
                # log this stage as also having failed and skip it
                try:
                    parent = keyvals['parent']
                    if parent is not None:
                        # get the log entry as it contains the status
                        bldlog = testDef.logger.getLog(parent)
                        if bldlog is None:
                            # couldn't find the parent's log - cannot continue
                            stageLog['status'] = 1
                            stageLog['stderr'] = "Prior dependent step did not record a log"
                            testDef.logger.logResults(title, stageLog)
                            continue
                        try:
                            if bldlog['status'] != 0:
                                # the parent step failed, and so we
                                # cannot proceed here either
                                stageLog['status'] = bldlog['status']
                                stageLog['stderr'] = "Prior dependent step failed - cannot proceed"
                                testDef.logger.logResults(title, stageLog)
                                continue
                        except KeyError:
                            # if it didn't report a status, we shouldn't rely on it
                            stageLog['status'] = 1
                            stageLog['stderr'] = "Prior dependent step failed to provide a status"
                            testDef.logger.logResults(title, stageLog)
                            continue
                except KeyError:
                    pass
                # extract the name of the plugin to use
                plugin = None
                try:
                    module = keyvals['plugin']
                    # see if this plugin exists
                    try:
                        for pluginInfo in testDef.stages.getPluginsOfCategory(stage):
                            if module == pluginInfo.plugin_object.print_name():
                                plugin = pluginInfo.plugin_object
                                break
                        if plugin is None:
                            # this plugin doesn't exist, or it may not be a stage as
                            # sometimes a stage consists of executing a tool or utility.
                            # so let's check the tools too, noting that those
                            # are not stage-specific.
                            availTools = list(testDef.loader.tools.keys())
                            for tool in availTools:
                                for pluginInfo in testDef.tools.getPluginsOfCategory(tool):
                                    if module == pluginInfo.plugin_object.print_name():
                                        plugin = pluginInfo.plugin_object
                                        break
                                if plugin is not None:
                                    break;
                            if plugin is None:
                                # Check the utilities
                                availUtils = list(testDef.loader.utilities.keys())
                                for util in availUtils:
                                    for pluginInfo in testDef.utilities.getPluginsOfCategory(util):
                                        if module == pluginInfo.plugin_object.print_name():
                                            plugin = pluginInfo.plugin_object
                                            break
                                    if plugin is not None:
                                        break;
                            if plugin is None:
                                stageLog['status'] = 1
                                stageLog['stderr'] = "Specified plugin",module,"does not exist in stage",stage,"or in the available tools and utilities"
                                testDef.logger.logResults(title, stageLog)
                                continue
                            else:
                                # activate the specified plugin
                                testDef.tools.activatePluginByName(module, tool)
                        else:
                            # activate the specified plugin
                            testDef.stages.activatePluginByName(module, stage)
                    except KeyError:
                        # If this stage has no plugins then check the tools and the utilities
                        availTools = list(testDef.loader.tools.keys())
                        for tool in availTools:
                            for pluginInfo in testDef.tools.getPluginsOfCategory(tool):
                                if module == pluginInfo.plugin_object.print_name():
                                    plugin = pluginInfo.plugin_object
                                    break
                            if plugin is not None:
                                break;
                        if plugin is None:
                            # Check the utilities
                            availUtils = list(testDef.loader.utilities.keys())
                            for util in availUtils:
                                for pluginInfo in testDef.utilities.getPluginsOfCategory(util):
                                    if module == pluginInfo.plugin_object.print_name():
                                        plugin = pluginInfo.plugin_object
                                        break
                                if plugin is not None:
                                    break;
                        if plugin is None:
                            stageLog['status'] = 1
                            stageLog['stderr'] = "Specified plugin",module,"does not exist in stage",stage,"or in the available tools and utilities"
                            testDef.logger.logResults(title, stageLog)
                            continue
                        else:
                            # activate the specified plugin
                            testDef.tools.activatePluginByName(module, tool)
                except KeyError:
                    # if they didn't specify a plugin, use the default if one
                    # is available and so designated
                    default = "Default{0}".format(stage)
                    for pluginInfo in testDef.stages.getPluginsOfCategory(stage):
                        if default == pluginInfo.plugin_object.print_name():
                            plugin = pluginInfo.plugin_object
                            break
                    if plugin is None:
                        # we really have no way of executing this
                        stageLog['status'] = 1
                        stageLog['stderr'] = "Plugin for stage",stage,"was not specified, and no default is available"
                        testDef.logger.logResults(title, stageLog)
                        continue

                # execute the provided test description and capture the result
                plugin.execute(stageLog, keyvals, testDef)
                testDef.logger.logResults(title, stageLog)
        return
