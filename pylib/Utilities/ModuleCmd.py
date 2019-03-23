#!/usr/bin/env python
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
import sys
import select
import os
from io import StringIO
from BaseMTTUtility import *

## @addtogroup Utilities
# @{
# @section ModuleCmd
# Load/Unload an environmental module
# @}
class ModuleCmd(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        self.env_module_wrapper = None
        self.env_module_link = None
        self.options = {}
        return

    def print_name(self):
        return "ModuleCmd"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def setCommand(self, options):
        # Check first if the --env-module-wrapper switch was used.  If not, then check for the LMOD_PKG environment variable.
        if options['env_module_wrapper'] is not None:
            self.env_module_wrapper = options['env_module_wrapper']
            if not os.path.isfile(self.env_module_wrapper):
                if options['verbose'] or options['debug'] :
                    print("Environment module python wrapper not found: " + self.env_module_wrapper)
                return
        else:
            try:
                mod_pkg = os.environ['MODULESHOME']
                if os.path.isfile(os.path.join(mod_pkg, "init/env_modules_python.py")) :
                   self.env_module_wrapper = os.path.join(mod_pkg, "init/env_modules_python.py")
                elif os.path.isfile(os.path.join(mod_pkg, "init/python.py")) :
                   self.env_module_wrapper = os.path.join(mod_pkg, "init/python.py")
                else:
                   if options['verbose'] or options['debug'] :
                       print("The --env-module-wrapper switch was not used and module python support via os.environ['MODULESHOME']/init/env_modules_python.py was not found")
                   return
            except KeyError:
                if options['verbose'] or options['debug'] :
                    print("The --env-module-wrapper switch was not used and module python support via os.environ['MODULESHOME'] was not found")
                return

        # setting the link variable to the wrapper as we use it in other places
        self.env_module_link = self.env_module_wrapper
        if options['verbose'] or options['debug']:
            print("Using env module wrapper:", self.env_module_link)

        return

    def loadModules(self, modules, testDef):
        # Logging of results from the environment modules usage is the responsibility
        # of the plugin that is making use of this utility.
        if self.env_module_wrapper is None:
            # cannot perform this operation
            return (1, None, "Module capability was not found")

        # Load the python module() definition
        sys.path.insert(0, os.path.dirname(self.env_module_link))
        try:
            from env_modules_python import module
        except:
            return (1, None, "No module named env_modules_python found")

        # We have to run this in the same python context for it to take effect and be propagated to future children
        # Redirect the sys.stdout and sys.stderr for the module loads and unloads.
        saved_stdout = sys.stdout
        saved_stderr = sys.stderr
        load_stdout = sys.stdout = StringIO()
        load_stderr = sys.stderr = StringIO()

        for mod in modules:
            mod = mod.strip()
            try:
                module("load", mod)
            except:
                # If a module name is not found the module python flow will trigger this exception.
                return (1, None, "Attempt to load environment module " + mod + " failed")

        # Restore sys.stdout and sys.stderr
        sys.stdout = saved_stdout
        sys.stderr = saved_stderr

        status = load_stderr.seek(0, os.SEEK_END)
        stdout = load_stdout.getvalue()
        stderr = load_stderr.getvalue()
        load_stdout.close()
        load_stderr.close()
        return (status, stdout, stderr)

    def unloadModules(self, modules, testDef):
        if self.env_module_wrapper is None:
            # cannot perform this operation
            return (1, None, "Module capability was not found")

        # Load the python module() definition
        sys.path.insert(0, os.path.dirname(self.env_module_link))
        try:
            from env_modules_python import module
        except:
            return (1, None, "No module named env_modules_python found")

        # We have to run this in the same python context for it to take effect and be propagated to future children
        # Redirect the sys.stdout and sys.stderr for the module loads and unloads.
        saved_stdout = sys.stdout
        saved_stderr = sys.stderr
        unload_stdout = sys.stdout = StringIO()
        unload_stderr = sys.stderr = StringIO()

        for mod in modules:
            mod = mod.strip()
            try:
                module("unload", mod)
            except:
                # Unlike the load, the module python flow will not cause an exception if the module can not be found.
                # Add this to catch any other unexpected exceptions.
                return (1, None, "Attempt to unload environment module " + mod + " failed")

        # Restore sys.stdout and sys.stderr
        sys.stdout = saved_stdout
        sys.stderr = saved_stderr

        status = unload_stderr.seek(0, os.SEEK_END)
        stdout = unload_stdout.getvalue()
        stderr = unload_stderr.getvalue()
        unload_stdout.close()
        unload_stderr.close()
        return (status, stdout, stderr)

    def swapModules(self, modules, testDef):
        if self.env_module_wrapper is None:
            # cannot perform this operation
            return (1, None, "Module capability was not found")

        # Load the python module() definition
        sys.path.insert(0, os.path.dirname(self.env_module_link))
        try:
            from env_modules_python import module
        except:
            return (1, None, "No module named env_modules_python found")

        # We have to run this in the same python context for it to take effect and be propagated to future children
        # Redirect the sys.stdout and sys.stderr for the module loads and unloads.
        saved_stdout = sys.stdout
        saved_stderr = sys.stderr
        unload_stdout = sys.stdout = StringIO()
        unload_stderr = sys.stderr = StringIO()

        try:
            module("swap", ' '.join(modules))
        except:
            # Unlike the load, the module python flow will not cause an exception if the module can not be found.
            # Add this to catch any other unexpected exceptions.
            return (1, None, "Environment module swap " + modules[0] + " " + modules[1] + " failed")

        # Restore sys.stdout and sys.stderr
        sys.stdout = saved_stdout
        sys.stderr = saved_stderr

        status = unload_stderr.seek(0, os.SEEK_END)
        stdout = unload_stdout.getvalue()
        stderr = unload_stderr.getvalue()
        unload_stdout.close()
        unload_stderr.close()
        return (status, stdout, stderr)

    def applyModules(self, section, cmds, testDef):
        # Check for requested module settings
        status = 0
        stdout = []
        stderr = []

        try:
            modules_unload = cmds['modules_unload']
        except KeyError:
            pass
        try:
            modules = cmds['modules']
        except KeyError:
            pass
        try:
            modules_swap = cmds['modules_swap']
        except KeyError:
            pass

        if modules_unload is not None or modules is not None or modules_swap is not None:
            if testDef.modcmd is None:
                # cannot execute this request
                return (1,stdout,"No module support available")

        if modules_unload is not None:
            # create a list of the requested modules for unload
            mods = modules_unload.split()
            # have them unloaded
            status,stdout,stderr = testDef.modcmd.unloadModules(mods, testDef)
            if not status:
                # Record this in the global testDef dictionary
                testDef.module_unload[section] = mods
                testDef.logger.verbose_print("ModuleCmd:applyModules: executed module unload " + modules_unload)

        if modules is not None:
            # create a list of the requested modules
            mods = modules.split()
            # have them loaded
            status,stdout,stderr = testDef.modcmd.loadModules(mods, testDef)
            if not status:
                # Record this in the global testDef dictionary
                testDef.module_load[section] = mods
                testDef.logger.verbose_print("ModuleCmd:applyModules: executed module load " + modules)

        if modules_swap is not None:
            # create a list of the requested modules
            mods = modules_swap.split()
            # have them loaded
            status,stdout,stderr = testDef.modcmd.swapModules(mods, testDef)
            if not status:
                # Record this in the global testDef dictionary
                testDef.module_swap[section] = mods
                testDef.logger.verbose_print("ModuleCmd:applyModules: executed module swap " + modules_swap)

        return (status,stdout,stderr)

    def revertModules(self, section, testDef):
        # Undo any environment modules changes in the reverse order they were applied
        status = 0
        stdout = []
        stderr = []

        try:
            mods = testDef.module_swap[section]
            if mods is not None:
                # Swap them back
                mods.reverse()
                status,stdout,stderr = testDef.modcmd.swapModules(mods, testDef)
            if not status:
                testDef.logger.verbose_print("ModuleCmd:revertModules: executed module swap " + " ".join(mods))
        except KeyError:
            pass

        try:
            mods = testDef.module_load[section]
            if mods is not None:
                status,stdout,stderr = testDef.modcmd.unloadModules(mods, testDef)
            if not status:
                testDef.logger.verbose_print("ModuleCmd:revertModules: executed module unload " + " ".join(mods))
        except KeyError:
            pass

        try:
            mods = testDef.module_unload[section]
            if mods is not None:
                status,stdout,stderr = testDef.modcmd.loadModules(mods, testDef)
            if not status:
                testDef.logger.verbose_print("ModuleCmd:revertModules: executed module load " + " ".join(mods))
        except KeyError:
            pass

        return (status,stdout,stderr)

    def checkForModules(self, section, log_to_check, cmds, testDef):
        # Check for module requests from a build or middleware stage
        try:
            if log_to_check['parameters'] is not None:
                for md in log_to_check['parameters']:
                    if "modules_unload" == md[0]:
                        try:
                            if cmds['modules_unload'] is not None:
                                # append these modules_unload to those
                                added_mods = md[1].split(',')
                                existing_mods = cmds['modules_unload'].split(',')
                                for md in existing_mods:
                                    added_mods.append(md)
                                cmds['modules_unload'] = ' '.join(added_mods)
                            else:
                                cmds['modules_unload'] = md[1]
                        except KeyError:
                            cmds['modules_unload'] = md[1]
                    if "modules" == md[0]:
                        try:
                            if cmds['modules'] is not None:
                                # append these modules to those
                                added_mods = md[1].split(',')
                                existing_mods = cmds['modules'].split(',')
                                for md in existing_mods:
                                    added_mods.append(md)
                                cmds['modules'] = ' '.join(added_mods)
                            else:
                                cmds['modules'] = md[1]
                        except KeyError:
                            cmds['modules'] = md[1]
                    if "modules_swap" == md[0]:
                        try:
                            if cmds['modules_swap'] is not None:
                                # modules_swap does not support more than one pair of modules to swap
                                return (1, [], [section, " middleware usage of modules_swap and Autotools plugin usage of module_swap is not supported"], 0)
                            else:
                                cmds['modules_swap'] = md[1]
                        except KeyError:
                            cmds['modules_swap'] = md[1]
        except KeyError:
            pass

        return (0, [] ,[])
