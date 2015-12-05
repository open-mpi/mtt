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

# define a global hash for stages
stages = {}
tools = {}
utilities = {}

def loadClasses(directory):
    global stages
    global tools
    global utilities
    oldcwd = os.getcwd()
    os.chdir(directory)   # change our working dir
    for filename in os.listdir(directory):
        if os.path.isdir(filename):
            filename = os.path.join(directory, filename)
            loadClasses(filename)
            continue
        if "MTT" not in filename:
            continue
        if not filename.endswith(".py"):
            continue
        if "Stage" not in filename and "Tool" not in filename and "Utility" not in filename:
            continue
        modname = filename[:-3]
        try:
            m = imp.load_source(modname, filename)
        except ImportError:
            print "ERROR: unable to load " + modname + " from file " + filename
            exit(1)
        try:
            cls = getattr(m, modname)
            a = cls()
            if "Stage" in modname:
                # trim the MTTClass from the name - it was included
                # solely to avoid confusion with global namespaces
                modname = modname[:-8]
                stages[modname] = a.__class__
            elif "Tool" in modname:
                # trim the MTTTool from the name - it was included
                # solely to avoid confusion with global namespaces
                modname = modname[:-7]
                tools[modname] = a.__class__
            elif "Utility" in modname:
                # trim the MTTUtility from the name - it was included
                # solely to avoid confusion with global namespaces
                modname = modname[:-10]
                utilities[modname] = a.__class__
        except AttributeError:
            # just ignore it
            continue
    os.chdir(oldcwd)

# First check for bozo error - we need to be given
# at least a cmd line option, so no params at all
# sounds like a plea for "help"
if 1 == len(sys.argv):
    sys.exit('MTT usage error: add -h for help')

# define the cmd line options
parser = OptionParser()

infoGroup = OptionGroup(parser, "Informational Options")
infoGroup.add_option("-v", "--version",
                     action="store_true", dest="version", default=False,
                     help="Print version")
infoGroup.add_option("--list-sections",
                     action="store_true", dest="listsections", default=False,
                     help="List section names understood by this client")
infoGroup.add_option("--list-plugins",
                     action="store", dest="listplugins", metavar="SECTION",
                     help="List available plugins for SECTION (* => all)")
infoGroup.add_option("--list-tools",
                     action="store_true", dest="listtools", default=False,
                     help="List tools available to this client")
infoGroup.add_option("--list-tool-modules",
                     action="store", dest="listtoolmodules", metavar="TYPE",
                     help="List available modules for TYPE (* => all)")
parser.add_option_group(infoGroup)

execGroup = OptionGroup(parser, "Execution Options")
execGroup.add_option("-e", "--executor", dest="executor",
                     help="Use the specified execution STRATEGY module", metavar="STRATEGY")

execGroup.add_option("-f", "--file", dest="filename",
                     help="Specify the test configuration FILE (or comma-delimited list of FILEs)", metavar="FILE")
execGroup.add_option("--plugin-dir", dest="plugindir",
                     help="Specify the DIRECTORY where additional plugins can be found (or comma-delimited list of DIRECTORYs)", metavar="DIRECTORY")
execGroup.add_option("--base-dir", dest="basedir",
                     help="Specify the DIRECTORY where the MTT software is located", metavar="DIRECTORY")
execGroup.add_option("--print-section-time", dest="sectime",
                      action="store_true", default=False,
                      help="Display the amount of time taken in each section")
execGroup.add_option("--print-cmd-time", dest="cmdtime",
                     action="store_true", default=False,
                     help="Display the amount of time taken by each command")
execGroup.add_option("--timestamp", dest="time",
                     action="store_true", default=False,
                     help="Alias for --print-section-time --print-cmd-time")
execGroup.add_option("--clean-start", dest="clean",
                     action="store_true", default=False,
                     help="Clean the scratch directory from past MTT invocations before running")
execGroup.add_option("-s", "--section", dest="section",
                     help="Execute the specified SECTION (or comma-delimited list of SECTIONs)", metavar="SECTION")
execGroup.add_option("--skip-sections", dest="skipsections",
                     help="Skip the specified SECTION (or comma-delimited list of SECTIONs)", metavar="SECTION")
execGroup.add_option("--no-reporter", dest="reporter",
                      action="store_true", default=False,
                      help="Do not invoke any MTT Reporter modules")
execGroup.add_option("-l", "--log", dest="logfile",
                     help="Log all output to FILE (defaults to stdout)", metavar="FILE")
parser.add_option_group(execGroup)

debugGroup = OptionGroup(parser, "Debug Options")
debugGroup.add_option("-d", "--debug", dest="debug",
                      action="store_true", default=False,
                      help="Output lots of debug messages")
debugGroup.add_option("--verbose",
                      action="store_true", dest="verbose", default=False,
                      help="Output some status/verbose messages while processing")
debugGroup.add_option("--dryrun",
                      action="store_true", dest="dryrun", default=False,
                      help="Show commands, but do not execute them")
debugGroup.add_option("--trial",
                      action="store_true", dest="trial", default=False,
                      help="Use when testing your MTT client setup; results that are generated and submitted to the database are marked as \"trials\" and are not included in normal reporting.")
debugGroup.add_option("--getvalue",
                      action="store", dest="getvalue", metavar="<section>,<param>",
                      help="Print the value of the specified INI parameter and exit")
parser.add_option_group(debugGroup)
(options, args) = parser.parse_args()

# Try to find the MTT files. We do this early so that
# we can import the version file in case someone asks
# for that information.  Assume that mtt executable is in the
# base directory for the MTT files.  Try several methods:

# 1. See if we are in the MTT home directory by looking for
#    the MTT plugin directory directly underneath us
# 2. Check to see if MTT_HOME is set in the environment
# 3. If $0 is a path, try seeing if that is the place.
# 4. Otherwise, search $ENV[PATH] for mtt, and when you find it, check
#    if the plugins are there.

if os.path.exists("pyclient") and os.path.exists("pylib"):
    # we appear to be in the home directory
    basedir = os.path.join("./", "pylib")
else:
    try:
        os.environ['MTT_HOME']
        # use that location
        basedir = os.path.join(os.environ['MTT_HOME'], "pylib")
    except KeyError:
        # didn't find MTT_HOME in the environment, so
        # try searching the PATH for it
        for path in os.environ["PATH"].split(os.pathsep):
            path = path.strip('"')
            exe_file = os.path.join(path, "pyclient")
            if os.path.isfile(exe_file) and os.access(fpath, os.X_OK)(exe_file):
                basedir = os.path.join(path, "pylib")
            else:
                print "We do not appear to be in the MTT home directory, nor has"
                print "MTT_HOME been set in the environment. We cannot continue"
                print "as we will be unable to find the MTT libraries"
                sys.exit(1)

# if they want debug, set the logging level
if (options.debug):
    logging.basicConfig(level=logging.DEBUG)

# if they asked us to print all times, then flag both sets
if (options.time):
    options.cmdtime = True
    options.sectime = True

# if they didn't specify an execution strategy, then default
# to sequential as least surprise
if not options.executor:
    options.executor = "sequential"

# if they want us to use a different base directory, then
# set it to that point
if options.basedir:
  basedir = os.path.join(options.basedir, "pylib")
  if not os.path.isdir(basedir):
    print "Cannot find options.basedir"
    sys.exit(1)
  if not os.access(fpath, os.X_OK)(options.basedir):
    print "Access permission filuare for options.basedir"
    sys.exit(1)
  if not os.access(fpath, os.X_OK)(basedir):
    print "Required directory basedir not available"
    sys.exit(1)

# Setup the array of directories we will search for plugins
# Note that we always look at the basedir location
plugindirs = []
plugindirs.append(basedir)
if options.plugindir:
    # could be a comma-delimited list, so split on commas
    x = options.plugindir.split(',')
    for y in x:
        plugindirs.append(y)

# Traverse the plugin directory tree and add all
# the class definitions we can find
for dirPath in plugindirs:
    filez = os.listdir(dirPath)
    for file in filez:
        file = os.path.join(dirPath, file)
        if os.path.isdir(file):
            loadClasses(file)

# Build the section plugin manager - the plugins should
# be in the directories located under the basedir
mttPluginManager = PluginManager()
# set the location - we always look at the basedir,
# but we will also look at any specified locations
mttPluginManager.setPluginPlaces([basedir])
# Get a list of all the categories - this corresponds to
# the MTT stages that have been defined. Note that we
# don't need to formally define the stages here - anyone
# can add a new stage, or delete an old one, by simply
# adding or removing a plugin directory.
mttPluginManager.setCategoriesFilter(stages)
# Load all plugins we find there
mttPluginManager.collectPlugins()

# Build the tools plugin manager - tools differ from sections
# in that they are plugins we will use to execute the various
# sections. For example, the TestRun section clearly needs the
# ability to launch jobs. There are many ways to launch jobs
# depending on the environment, and sometimes several ways to
# start jobs even within one environment (e.g., mpirun vs
# direct launch).
toolPluginManager = PluginManager()
# location is the same
toolPluginManager.setPluginPlaces([basedir])
# Get the list of tools - not every tool will be capable
# of executing. For example, a tool that supports direct launch
# against a specific resource manager cannot be used on a
# system being managed by a different RM.
toolPluginManager.setCategoriesFilter(tools)
# Load all the tool plugins
toolPluginManager.collectPlugins()
# Tool plugins are required to provide a function we can
# probe to determine if they are capable of operating - check
# those now and prune those tools that cannot support this
# environment

# Print the available MTT sections out, if requested
if options.listsections:
    print "Supported MTT stages:"
    stages = stages.keys()
    for stage in stages:
        print "    " + stage
    exit(0)

# Print the detected plugins for a given section
if options.listplugins:
    # if the list is '*', print the plugins for every section
    if options.listplugins == "*":
        sections = stages.keys()
    else:
        sections = options.listplugins.split(',')
    print
    for section in sections:
        print section + ":"
        try:
            for pluginInfo in mttPluginManager.getPluginsOfCategory(section):
                print "    " + pluginInfo.plugin_object.print_name()
        except KeyError:
          print "    Invalid section name " + section
        print
    exit(1)

# Print the available MTT tools out, if requested
if options.listtools:
    print "Available MTT tools:"
    availTools = tools.keys()
    for tool in availTools:
        print "    " + tool
    exit(0)

# Print the detected tool plugins for a given tool type
if options.listtoolmodules:
    # if the list is '*', print the plugins for every type
    if options.listtoolmodules == "*":
        print
        availTools = tools.keys()
    else:
        availTools = options.listtoolmodules.split(',')
    print
    for tool in availTools:
        print tool + ":"
        try:
            for pluginInfo in toolPluginManager.getPluginsOfCategory(tool):
                print "    " + pluginInfo.plugin_object.print_name()
        except KeyError:
            print "    Invalid tool type name"
        print
    exit(1)


# if they asked for the version info, print it and exit
if options.version:
    for pluginInfo in toolPluginManager.getPluginsOfCategory("Version"):
        print "MTT Base:   " + pluginInfo.plugin_object.getVersion()
        print "MTT Client: " + pluginInfo.plugin_object.getClientVersion()
    sys.exit(0)

# if they didn't specify any files, then there is nothing
# for us to do
if not options.filename:
    sys.exit('MTT requires at least one test-specification file')

# open the logging file if given - otherwise, we log
# to stdout
logger = utilities["Logger"]()
logger.open(options)

# Read the input test definition file(s)
testFiles = options.filename.split(',')
for testFile in testFiles:
    Config = ConfigParser.ConfigParser()
    Config.read(testFile)
    for section in Config.sections():
        logger.verbose_print(options, "SECTION: " + section)
        logger.verbose_print(options, Config.items(section))
        logger.timestamp(options)
        if options.dryrun:
            continue
        if section.startswith("SKIP") or section.startswith("skip"):
            # users often want to temporarily ignore a section
            # of their test definition file, but don't want to
            # remove it lest they forget what it did. So let
            # them just mark the section as "skip" to be ignored
            continue;

# Activate the specified execution strategy module
toolPluginManager.activatePluginByName(options.executor, "Executor")
# Pass it the list of test files for execution
executor = toolPluginManager.getPluginByName(options.executor, "Executor")
print "Executing: " + executor.plugin_object.print_name()
executor.plugin_object.execute(options, mttPluginManager, toolPluginManager)

# Activate all loaded plugins
#for pluginInfo in mttPluginManager.getAllPlugins():
#   mttPluginManager.activatePluginByName(pluginInfo.name)


