#!/usr/bin/env python
#
# Copyright (c) 2016      Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import os
import sys
import Queue
import threading
from CNCMTTTool import *

class workerThread(threading.Thread):
    def __init__(self, threadID, queue, status, lock, testDef):
        threading.Thread.__init__(self)
        self.threadID = threadID
        self.queue = queue
        self.lock = lock
        self.status = status
        self.testDef = testDef
        return

    def run(self):
        self.testDef.logger.verbose_print("IPMITool: Thread " + str(self.threadID) + " is active")
        while True:
            self.lock.acquire()
            if not self.queue.empty():
                task = self.queue.get()
                self.lock.release()
                self.testDef.logger.verbose_print("IPMITool: Thread " + str(self.threadID) + " received task " + ' '.join(task['cmd']))
                # we should have received a dictionary - check for dryrun
                dryrun = False
                try:
                    if task['dryrun']:
                        dryrun = True
                except:
                    pass
                # check the cmd
                try:
                    if task['reset']:
                        if dryrun:
                            # just record a result
                            self.testDef.logger.verbose_print("IPMITool: Thread " + str(self.threadID) + " dryrun reset " + task['target'])
                            self.lock.acquire()
                            self.status.append((0, ' '.join(task['cmd']), None))
                            self.lock.release()
                            continue
                        # ping until we get a response
                        ntries = 0
                        while True:
                            ++ntries
                            status,stdout,stderr = self.testDef.execmd.execute(task['cmd'], testDef)
                            if 0 == status or ntries == task['maxtries']:
                                self.testDef.logger.verbose_print("IPMITool: node " + task['target'] + " is back")
                                break
                        # record the result
                        self.lock.acquire()
                        if 0 != status and ntries >= task['maxtries']:
                            msg = "Operation timed out on node " + task['target']
                            self.status.append((-1, ' '.join(task['cmd']), msg))
                        else:
                            self.status.append((status, ' '.join(task['cmd']), stderr))
                        self.lock.release()
                        continue
                except:
                    try:
                        if task['cmd'] is not None:
                            if dryrun:
                                # just record a result
                                self.testDef.logger.verbose_print("IPMITool: Thread " + str(self.threadID) + " dryrun " + ' '.join(task['cmd']))
                                self.lock.acquire()
                                self.status.append((0, ' '.join(task['cmd']), None))
                                # add reset command if required
                                try:
                                    if task['target'] is not None:
                                        # add the reset command to the queue
                                        ckcmd = {}
                                        ckcmd['reset'] = True
                                        ckcmd['cmd'] = ["ping", "-c", "1", task['target']]
                                        ckcmd['maxtries'] = task['maxtries']
                                        ckcmd['target'] = task['target']  # just for debug purposes
                                        ckcmd['dryrun'] = dryrun
                                        # add it to the queue
                                        self.queue.put(ckcmd)
                                except:
                                    pass
                                self.lock.release()
                                continue
                            # send it off to ipmitool to execute
                            self.testDef.logger.verbose_print("IPMITool: " + ' '.join(task['cmd']))
                            st,stdout,stderr = self.testDef.execmd.execute(task['cmd'], testDef)
                            self.lock.acquire()
                            self.status.append((st, ' '.join(task['cmd']), stderr))
                            try:
                                if task['target'] is not None:
                                    # add the reset command to the queue
                                    ckcmd['reset'] = True
                                    ckcmd['cmd'] = ["ping", "-c", "1", task['target']]
                                    ckcmd['maxtries'] = task['maxtries']
                                    ckcmd['target'] = task['target']  # just for debug purposes
                                    ckcmd['dryrun'] = dryrun
                                    # add it to the queue
                                    self.queue.put(ckcmd)
                            except:
                                pass
                            self.lock.release()
                            continue
                        else:
                            # mark as a bad command
                            self.lock.acquire()
                            self.status.append((2, "NULL", "Missing command"))
                            self.lock.release()
                            continue
                    except:
                        # bad input
                        self.lock.acquire()
                        self.status.append((2, "NULL", "Missing command"))
                        self.lock.release()
                        continue
            else:
                # if the queue is empty, then we are done
                self.lock.release()
                return

## @addtogroup Tools
# @{
# @addtogroup CNC
# @section IPMITool
# @param username      Remote session username
# @param dryrun        Dryrun - print out commands but do not execute
# @param target        List of remote host names or LAN interfaces to monitor during reset operations
# @param numthreads    Number of worker threads to use
# @param controller    List of IP addresses of remote node controllers/BMCs
# @param command       Command to be sent
# @param pwfile        File containing remote session password
# @param password      Remote session password
# @param maxtries      Max number of times to ping each host before declaring reset to fail
# @}
class IPMITool(CNCMTTTool):
    def __init__(self):
        CNCMTTTool.__init__(self)
        self.options = {}
        self.options['target'] = (None, "List of remote host names or LAN interfaces to monitor during reset operations")
        self.options['controller'] = (None, "List of IP addresses of remote node controllers/BMCs")
        self.options['username'] = (None, "Remote controller username")
        self.options['password'] = (None, "Remote controller password")
        self.options['pwfile'] = (None, "File containing remote controller password")
        self.options['command'] = (None, "Command to be sent")
        self.options['maxtries'] = (100, "Max number of times to ping each host before declaring reset to fail")
        self.options['numthreads'] = (30, "Number of worker threads to use")
        self.options['dryrun'] = (False, "Dryrun - print out commands but do not execute")
        self.options['sudo'] = (False, "Use sudo to execute privileged commands")
        self.lock = threading.Lock()
        self.threads = []
        self.threadID = 0
        self.status = []
        return

    def activate(self):
        # use the automatic procedure from IPlugin
        IPlugin.activate(self)
        return

    def deactivate(self):
        IPlugin.deactivate(self)

    def print_name(self):
        return "IPMITool"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("IPMITool execute")
        # check for a modules directive
        mods = None
        try:
            if keyvals['modules'] is not None:
                if testDef.modcmd is None:
                    # cannot execute this request
                    log['stderr'] = "No module support available"
                    log['status'] = 1
                    return
                # create a list of the requested modules
                mods = keyvals['modules'].split(',')
                # have them loaded
                status,stdout,stderr = testDef.modcmd.loadModules(mods, testDef)
                if 0 != status:
                    log['status'] = status
                    log['stdout'] = stdout
                    log['stderr'] = stderr
                    return
                modloaded = True
        except KeyError:
            pass

        # parse what we were given against our defined options
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        testDef.logger.verbose_print("IPMITool: " + ' '.join(cmds))
        # must have given us at least one controller address
        try:
            if cmds['controller'] is None:
                log['status'] = 1
                log['stderr'] = "No target controllers identified"
                return
            else:
                # convert to a list
                controllers = cmds['controller'].split(',')
        except:
            log['status'] = 1
            log['stderr'] = "No target controllers identified"
            return
        # and a command
        try:
            if cmds['command'] is None:
                log['status'] = 1
                log['stderr'] = "No IPMI command given"
                return
        except:
            log['status'] = 1
            log['stderr'] = "No IPMI command given"
            return
        # if this is a reset command, then we must have targets
        # for each controller
        try:
            if cmds['target'] is None:
                log['status'] = 1
                log['stderr'] = "No target nodes identified"
                return
            else:
                # convert it to a list
                targets = cmds['target'].split(",")
                # must match number of controllers
                if len(targets) != len(controllers):
                    log['status'] = 1
                    log['stderr'] = "Number of targets doesn't equal number of controllers"
                    return
                reset = True
        except:
            reset = False
        # Setup the queue - we need a spot for the command to be sent to each
        # identified target. If it is a command that will result in cycling
        # the node, then we need to double it so we can execute the loop of
        # "ping" commands to detect node restart
        if reset:
            ipmiQueue = Queue.Queue(2 * len(controllers))
        else:
            ipmiQueue = Queue.Queue(len(controllers))

        # Fill the queue
        self.lock.acquire()
        for n in range(0, len(controllers)):
            # construct the cmd
            cmd = {}
            ipmicmd = cmds['command'].split()
            ipmicmd.insert(0, "ipmitool")
            if cmds['sudo']:
                ipmicmd.insert(0, "sudo")
            ipmicmd.append("-H")
            ipmicmd.append(controllers[n])
            if cmds['username'] is not None:
                ipmicmd.append("-U")
                ipmicmd.append(cmds['username'])
            if cmds['password'] is not None:
                ipmicmd.append("-P")
                ipmicmd.append(cmds['password'])
            cmd['cmd'] = ipmicmd
            if reset:
                cmd['target'] = targets[n]
                cmd['maxtries'] = cmds['maxtries']
            cmd['dryrun'] = cmds['dryrun']
            # add it to the queue
            ipmiQueue.put(cmd)
        # setup the response
        self.status = []
        # spin up the threads
        self.threads = []
        # release the queue
        self.lock.release()
        if len(targets) < self.options['numthreads']:
            rng = len(targets)
        else:
            rng = self.options['numthreads']
        for n in range(0, rng):
            thread = workerThread(self.threadID, ipmiQueue, self.status, self.lock, testDef)
            thread.start()
            self.threads.append(thread)
            self.threadID += 1
        # wait for completion
        while not ipmiQueue.empty():
            pass
        # wait for all threads to complete/terminate
        for t in self.threads:
            t.join()
        # set our default log
        log['status'] = 0
        log['stdout'] = None
        log['stderr'] = None
        # determine our final status - if any of the steps failed, then
        # set the status to the first one that did
        for st in self.status:
            if 0 != st[0]:
                log['status'] = st[0]
                log['stdout'] = st[1]
                log['stderr'] = st[2]
        # reset modules if necessary
        if mods is not None:
            testDef.modcmd.unloadModules(mods, testDef)
        return
