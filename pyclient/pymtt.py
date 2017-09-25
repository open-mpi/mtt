#!/usr/bin/env python
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
from yapsy.PluginManager import PluginManager
import argparse

# First check for bozo error - we need to be given
# at least a cmd line option, so no params at all
# sounds like a plea for "help"
#if 1 == len(sys.argv):
#    sys.exit('MTT usage error: add -h for help')

# define the cmd line arguments
parser = argparse.ArgumentParser(description="usage: %prog [options] testfile1 testfile2 ...")

parser.add_argument('ini_files', action='append', metavar='FILE', nargs='*', help = ".ini file to be used")

infoGroup = parser.add_argument_group('InfoGroup','Informational Options')
infoGroup.add_argument("-v", "--version",
                     action="store_true", dest="version", default=False,
                     help="Print version")
infoGroup.add_argument("--list-stages",
                     action="store_true", dest="listsections", default=False,
                     help="List section names understood by this client")
infoGroup.add_argument("--list-stage-plugins",
                     action="store", dest="listplugins", metavar="STAGE",
                     help="List available plugins for SECTION (* => all)")
infoGroup.add_argument("--list-stage-options",
                     action="store", dest="liststageoptions", metavar="STAGE",
                     help="List available options for STAGE (* => all)")
infoGroup.add_argument("--list-tools",
                     action="store_true", dest="listtools", default=False,
                     help="List tools available to this client")
infoGroup.add_argument("--list-tool-plugins",
                     action="store", dest="listtoolmodules", metavar="TYPE",
                     help="List available modules for TYPE (* => all)")
infoGroup.add_argument("--list-tool-options",
                     action="store", dest="listtooloptions", metavar="TOOL",
                     help="List available options for TOOL (* => all)")
infoGroup.add_argument("--list-utilities",
                     action="store_true", dest="listutils", default=False,
                     help="List utilities available to this client")
infoGroup.add_argument("--list-utility-plugins",
                     action="store", dest="listutilmodules", metavar="TYPE",
                     help="List available modules for TYPE (* => all)")
infoGroup.add_argument("--list-utility-options",
                     action="store", dest="listutiloptions", metavar="UTILITY",
                     help="List available options for UTILITY (* => all)")

execGroup = parser.add_argument_group('execGroup', "Execution Options")
execGroup.add_argument("--description", dest="description",
                     help="Provide a brief title/description to be included in the log for this test")
execGroup.add_argument("-e", "--executor", dest="executor",
                     help="Use the specified execution STRATEGY module", metavar="STRATEGY")
execGroup.add_argument("--base-dir", dest="basedir",
                     help="Specify the DIRECTORY where we can find the TestDef class (checks DIRECTORY, DIRECTORY/Utilities, and DIRECTORY/pylib/Utilities locations) - also serves as default plugin-dir", metavar="DIRECTORY")
execGroup.add_argument("--plugin-dir", dest="plugindir",
                     help="Specify the DIRECTORY where additional plugins can be found (or comma-delimited list of DIRECTORYs)", metavar="DIRECTORY")
execGroup.add_argument("--ignore-loadpath-errors", action="store_true", dest="ignoreloadpatherrs", default=False,
                     help="Ignore errors in plugin paths")
execGroup.add_argument("--scratch-dir", dest="scratchdir", default="./mttscratch",
                     help="Specify the DIRECTORY under which scratch files are to be stored", metavar="DIRECTORY")
execGroup.add_argument("--print-section-time", dest="sectime",
                      action="store_true", default=True,
                      help="Display section timestamps and execution time")
execGroup.add_argument("--print-cmd-time", dest="cmdtime",
                     action="store_true", default=False,
                     help="Display stdout/stderr timestamps and cmd execution time")
execGroup.add_argument("--timestamp", dest="time",
                     action="store_true", default=False,
                     help="Alias for --print-section-time --print-cmd-time")
execGroup.add_argument("--clean-start", dest="clean",
                     action="store_true",
                     help="Clean the scratch directory from past MTT invocations before running")
execGroup.add_argument("-s", "--sections", dest="section",
                     help="Execute the specified SECTION (or comma-delimited list of SECTIONs)", metavar="SECTION")
execGroup.add_argument("--skip-sections", dest="skipsections",
                     help="Skip the specified SECTION (or comma-delimited list of SECTIONs)", metavar="SECTION")
execGroup.add_argument("--no-reporter", dest="reporter",
                      action="store_true", default=False,
                      help="Do not invoke any MTT Reporter modules")
execGroup.add_argument("-l", "--log", dest="logfile", default=None,
                     help="Log all output to FILE (defaults to stdout)", metavar="FILE")
execGroup.add_argument("--group-results", dest="submit_group_results", default=True,
                     help="Report results from each test section as it is completed")
execGroup.add_argument("--default-make-options", dest="default_make_options", default="-j10",
                     help="Default options when running the \"make\" command")
execGroup.add_argument("--env-module-wrapper", dest="env_module_wrapper", default=None,
                     help="Python environment module wrapper")
execGroup.add_argument("--stop-on-fail", dest="stop_on_fail",
                     action="store_true", default=False,
                     help="If a stage fails, exit and issue a non-zero return code")

debugGroup = parser.add_argument_group('debugGroup', 'Debug Options')
debugGroup.add_argument("-d", "--debug", dest="debug",
                      action="store_true", default=False,
                      help="Output lots of debug messages")
debugGroup.add_argument("--verbose",
                      action="store_true", dest="verbose", default=False,
                      help="Output some status/verbose messages while processing")
debugGroup.add_argument("--extraverbose",
                      action="store_true", dest="extraverbose", default=False,
                      help="Output timestamps with every verbose message")
debugGroup.add_argument("--dryrun",
                      action="store_true", dest="dryrun", default=False,
                      help="Show commands, but do not execute them")
debugGroup.add_argument("--trial",
                      action="store_true", dest="trial", default=False,
                      help="Use when testing your MTT client setup; results that are generated and submitted to the database are marked as \"trials\" and are not included in normal reporting.")
args = parser.parse_args()


# Try to find the MTT TestDef class. Try several methods:

# 1. If they specified the directory, check it and underneath
#    it, if necessary
# 2. See if we are in the MTT home directory by looking for
#    the MTT plugin directory directly underneath us
# 3. Check to see if MTT_HOME is set in the environment
# 4. If $0 is a path, try seeing if that is the place.
#
if args.basedir:
    basedir = args.basedir
    topdir = basedir
    if not os.path.exists(basedir) or not os.path.isdir(basedir):
        print("The specified base directory",basedir,"doesn't exist")
        sys.exit(1)
    if not os.path.exists(os.path.join(basedir, "TestDef.py")):
        # try adding std path to it
        chkdir = os.path.join(args.basedir, "System")
        if not os.path.exists(chkdir) or not os.path.isdir(chkdir):
            # see if the pylib/System location exists
            basedir = os.path.join(args.basedir, "pylib", "System")
            if not os.path.exists(basedir) or not os.path.isdir(basedir):
                print("The TestDef.py file was not found in the specified base directory,")
                print("and no standard location under the specified base directory",basedir,"exists")
                sys.exit(1)
            else:
                if not os.path.exists(os.path.join(basedir, "TestDef.py")):
                    print("The TestDef.py file was not found in the specified base directory,")
                    print("or any standard location under the specified base directory",basedir)
                    sys.exit(1)
        else:
            if os.path.exists(os.path.join(chkdir, "TestDef.py")):
                basedir = chkdir
            else:
                print("The TestDef.py file was not found in the standard location")
                print("under the specified base directory at",chkdir)
                sys.exit(1)
elif os.path.exists("TestDef.py"):
    # the class file is local to us, so use it
    basedir = "./"
    topdir = basedir
elif os.path.exists("pylib"):
    # we appear to be in the MTT home directory
    basedir = os.path.join("./", "pylib", "System")
    topdir = os.path.join("./", "pylib")
    if not os.path.exists(basedir) or not os.path.isdir(basedir):
        print("The local directory",basedir,"doesn't exist")
        sys.exit(1)
    if not os.path.exists(os.path.join(basedir, "TestDef.py")):
        print("The TestDef.py file was not found in the standard location")
        print("under the specified base directory at",basedir)
        sys.exit(1)
else:
    try:
        # try that location
        basedir = os.path.join(os.environ['MTT_HOME'], "pylib", "System")
        if not os.path.exists(basedir) or not os.path.isdir(basedir):
            print("MTT_HOME points to an invalid location - please correct")
            sys.exit(1)
        topdir = os.path.join(os.environ['MTT_HOME'], "pylib")
    except KeyError:
        # didn't find MTT_HOME in the environment, so
        # next see if $0 is an absolute path
        if os.path.isabs(sys.argv[0]):
            # try that location
            path = os.path.dirname(sys.argv[0])
            basedir = os.path.join(path, "pylib", "System")
            topdir = os.path.join(path, "pylib")
            if not os.path.exists(basedir) or not os.path.isdir(basedir):
                print("A base directory for MTT was not specified, we do not appear")
                print("to be in the MTT home directory, and MTT_HOME has not been")
                print("set in the environment. We cannot continue as we will be")
                print("unable to find the MTT libraries")
                sys.exit(1)
        else:
            print("A base directory for MTT was not specified, we do not appear")
            print("to be in the MTT home directory, and MTT_HOME has not been")
            print("set in the environment. We cannot continue as we will be")
            print("unable to find the MTT libraries")
            sys.exit(1)

# if they want debug, set the logging level
if (args.debug):
    logging.basicConfig(level=logging.DEBUG)

# load the "testdef" Test Definition class so we can
# begin building this test
try:
    m = imp.load_source("TestDef", os.path.join(basedir, "TestDef.py"))
except ImportError:
    print("ERROR: unable to load TestDef that must contain the Test Definition object")
    exit(1)
cls = getattr(m, "TestDef")
a = cls()

# create the Test Definition object and set the
# options and arguments
# create the scratch directory
testDef = a.__class__();
testDef.setOptions(args)

# load the plugins for this test
testDef.loadPlugins(basedir, topdir)

# provide an opportunity to print various requested
# outputs before starting to process the test
testDef.printInfo()

# if they didn't specify any files, then there is nothing
# for us to do
if not args.ini_files or not args.ini_files[0]:
    sys.exit('MTT requires at least one test-specification file')

# sanity check a couple of options
if args.section and args.skipsections:
    print("ERROR: Cannot both execute specific sections and specify sections to be skipped")
    sys.exit(1)

# open the logging file if given - otherwise, we log
# to stdout
testDef.openLogger()

# Read the input test definition file(s)
testDef.configTest()

# Determine executor to use
if(args.executor is not None):
    if(args.executor == "sequential" or args.executor == "Sequential"):
        testDef.config.set('MTTDefaults', 'executor', 'sequential')
        status = testDef.executeTest()
    elif(args.executor == "combinatorial" or args.executor == "Combinatorial"):
        testDef.config.set('MTTDefaults', 'executor', 'combinatorial')
        status = testDef.executeCombinatorial()
    else:
        print("Specified executor ", args.executor, " not found!")
        sys.exit(1)
    # All done!
    sys.exit(status)

elif(testDef.config.has_option('MTTDefaults', 'executor')):
    if (testDef.config.get('MTTDefaults', 'executor') == "sequential" or testDef.config.get('MTTDefaults', 'executor') == "Sequential"):
        status = testDef.executeTest()
    elif (testDef.config.get('MTTDefaults', 'executor') == "combinatorial" or testDef.config.get('MTTDefaults', 'executor') == "Combinatorial"):
        status = testDef.executeCombinatorial()
    else:
        print("Specified executor ", testDef.config.get('MTTDefaults', 'executor'), " not found!")
        sys.exit(1)  
    # All done!
    sys.exit(status)

# If no executor is specified default to sequential
else:
    testDef.config.set('MTTDefaults', 'executor', 'sequential')
    status = testDef.executeTest()  
# All done!
    sys.exit(status)
