# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2018 Intel, Inc. All rights reserved.
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
import traceback
import configparser
import importlib
import logging
import imp
import datetime
from yapsy.PluginManager import PluginManager

from ExecutorMTTTool import *

try:
    basestring
except:
    basestring = str

# Theory of Operation
#
# The sequential executor executes a single, ordered pass thru the
# provided test description. By ordered we mean that execution starts
# with the first provided step and continues until it reaches the end.
# Thus, the user is responsible for ensuring that the order of execution
# is correct.
#

## @addtogroup Tools
# @{
# @addtogroup Executor
# @section SequentialEx
# Sequential execution executor
# @}
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

    def durationTimeoutHandler(self):
        self.one_last_loop = True


    def execute_sections(self, testDef):
        for step in testDef.loader.stageOrder:
            for title in testDef.config.sections():
                if self.only_reporter and step != "Reporter":
                    continue
                elif self.looping and not self.only_reporter and step == "Reporter":
                    continue
                elif self.looping and self.only_reporter:
                    self.looping = False
                    if step != "Reporter":
                        continue
                try:
                    testDef.plugin_trans_sem.release()
                    if (":" in title and step not in title.split(":")[0]) or \
                       (":" not in title and step not in title):
                        testDef.plugin_trans_sem.acquire()
                        continue
                    # see if this is a step we are to execute
                    if title not in testDef.actives:
                        testDef.plugin_trans_sem.acquire()
                        continue

                    # create display title for section in case loopforever is on
                    title_append = "-loop%d" % (self.loop_count) if self.loopforever else ""
                    disp_title = title + title_append

                    testDef.logger.verbose_print(disp_title)
                    # if they provided the STOP section, that means we
                    # are to immediately stop processing the test definition
                    # file and return
                    if "STOP" in title:
                        return
                    # if they included the "SKIP" qualifier, then we skip
                    # this section
                    if "SKIP" in title:
                        testDef.plugin_trans_sem.acquire()
                        continue
                    # extract the stage and stage name from the title
                    if ":" in title:
                        stage,name = title.split(':')
                        stage = stage.strip()
                    else:
                        stage = title

                    # Refresh test options if not running combinatorial plugin
                    if testDef.options['executor'] != "combinatorial":
                        testDef.configTest()
                        testDef.logger.verbose_print("OPTIONS FOR SECTION: %s" % disp_title)
                        testDef.logger.verbose_print(testDef.config.items(title))

                    # setup the log
                    stageLog = {'section':disp_title}
                    # get the key-value tuples output by the configuration parser
                    stageLog["parameters"] = testDef.config.items(title)
                    # convert the list of key-value tuples provided in this stage
                    # by the user to a dictionary for easier parsing.
                    # Yes, we could do this automatically, but we instead do it
                    # manually so we can strip all the keys and values for easier
                    # parsing later
                    keyvals = {'section':disp_title.strip()}
                    for kv in testDef.config.items(title):
                        keyvals[kv[0].strip()] = kv[1].strip()
                    if 'parent' in keyvals:
                        keyvals['parent'] = keyvals['parent'] + title_append
                    # if they included the "ASIS" qualifier, remove it
                    # from the stage name
                    if "ASIS" in stage:
                        # find the first non-space character
                        i = 4
                        while stage[i].isspace():
                            i = i + 1
                        stage = stage[i:]
                        stageLog['section'] = disp_title[i:].strip()
                        keyvals['section'] = disp_title[i:].strip()
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
                                stageLog['stderr'] = ["Prior dependent step did not record a log"]
                                testDef.logger.logResults(disp_title, stageLog)
                                testDef.plugin_trans_sem.acquire()
                                continue
                            try:
                                if bldlog['status'] != 0:
                                    # the parent step failed, and so we
                                    # cannot proceed here either
                                    stageLog['status'] = bldlog['status']
                                    stageLog['stderr'] = ["Prior dependent step failed - cannot proceed"]
                                    testDef.logger.logResults(disp_title, stageLog)
                                    testDef.plugin_trans_sem.acquire()
                                    continue
                            except KeyError:
                                # if it didn't report a status, we shouldn't rely on it
                                stageLog['status'] = 1
                                stageLog['stderr'] = ["Prior dependent step failed to provide a status"]
                                testDef.logger.logResults(disp_title, stageLog)
                                testDef.plugin_trans_sem.acquire()
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
                                    testDef.logger.logResults(disp_title, stageLog)
                                    testDef.plugin_trans_sem.acquire()
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
                                testDef.logger.logResults(disp_title, stageLog)
                                testDef.plugin_trans_sem.acquire()
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
                            testDef.logger.logResults(disp_title, stageLog)
                            testDef.plugin_trans_sem.acquire()
                            continue

                    # Make sure that the plugin was activated
                    if not plugin.is_activated:
                        plugin.activate()

                    # execute the provided test description and capture the result
                    testDef.logger.stage_start_print(disp_title, plugin.print_name())
                    plugin.execute(stageLog, keyvals, testDef)
                    # Make sure stdout and stderr are properly formatted
                    if 'stdout' in stageLog and isinstance(stageLog['stdout'], basestring):
                        stageLog['stdout'] = stageLog['stdout'].split("\n")
                    if 'stderr' in stageLog and isinstance(stageLog['stderr'], basestring):
                        stageLog['stderr'] = stageLog['stderr'].split("\n")
                    testDef.logger.stage_end_print(disp_title, plugin.print_name(), stageLog)
                    testDef.logger.logResults(disp_title, stageLog)
                    if testDef.options['stop_on_fail'] is not False and stageLog['status'] != 0:
                        print("Section " + stageLog['section'] + ": Status " + str(stageLog['status']))
                        try:
                            print("Section " + stageLog['section'] + ": Stderr " + str(stageLog['stderr']))
                        except KeyError:
                            pass
                        sys.exit(1)
         
                    # Set flag if any stage failed so that a return code can be passed back up
                    if stageLog['status'] != 0:
                        self.status = 1

                    # sem for exclusive access while outside exception-catching-zone
                    testDef.plugin_trans_sem.acquire()

                except KeyboardInterrupt as e:
                    self.looping = False
                    for p in testDef.stages.getAllPlugins() \
                           + testDef.tools.getAllPlugins() \
                           + testDef.utilities.getAllPlugins():
                        if not p._getIsActivated():
                            continue
                        p.plugin_object.deactivate()
                    stageLog['status'] = 0
                    stageLog['stderr'] = ["Exception was raised: %s %s" % (type(e), str(e))]
                    testDef.logger.logResults(disp_title, stageLog)
                    testDef.logger.verbose_print("=======================================")
                    testDef.logger.verbose_print("KeyboardInterrupt exception was raised: %s %s" \
                                % (type(e), str(e)))
                    testDef.logger.verbose_print("=======================================")
                    self.status = 0
                    self.only_reporter = True
                    continue

                except BaseException as e:
                    self.looping = False
                    for p in testDef.stages.getAllPlugins() \
                           + testDef.tools.getAllPlugins() \
                           + testDef.utilities.getAllPlugins():
                        if not p._getIsActivated():
                            continue
                        p.plugin_object.deactivate()
                    stageLog['status'] = 1
                    stageLog['stderr'] = ["Exception was raised: %s %s" % (type(e), str(e))]
                    testDef.logger.logResults(disp_title, stageLog)
                    testDef.logger.verbose_print("=======================================")
                    testDef.logger.verbose_print("Exception was raised: %s %s" \
                                % (type(e), str(e)))
                    testDef.logger.verbose_print("=======================================")
                    type_, value_, traceback_ = sys.exc_info()
                    ex = traceback.format_exception(type_, value_, traceback_)
                    testDef.logger.verbose_print("\n".join(ex))
                    testDef.logger.verbose_print("=======================================")
                    self.status = 1
                    self.only_reporter = True
                    continue
        self.only_reporter = False

    def execute(self, testDef):
        testDef.logger.verbose_print("ExecuteSequential")
        self.status = 0
        self.only_reporter = False
        self.looping = testDef.options['loopforever']
        self.one_last_loop = False
        self.loopforever = testDef.options['loopforever']
        self.loop_count = 0

        # Holding a semaphore while in transition between plugins
        # so async threads don't interrupt in the wrong context
        testDef.plugin_trans_sem.acquire()

        # If --duration switch is used, activate watchdog timer
        if testDef.options['duration']:
            testDef.watchdog.__init__(timeout=testDef.options['duration'],
                                      testDef=testDef)
            testDef.watchdog.activate()
            testDef.watchdog.start(handler=self.durationTimeoutHandler)

        # Start harasser
        if testDef.options["harass_trigger_scripts"] is not None:
            stageLog = {'section':"DefaultHarasser"}
            testDef.harasser.execute(stageLog,{"trigger_scripts": testDef.options["harass_trigger_scripts"],
                                  "stop_scripts": testDef.options["harass_stop_scripts"],
                                  "join_timeout": testDef.options["harass_join_timeout"]}, testDef)
            if stageLog['status'] != 0:
                self.status = 1
                self.only_reporter = True
            testDef.logger.logResults("DefaultHarasser", stageLog)

        # Keep on looping as long as it's needed
        while self.looping or self.loop_count == 0 or (self.one_last_loop and self.looping):
            self.loop_count += 1
            if self.one_last_loop:
                self.only_reporter = True
                self.looping = False
            # Execute all sections in INI file
            self.execute_sections(testDef)

        for p in testDef.stages.getAllPlugins() \
               + testDef.tools.getAllPlugins() \
               + testDef.utilities.getAllPlugins():
            if p._getIsActivated():
                p.plugin_object.deactivate()

        testDef.plugin_trans_sem.release()

        return self.status
