#!/usr/bin/env python

import os
import sys
import ConfigParser
import importlib
from yapsy.PluginManager import PluginManager
from optparse import OptionParser, OptionGroup

def print_version():
    print "MTT: {}.{}.{}{}".format(version.MTTMajor,
                                 version.MTTMinor,
                                 version.MTTRelease,
                                 version.MTTGreek)
    print "MTTClient: {}.{}.{}{}".format(version.MTTPyClientMajor,
                                       version.MTTPyClientMinor,
                                       version.MTTPyClientRelease,
                                       version.MTTPyClientGreek)
    sys.exit(0);

# First check for bozo error - we need to be given
# at least one INI file to execute, so there has to
# be at least one argument
if 1 == len(sys.argv):
    sys.exit('MTT usage error: add -h for help')

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
    basedir = "./"
else:
    try:
        os.environ['MTT_HOME']
        # use that location
        basedir = os.environ['MTT_HOME']
    except KeyError:
        # didn't find MTT_HOME in the environment, so
        # try searching the PATH for it
        for path in os.environ["PATH"].split(os.pathsep):
            path = path.strip('"')
            exe_file = os.path.join(path, "pyclient")
            if os.path.isfile(exe_file) and os.access(fpath, os.X_OK)(exe_file):
                print exe_file
            else:
                print "cannot find anything"
                sys.exit(1)

# check for existence of version file
versiondir = os.path.join(basedir, "pylib")
versionfile = os.path.join(versiondir, "MTTVersion.py")
if not os.path.exists(versionfile):
    errout = "Could not find required version file ", versionfile
    sys.exit(errout)
sys.path.append(versiondir)
version = importlib.import_module("MTTVersion", package=None)


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
                     help="List available plugins for SECTION")
parser.add_option_group(infoGroup)

execGroup = OptionGroup(parser, "Execution Options")
execGroup.add_option("-f", "--file", dest="filename",
                     help="Specify the test configuration FILE (or comma-delimited list of FILEs)", metavar="FILE")
execGroup.add_option("--print-section-time", dest="sectime",
                      action="store_true", default=False,
                      help="Display the amount of time taken in each section")
execGroup.add_option("--print-cmd-time", dest="cmdtime",
                     action="store_true", default=False,
                     help="Display the amount of time taken by each command")
execGroup.add_option("--print-time", dest="time",
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

# if they asked for the version info, print it and exit
if (options.version):
    print_version()

# if they didn't specify any files, then there is nothing
# for us to do
if not options.filename:
    sys.exit('MTT requires at least one test-specification file')

# if they asked us to print all times, then flag both sets
if (options.time):
    options.cmdtime = True
    options.sectime = True

# Build the plugin manager
mttPluginManager = PluginManager()
# Tell it the default place(s) where to find plugins
mttPluginManager.setPluginPlaces([basedir])
# Load all plugins
mttPluginManager.collectPlugins()
# Activate all loaded plugins
for pluginInfo in mttPluginManager.getAllPlugins():
   mttPluginManager.activatePluginByName(pluginInfo.name)


Config = ConfigParser.ConfigParser()
Config.read("./test.ini")
print Config.sections()







# Define the various categories corresponding to the different
# kinds of plugins you have defined
#simplePluginManager.setCategoriesFilter({
#   "Playback" : IPlaybackPlugin,
#   "SongInfo" : ISongInfoPlugin,
#   "Visualization" : IVisualisation,
#   })

# Trigger 'some action' from the "Visualization" plugins
#for pluginInfo in simplePluginManager.getPluginsOfCategory("Visualization"):
#   pluginInfo.plugin_object.doSomething(...)


