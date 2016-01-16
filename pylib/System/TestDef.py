#!/usr/bin/env python
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import os
import shutil
import sys
import ConfigParser
import importlib
import logging
import imp
from yapsy.PluginManager import PluginManager
from optparse import OptionParser, OptionGroup
import datetime
from distutils.spawn import find_executable

# The Test Definition class is mostly a storage construct
# to make it easier when passing values across stages and
# tools.

def _mkdir_recursive(path):
    sub_path = os.path.dirname(path)
    if sub_path and not os.path.exists(sub_path):
        _mkdir_recursive(sub_path)
    if not os.path.exists(path):
        os.mkdir(path)


class TestDef:
    def __init__(self):
        # set aside storage for options and cmd line args
        self.options = {}
        self.args = []
        # record if we have loaded the plugins or
        # not - this is just a bozo check to ensure
        # someone doesn't tell us to do it twice
        self.loaded = False
        # set aside a spot for a logger object, and
        # note that it hasn't yet been defined
        self.logger = None
        self.modcmd = None
        self.execmd = None
        self.config = None
        self.stages = None
        self.tools = None
        self.utilities = None

    def setOptions(self, options, args):
        self.options = options
        self.args = args
        # if they asked us to print all times, then flag both sets
        if (options.time):
            self.options.cmdtime = True
            self.options.sectime = True

    def loadPlugins(self, basedir, topdir):
        if self.loaded:
            print "Cannot load plugins multiple times"
            exit(1)
        self.loaded = True

        # find the loader utility so we can bootstrap ourselves
        try:
            m = imp.load_source("LoadClasses", os.path.join(basedir, "LoadClasses.py"));
        except ImportError:
            print "ERROR: unable to load LoadClasses that must contain the class loader object"
            exit(1)
        cls = getattr(m, "LoadClasses")
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

        # Build the stages plugin manager
        self.stages = PluginManager()
        # set the location
        self.stages.setPluginPlaces(plugindirs)
        # Get a list of all the categories - this corresponds to
        # the MTT stages that have been defined. Note that we
        # don't need to formally define the stages here - anyone
        # can add a new stage, or delete an old one, by simply
        # adding or removing a plugin directory.
        self.stages.setCategoriesFilter(self.loader.stages)
        # Load all plugins we find there
        self.stages.collectPlugins()

        # Build the tools plugin manager - tools differ from sections
        # in that they are plugins we will use to execute the various
        # sections. For example, the TestRun section clearly needs the
        # ability to launch jobs. There are many ways to launch jobs
        # depending on the environment, and sometimes several ways to
        # start jobs even within one environment (e.g., mpirun vs
        # direct launch).
        self.tools = PluginManager()
        # location is the same
        self.tools.setPluginPlaces(plugindirs)
        # Get the list of tools - not every tool will be capable
        # of executing. For example, a tool that supports direct launch
        # against a specific resource manager cannot be used on a
        # system being managed by a different RM.
        self.tools.setCategoriesFilter(self.loader.tools)
        # Load all the tool plugins
        self.tools.collectPlugins()
        # Tool plugins are required to provide a function we can
        # probe to determine if they are capable of operating - check
        # those now and prune those tools that cannot support this
        # environment

        # Build the utilities plugins
        self.utilities = PluginManager()
        # set the location
        self.utilities.setPluginPlaces(plugindirs)
        # Get the list of available utilities.
        self.utilities.setCategoriesFilter(self.loader.utilities)
        # Load all the utility plugins
        self.utilities.collectPlugins()

        # since we use these all over the place, find the
        # ExecuteCmd and ModuleCmd plugins and record them
        availUtil = self.loader.utilities.keys()
        for util in availUtil:
            for pluginInfo in self.utilities.getPluginsOfCategory(util):
                if "ExecuteCmd" == pluginInfo.plugin_object.print_name():
                    self.execmd = pluginInfo.plugin_object
                elif "ModuleCmd" == pluginInfo.plugin_object.print_name():
                    self.modcmd = pluginInfo.plugin_object
                if self.execmd is not None and self.modcmd is not None:
                    break
        if self.execmd is None:
            print "ExecuteCmd plugin was not found"
            print "This is a basic capability required"
            print "for MTT operations - cannot continue"
            sys.exit(1)

        return

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
                    for pluginInfo in self.stages.getPluginsOfCategory(section):
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
                availTools = self.loader.tools.keys()
            else:
                availTools = self.options.listtoolmodules.split(',')
            print
            for tool in availTools:
                print tool + ":"
                try:
                    for pluginInfo in self.tools.getPluginsOfCategory(tool):
                        print "    " + pluginInfo.plugin_object.print_name()
                except KeyError:
                    print "    Invalid tool type name"
                print
            exit(1)


        # Print the available MTT utilities out, if requested
        if self.options.listutils:
            print "Available MTT utilities:"
            availUtils = self.loader.utilities.keys()
            for util in availUtils:
                print "    " + util
            exit(0)

        # Print the detected utility plugins for a given tool type
        if self.options.listutilmodules:
            # if the list is '*', print the plugins for every type
            if self.options.listutilmodules == "*":
                print
                availUtils = self.loader.utilities.keys()
            else:
                availUtils = self.options.listutilitymodules.split(',')
            print
            for util in availUtils:
                print util + ":"
                try:
                    for pluginInfo in self.utilities.getPluginsOfCategory(util):
                        print "    " + pluginInfo.plugin_object.print_name()
                except KeyError:
                    print "    Invalid utility type name"
                print
            exit(1)


        # if they asked for the version info, print it and exit
        if self.options.version:
            for pluginInfo in self.tools.getPluginsOfCategory("Version"):
                print "MTT Base:   " + pluginInfo.plugin_object.getVersion()
                print "MTT Client: " + pluginInfo.plugin_object.getClientVersion()
            sys.exit(0)

    def openLogger(self):
        # there must be a logger utility or we can't do
        # anything useful
        if not self.utilities.activatePluginByName("Logger", "Base"):
            print "Required Logger plugin not found or could not be activated"
            sys.exit(1)
        # execute the provided test description
        self.logger = self.utilities.getPluginByName("Logger", "Base").plugin_object
        self.logger.open(self.options)
        return

    def configTest(self):
        for testFile in self.args:
            self.config = ConfigParser.ConfigParser()
            self.config.read(testFile)
            for section in self.config.sections():
                if self.logger is not None:
                    self.logger.verbose_print(self.options, "SECTION: " + section)
                    self.logger.verbose_print(self.options, self.config.items(section))
                    self.logger.timestamp(self.options)
                if self.options.dryrun:
                    continue
                if section.startswith("SKIP") or section.startswith("skip"):
                    # users often want to temporarily ignore a section
                    # of their test definition file, but don't want to
                    # remove it lest they forget what it did. So let
                    # them just mark the section as "skip" to be ignored
                    continue;
                if "MTTDefaults" == section.strip():
                    self.setDefaults(self.config.items(section))
        return

    def executeTest(self):
        if not self.loaded:
            print "Plugins have not been loaded - cannot execute test"
            exit(1)
        if self.config is None:
            print "No test definition file was parsed - cannot execute test"
            exit(1)
        if not self.tools.getPluginByName(self.options.executor, "Executor"):
            print "Specified executor",self.executor,"not found"
            exit(1)
        # if they want us to clear the scratch, then do so
        if self.options.clean:
            shutil.rmtree(self.options.scratchdir)
        # setup the scratch directory
        _mkdir_recursive(self.options.scratchdir)
        # activate the specified plugin
        self.tools.activatePluginByName(self.options.executor, "Executor")
        # execute the provided test description
        executor = self.tools.getPluginByName(self.options.executor, "Executor")
        executor.plugin_object.execute(self)
        return

    def report(self):
        if self.logger is not None:
            self.logger.outputLog()
        return

    def setDefaults(self, defaults=[]):
        for default in defaults:
            if "trial_run" in default[0]:
                self.options.trial = default[1]
            elif "scratch" in default[0]:
                self.options.scratchdir = default[1]
            elif "logfile" in default[0]:
                self.options.logfile = default[1]
            elif "description" in default[0]:
                self.options.description = default[1]
            elif "submit_group_results" in default[0]:
                self.options.submit_group_results = default[1]
        return

# Activate the specified execution strategy module
#toolPluginManager.activatePluginByName(options.executor, "Executor")
# Pass it the list of test files for execution
#executor = toolPluginManager.getPluginByName(options.executor, "Executor")
#print "Executing: " + executor.plugin_object.print_name()
#executor.plugin_object.execute(options, mttPluginManager, toolPluginManager)

# Activate all loaded plugins
#for pluginInfo in mttPluginManager.getAllPlugins():
#   mttPluginManager.activatePluginByName(pluginInfo.name)


