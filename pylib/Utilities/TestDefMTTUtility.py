#!/usr/bin/env python
#
# Copyright (c) 2015      Intel, Inc. All rights reserved.
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
from yapsy.PluginManager import PluginManager
from optparse import OptionParser, OptionGroup
import datetime

# The Test Definition class is mostly a storage construct
# to make it easier when passing values across stages and
# tools.

class TestDefMTTUtility:
    def __init__(self):
        self.options = {}
        self.args = []
        self.executor = "sequential"
        self.loaded = False
        self.logger = None
        self.trial_run = False
        self.scratch = ""
        self.submit_group_results = True
        self.logfile = ""
        self.description = ""

    def setOptions(self, options, args):
        self.options = options
        self.args = args
        # if they asked us to print all times, then flag both sets
        if (options.time):
            self.options.cmdtime = True
            self.options.sectime = True
        # if they specified an execution strategy, set it
        if options.executor:
            self.executor = options.executor

    def loadPlugins(self, basedir, topdir):
        if self.loaded:
            print "Cannot load plugins multiple times"
            exit(1)
        self.loaded = True

        # find the loader utility
        try:
            m = imp.load_source("LoadClassesMTTUtility", os.path.join(basedir, "LoadClassesMTTUtility.py"));
        except ImportError:
            print "ERROR: unable to load LoadClassesMTTUtility that must contain the class loader object"
            exit(1)
        cls = getattr(m, "LoadClassesMTTUtility")
        a = cls()
        # setup the loader object
        self.loader = a.__class__();

        # Setup the array of directories we will search for plugins
        # Note that we always look at the topdir location by default
        plugindirs = []
        plugindirs.append(topdir)
        if self.options.plugindir:
            # could be a comma-delimited list, so split on commas
            x = self.options.plugindir.split(',')
            for y in x:
                # prepend so we always look at the given
                # location first in case the user wants
                # to "overload/replace" a default MTT
                # class definition
                plugindirs.prepend(y)

        # Traverse the plugin directory tree and add all
        # the class definitions we can find
        for dirPath in plugindirs:
            filez = os.listdir(dirPath)
            for file in filez:
                file = os.path.join(dirPath, file)
                if os.path.isdir(file):
                    self.loader.load(file)

        # Instantiate the logger

        # Build the section plugin manager
        self.pluginManager = PluginManager()
        # set the location
        self.pluginManager.setPluginPlaces(plugindirs)
        # Get a list of all the categories - this corresponds to
        # the MTT stages that have been defined. Note that we
        # don't need to formally define the stages here - anyone
        # can add a new stage, or delete an old one, by simply
        # adding or removing a plugin directory.
        self.pluginManager.setCategoriesFilter(self.loader.stages)
        # Load all plugins we find there
        self.pluginManager.collectPlugins()

        # Build the tools plugin manager - tools differ from sections
        # in that they are plugins we will use to execute the various
        # sections. For example, the TestRun section clearly needs the
        # ability to launch jobs. There are many ways to launch jobs
        # depending on the environment, and sometimes several ways to
        # start jobs even within one environment (e.g., mpirun vs
        # direct launch).
        self.toolPluginManager = PluginManager()
        # location is the same
        self.toolPluginManager.setPluginPlaces(plugindirs)
        # Get the list of tools - not every tool will be capable
        # of executing. For example, a tool that supports direct launch
        # against a specific resource manager cannot be used on a
        # system being managed by a different RM.
        self.toolPluginManager.setCategoriesFilter(self.loader.tools)
        # Load all the tool plugins
        self.toolPluginManager.collectPlugins()
        # Tool plugins are required to provide a function we can
        # probe to determine if they are capable of operating - check
        # those now and prune those tools that cannot support this
        # environment

    def printInfo(self):
        # Print the available MTT sections out, if requested
        if self.options.listsections:
            print "Supported MTT stages:"
            stages = self.loader.stages.keys()
            for stage in stages:
                print "    " + stage
            exit(0)

        # Print the detected plugins for a given section
        if self.options.listplugins:
            # if the list is '*', print the plugins for every section
            if self.options.listplugins == "*":
                sections = self.loader.stages.keys()
            else:
                sections = self.options.listplugins.split(',')
            print
            for section in sections:
                print section + ":"
                try:
                    for pluginInfo in self.pluginManager.getPluginsOfCategory(section):
                        print "    " + pluginInfo.plugin_object.print_name()
                except KeyError:
                  print "    Invalid section name " + section
                print
            exit(1)

        # Print the available MTT tools out, if requested
        if self.options.listtools:
            print "Available MTT tools:"
            availTools = self.loader.tools.keys()
            for tool in availTools:
                print "    " + tool
            exit(0)

        # Print the detected tool plugins for a given tool type
        if self.options.listtoolmodules:
            # if the list is '*', print the plugins for every type
            if self.options.listtoolmodules == "*":
                print
                availTools = loader.tools.keys()
            else:
                availTools = self.options.listtoolmodules.split(',')
            print
            for tool in availTools:
                print tool + ":"
                try:
                    for pluginInfo in self.toolPluginManager.getPluginsOfCategory(tool):
                        print "    " + pluginInfo.plugin_object.print_name()
                except KeyError:
                    print "    Invalid tool type name"
                print
            exit(1)


        # if they asked for the version info, print it and exit
        if self.options.version:
            for pluginInfo in self.toolPluginManager.getPluginsOfCategory("Version"):
                print "MTT Base:   " + pluginInfo.plugin_object.getVersion()
                print "MTT Client: " + pluginInfo.plugin_object.getClientVersion()
            sys.exit(0)

    def openLogger(self):
        if self.loader.utilities["Logger"]:
            self.logger = self.loader.utilities["Logger"]()
            self.logger.open(self.options)

    def configTest(self):
        for testFile in self.args:
            Config = ConfigParser.ConfigParser()
            Config.read(testFile)
            for section in Config.sections():
                if self.logger is not None:
                    self.logger.verbose_print(self.options, "SECTION: " + section)
                    self.logger.verbose_print(self.options, Config.items(section))
                    self.logger.timestamp(self.options)
                if self.options.dryrun:
                    continue
                if section.startswith("SKIP") or section.startswith("skip"):
                    # users often want to temporarily ignore a section
                    # of their test definition file, but don't want to
                    # remove it lest they forget what it did. So let
                    # them just mark the section as "skip" to be ignored
                    continue;
                if "MTTDefaults" in section:
                    self.setDefaults(Config.items(section))

    def executeTest(self):
        print "EXECUTE"

    def report(self):
        print "REPORT"

    def setDefaults(self, defaults=[]):
        for default in defaults:
            if "trial_run" in default[0]:
                self.trial_run = default[1]
            elif "scratch" in default[0]:
                self.scratch_dir = default[1]
            elif "logfile" in default[0]:
                self.logfile = default[1]
            elif "description" in default[0]:
                self.description = default[1]
            elif "submit_group_results" in default[0]:
                self.submit_group_results = default[1]

# Activate the specified execution strategy module
#toolPluginManager.activatePluginByName(options.executor, "Executor")
# Pass it the list of test files for execution
#executor = toolPluginManager.getPluginByName(options.executor, "Executor")
#print "Executing: " + executor.plugin_object.print_name()
#executor.plugin_object.execute(options, mttPluginManager, toolPluginManager)

# Activate all loaded plugins
#for pluginInfo in mttPluginManager.getAllPlugins():
#   mttPluginManager.activatePluginByName(pluginInfo.name)


