#!/usr/bin/env python
#
# Copyright (c) 2015-2017 Intel, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
import os
import re
from HarasserMTTTool import *
import datetime
import multiprocessing
import sys

## @addtogroup Tools
# @{
# @addtogroup Harasser
# @section Harasser
# @param trigger_scripts      Scripts to run to launch harassers
# @param stop_scripts         Scripts to run to stop and clean-up harassers
# @param join_timeout         Seconds to wait for process to finish
# @}
class Harasser(HarasserMTTTool):
    def __init__(self):
        HarasserMTTTool.__init__(self)
        self.activated = False
        self.execution_counter = 0
        self.testDef = None
        self.running_harassers = {}
        self.options = {}
        self.options['trigger_scripts'] = (None, "Scripts to run to launch harassers")
        self.options['stop_scripts'] = (None, "Scripts to run to stop and clean-up harassers")
        self.options['join_timeout'] = (None, "Seconds to wait for processes to finish")
        return

    def config(self, cfg):
        """Configures plugin outside of INI file
        """
        for k in cfg:
            if k in self.options:
                self.options[k] = (cfg[k], self.options[k][1])

    def activate(self):
        """Activates plugin
        """
        if not self.activated:
            # use the automatic procedure from IPlugin
            IPlugin.activate(self)
            self.activated = True
        return

    def deactivate(self):
        """Deactivates plugin
        """
        if self.activated:
            IPlugin.deactivate(self)
            self.activated = False
            if self.execution_counter > 0:
                self.testDef.logger.verbose_print("Harasser plugin stopped while harassers were running. Cleaning up harassers...")
                self.stop(self.running_harassers.keys(), self.testDef)
                self.testDef.logger.verbose_print("Harassers were cleaned up.")
        return

    def print_name(self):
        return "Harasser"

    def print_options(self, testDef, prefix):
        """Prints current configuration of plugin
        """
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def get_running_harassers(self):
        """Returns information about what harassers are currently running
        """
        return self.running_harassers

    def parallel_execute(self, cmds, cmdargs, testDef):
        """This function is passed into multiprocessing as a target
        """
        status,stdout,stderr,time = testDef.execmd.execute(cmds, cmdargs, testDef)

    def start(self, testDef):
        """Harassment is started on the system
        """
        # Parse input for lists of scripts to run
        trigger_scripts = self.options['trigger_scripts'][0]
        if trigger_scripts is None or trigger_scripts == '':
            trigger_scripts = []
        else:
            trigger_scripts = trigger_scripts.split(',')
        stop_scripts = self.options['stop_scripts'][0]
        if stop_scripts is None or stop_scripts == '':
            stop_scripts = []
        else:
            stop_scripts = stop_scripts.split(',')

        # Execute scripts while pairing which scripts
        # are used to stop/cleanup each start script
        exec_ids = []
        for trigger_script,stop_script in zip(trigger_scripts,stop_scripts):
            trigger_script = trigger_script.strip()
            stop_script = stop_script.strip()
            ops = {(k[:-1] if k.endswith('_scripts') else k):\
                   (trigger_script if k == 'trigger_scripts' else (\
                    stop_script if k == 'stop_scripts' \
                    else v[0])) \
                   for k,v in self.options.items()}

            cmdargs = trigger_script.split()

            process = multiprocessing.Process(name='p'+str(self.execution_counter), \
                            target=self.parallel_execute, \
                            args=({k:v[0] for k,v in self.options.items()},cmdargs,testDef))
            process.start()
            
            self.running_harassers[self.execution_counter] = (process, ops, datetime.datetime.now())
            exec_ids.append(self.execution_counter)
            self.execution_counter += 1

        return exec_ids

    def check(self, exec_ids, testDef):
        """A check to see if harassers are working properly
        """
        dead_processes = []
        for exec_id in exec_ids:
            if not self.running_harassers[exec_id][0].is_alive() \
                and self.running_harassers[exec_id][0].exitcode != 0:
                dead_processes.append(self.running_harassers[exec_id])
        if dead_processes:
            process_run_info = self.stop(exec_ids, testDef)
            return dead_processes, process_run_info
        return None

    def stop(self, exec_ids, testDef):
        """Calls the stop-scripts provided with harasser scripts to stop and clean up harassment
        """
        process_info = [self.running_harassers[exec_id] for exec_id in exec_ids]
        for exec_id in exec_ids:
            del self.running_harassers[exec_id]

        return_info = []
        for process,ops,starttime in process_info:
            cmdargs = ops['stop_script'].split()
            status,stdout,stderr,time = testDef.execmd.execute({k:v[0] for k,v in self.options.items()}, cmdargs, testDef)
            return_info.append((status,stdout,stderr,datetime.datetime.now()-starttime))

        for (process,ops,starttime),(status,stdout,stderr,time) in zip(process_info,return_info):
            if status == 0:
                if self.options['join_timeout'][0] is None:
                    process.join()
                else:
                    process.join(int(self.options['join_timeout'][0]))
            elif status == 1:
                process.terminate()

            self.execution_counter -= 1

        return return_info

    def execute(self, log, keyvals, testDef):
        """Configure the harasser plugin on whether to run and what to run
        """
        testDef.logger.verbose_print("Harasser Execute")

        self.testDef = testDef

        try:
            if log['section'] is not None:
                if "Default" in log['section']:
                    # this section contains default settings
                    # for this launcher
                    myopts = {}
                    testDef.parseOptions(log, self.options, keyvals, myopts)
                    # transfer the findings into our local storage
                    keys = list(self.options.keys())
                    optkeys = list(myopts.keys())
                    for optkey in optkeys:
                        for key in keys:
                            if key == optkey:
                                self.options[key] = (myopts[optkey],self.options[key][1])

                    # we captured the default settings, so we can
                    # now return with success
                    log['status'] = 0
                    return
        except KeyError:
            # error - the section should have been there
            log['status'] = 1
            log['stderr'] = "Section not specified"
            return

        log['status'] = 1
        log['stderr'] = "Must be used in a Default stage"

