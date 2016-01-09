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


# First check for bozo error - we need to be given
# at least a cmd line option, so no params at all
# sounds like a plea for "help"
if 1 == len(sys.argv):
    sys.exit('MTT usage error: add -h for help')

# define the cmd line options
parser = OptionParser("usage: %prog [options] testfile1 testfile2 ...")

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
execGroup.add_option("--base-dir", dest="basedir",
                     help="Specify the DIRECTORY where we can find the TestDef class (checks DIRECTORY, DIRECTORY/Utilities, and DIRECTORY/pylib/Utilities locations) - also serves as default plugin-dir", metavar="DIRECTORY")
execGroup.add_option("--plugin-dir", dest="plugindir",
                     help="Specify the DIRECTORY where additional plugins can be found (or comma-delimited list of DIRECTORYs)", metavar="DIRECTORY")
execGroup.add_option("--scratch-dir", dest="scratchdir",
                     help="Specify the DIRECTORY under which scratch files are to be stored", metavar="DIRECTORY")
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

# Try to find the MTT TestDef class. Try several methods:

# 1. If they specified the directory, check it and underneath
#    it, if necessary
# 2. See if we are in the MTT home directory by looking for
#    the MTT plugin directory directly underneath us
# 3. Check to see if MTT_HOME is set in the environment
# 4. If $0 is a path, try seeing if that is the place.
#
if options.basedir:
    basedir = options.basedir
    topdir = basedir
    if not os.path.exists(basedir) or not os.path.isdir(basedir):
        print "The specified base directory",basedir,"doesn't exist"
        sys.exit(1)
    if not os.path.exists(os.path.join(basedir, "TestDefMTTUtility.py")):
        # try adding std path to it
        chkdir = os.path.join(options.basedir, "Utilities")
        if not os.path.exists(chkdir) or not os.path.isdir(chkdir):
            # see if the pylib/Utilities location exists
            basedir = os.path.join(options.basedir, "pylib", "Utilities")
            if not os.path.exists(basedir) or not os.path.isdir(basedir):
                print "The TestDefMTTUtility.py file was not found in the specified base directory,"
                print "and no standard location under the specified base directory",basedir,"exists"
                sys.exit(1)
            else:
                if not os.path.exists(os.path.join(basedir, "TestDefMTTUtility.py")):
                    print "The TestDefMTTUtility.py file was not found in the specified base directory,"
                    print "or any standard location under the specified base directory",basedir
                    sys.exit(1)
        else:
            if os.path.exists(os.path.join(chkdir, "TestDefMTTUtility.py")):
                basedir = chkdir
            else:
                print "The TestDefMTTUtility.py file was not found in the standard location"
                print "under the specified base directory at",chkdir
                sys.exit(1)
elif os.path.exists("TestDefMTTUtility.py"):
    # the class file is local to us, so use it
    basedir = "./"
    topdir = basedir
elif os.path.exists("pylib"):
    # we appear to be in the MTT home directory
    basedir = os.path.join("./", "pylib", "Utilities")
    topdir = os.path.join("./", "pylib")
    if not os.path.exists(basedir) or not os.path.isdir(basedir):
        print "The local directory",basedir,"doesn't exist"
        sys.exit(1)
    if not os.path.exists(os.path.join(basedir, "TestDefMTTUtility.py")):
        print "The TestDefMTTUtility.py file was not found in the standard location"
        print "under the specified base directory at",basedir
        sys.exit(1)
else:
    try:
        os.environ['MTT_HOME']
        # try that location
        basedir = os.path.join(os.environ['MTT_HOME'], "pylib", "Utilities")
        if not os.path.exists(basedir) or not os.path.isdir(basedir):
            print "MTT_HOME points to an invalid location - please correct"
            sys.exit(1)
        topdir = os.path.join(os.environ['MTT_HOME'], "pylib")
    except KeyError:
        # didn't find MTT_HOME in the environment, so
        # next see if $0 is an absolute path
        if os.path.isabs(sys.argv[0]):
            # try that location
            path = os.path.dirname(sys.argv[0])
            basedir = os.path.join(path, "pylib", "Utilities")
            topdir = os.path.join(path, "pylib")
            if not os.path.exists(basedir) or not os.path.isdir(basedir):
                print "A base directory for MTT was not specified, we do not appear"
                print "to be in the MTT home directory, and MTT_HOME has not been"
                print "set in the environment. We cannot continue as we will be"
                print "unable to find the MTT libraries"
                sys.exit(1)
        else:
            print "A base directory for MTT was not specified, we do not appear"
            print "to be in the MTT home directory, and MTT_HOME has not been"
            print "set in the environment. We cannot continue as we will be"
            print "unable to find the MTT libraries"
            sys.exit(1)

# if they want debug, set the logging level
if (options.debug):
    logging.basicConfig(level=logging.DEBUG)

# load the "testdef" Test Definition class so we can
# begin building this test
try:
    m = imp.load_source("TestDefMTTUtility", os.path.join(basedir, "TestDefMTTUtility.py"));
except ImportError:
    print "ERROR: unable to load TestDefMTTUtility that must contain the Test Definition object"
    exit(1)
cls = getattr(m, "TestDefMTTUtility")
a = cls()

# create the Test Definition object and set the
# options and arguments
testDef = a.__class__();
testDef.setOptions(options, args)

# load the plugins for this test
testDef.loadPlugins(basedir, topdir)

# provide an opportunity to print various requested
# outputs before starting to process the test
testDef.printInfo()

# if they didn't specify any files, then there is nothing
# for us to do
if not args:
    sys.exit('MTT requires at least one test-specification file')

# open the logging file if given - otherwise, we log
# to stdout
testDef.openLogger()

# Read the input test definition file(s)
testDef.configTest()

# Now execute the strategy
testDef.executeTest()

# Report the results
testDef.report()

# All done!
