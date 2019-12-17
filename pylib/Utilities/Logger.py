
from builtins import str
#!/usr/bin/env python
#
# Copyright (c) 2015-2018 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import sys
import datetime
from BaseMTTUtility import *
import json
import os
import pwd
import grp

## @addtogroup Utilities
# @{
# @section Logger
# Log results and provide debug output when directed
# @}
class Logger(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        self.fh = sys.stdout
        self.results = []
        self.options = {}
        self.printout = False
        self.timestamp = False
        self.cmdtimestamp = False
        self.timestampeverything = False
        self.stage_start = {}
        self.elk_log = None
        self.current_section = None
        self.execmds_stash = []

    def reset(self):
        self.results = []
        self.stage_start = {}

    def print_name(self):
        return "Logger"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
            sys.stdout.flush()
        return

    def open(self, testDef):
        # init the logging file handle
        try:
            if testDef.options['logfile'] is not None:
                self.fh = open(testDef.options['logfile'], 'w')
            else:
                self.fh = sys.stdout
        except KeyError:
            self.fh = sys.stdout
        # define the verbosity/debug flags
        try:
            if testDef.options['verbose']:
                self.printout = True
        except KeyError:
            pass
        try:
            if testDef.options['extraverbose']:
                self.printout = True
                self.timestamp = True
                self.cmdtimestamp = True
                self.timestampeverything = True
        except KeyError:
            pass
        try:
            if testDef.options['debug']:
                self.printout = True
        except KeyError:
            pass
        try:
            if testDef.options['dryrun']:
                self.printout = True
        except KeyError:
            pass
        # define the time flags
        try:
            if testDef.options['cmdtime']:
                self.timestamp = True
                self.cmdtimestamp = True
        except KeyError:
            pass
        try:
            if testDef.options['time']:
                self.timestamp = True
                self.cmdtimestamp = True
        except KeyError:
            pass
        return

    def get_dict_contents(self, dic):
        return self.get_tuplelist_contents(list(dic.items()))

    def get_tuplelist_contents(self, tuplelist):
        if not tuplelist:
            return []
        max_keylen = max([len(key) for key,_ in tuplelist])
        return ["%s = %s" % (k.rjust(max_keylen), o) for k,o in tuplelist]

    def log_to_elk(self, result, logtype, testDef):
        result = result.copy()
        if testDef.options['elk_head'] is None or testDef.options['elk_id'] is None:
            self.verbose_print('Error: entered log_to_elk() function without elk_id and elk_head specified')
            return

        result = {k:(str(v) if isinstance(v, datetime.datetime)
                            or isinstance(v, datetime.date) else v)
                  for k,v in list(result.items())}
        result['execid'] = testDef.options['elk_id']
        result['cycleid'] = testDef.options['elk_testcycle']
        result['caseid'] = testDef.options['elk_testcase']
        result['logtype'] = logtype

        # drop the stderr and stdout, will use the copies that are part of the commands issues
        if 'stderr' in result:
            del result['stderr']
        if 'stdout' in result:
            del result['stdout']

        # convert ini_files, lists of lists into a comma separated string
        if 'options' in result and 'ini_files' in result['options']:
            result['options']['ini_files'] = ','.join(t[0] for t in result['options']['ini_files'])

        if logtype == 'mtt-sec':
            # convert comamands, list of dicts into a dictionary
            if self.execmds_stash:
                result['commands'] = {"command{}".format(i):c for i,c in enumerate(self.execmds_stash)}
                self.execmds_stash = []

            # convert parameters, list of lists into a dictionary
            if 'parameters' in result:
                result['parameters'] = { p[0]:p[1] for p in result['parameters'] }

            # convert profile, list of lists into a dictionary
            if 'profile' in result:
                result['profile'] = { k:' '.join(v) for k,v in list(result['profile'].items()) }

        if testDef.options['elk_debug']:
            self.verbose_print('Logging to elk_head={}/{}.elog: {}'.format(testDef.options['elk_head'], testDef.options['elk_id'], result))

        if self.elk_log is None:
            allpath = '/'
            for d in os.path.normpath(testDef.options['elk_head']).split(os.path.sep):
                allpath = os.path.join(allpath, d)
                if not os.path.exists(allpath):
                    os.mkdir(allpath)
                    uid = None
                    gid = None
                    if testDef.options['elk_chown'] is not None and ':' in testDef.options['elk_chown']:
                        user = testDef.options['elk_chown'].split(':')[0]
                        group = testDef.options['elk_chown'].split(':')[1]
                        uid = pwd.getpwnam(user).pw_uid
                        gid = grp.getgrnam(group).gr_gid
                        os.chown(allpath, uid, gid)
            self.elk_log = open(os.path.join(testDef.options['elk_head'], '{}-{}.elog'.format(testDef.options['elk_testcase'], testDef.options['elk_id'])), 'a+')
        self.elk_log.write(json.dumps(result) + '\n')
        return

    def print_cmdline_args(self, testDef):
        if not (testDef and testDef.options):
            print("Error: print_cmdline_args was called too soon. Continuing...")
            sys.stdout.flush()
            return
        header_to_print = "CMDLINE_ARGS"
        strs_to_print = self.get_dict_contents(testDef.options)
        self.verbose_print("="*max([len(header_to_print),len(strs_to_print[0])]))
        self.verbose_print(header_to_print)
        self.verbose_print("="*max([len(header_to_print),len(strs_to_print[0])]))
        for s in strs_to_print:
            self.verbose_print(s)
        self.verbose_print("")
        if testDef.options['elk_id'] is not None:
            self.log_to_elk({'environment': dict(os.environ), 'options': testDef.options}, 'mtt-env', testDef)

    def log_execmd_elk(self, cmdargs, status, stdout, stderr, timedout, starttime, endtime, elapsed_secs, slurm_job_ids, testDef):
        if testDef.options['elk_id'] is not None:
            if testDef.options['elk_maxsize'] is not None:
                try:
                    maxsize = int(testDef.options['elk_maxsize'])
                except:
                    maxsize = None
                if maxsize is not None and len(stdout) > maxsize:
                    if maxsize > 0:
                        stdout = ['<truncated>'] + stdout[-maxsize:]
                    else:
                        stdout = ['<truncated>']
                if maxsize is not None and len(stderr) > maxsize:
                    if maxsize > 0:
                        stderr = ['<truncated>'] + stderr[-maxsize:]
                    else:
                        stderr = ['<truncated>']
            self.execmds_stash.append({'cmdargs': ' '.join(cmdargs),
                                       'status': status,
                                       'stdout': stdout if testDef.options['elk_nostdout'] is not None else ['<ignored>'],
                                       'stderr': stderr if testDef.options['elk_nostderr'] is not None else ['<ignored>'],
                                       'timedout': timedout,
                                       'starttime': str(starttime),
                                       'endtime': str(endtime),
                                       'elapsed': elapsed_secs,
                                       'slurm_job_ids': ','.join([str(j) for j in slurm_job_ids])
                                      })

    def stage_start_print(self, stagename):
        self.stage_start[stagename] = datetime.datetime.now()
        if self.printout:
            to_print="START EXECUTING [%s] start_time=%s" % (stagename, self.stage_start[stagename])
            self.verbose_print("")
            self.verbose_print("="*len(to_print))
            self.verbose_print(to_print)
            self.verbose_print("="*len(to_print))
        self.current_section = stagename

    def stage_end_print(self, stagename, log):
        stage_end = datetime.datetime.now()
        if self.printout:
            to_print="DONE EXECUTING [%s] end_time=%s, elapsed=%s" % (stagename, stage_end, stage_end-self.stage_start[stagename])
            self.verbose_print(to_print)
            self.verbose_print("STATUS OF [%s] IS %d" % (stagename, log['status']))
            self.verbose_print("")
        log['elapsed'] = (stage_end-self.stage_start[stagename]).total_seconds()
        log['starttime'] = self.stage_start[stagename]
        log['endtime'] = stage_end
        self.current_section = None

    def verbose_print(self, string, timestamp=None):
        if self.printout:
            try:
                print(("%s%s" % ("%s "%(datetime.datetime.now() if timestamp is None else timestamp) \
                            if (self.timestampeverything or timestamp) else "", string)), file=self.fh)
                sys.stdout.flush()
            except UnicodeEncodeError as e:
                print("Error: Could not verbose print due to a UnicodeEncodeError")
                print(e)
                sys.stdout.flush()
            return

    def timestamp(self):
        if self.timestamp:
            return datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    def close(self):
        if self.fh is not sys.stdout:
            self.fh.close()
        return

    def logResults(self, title, result, testDef):
        self.verbose_print("LOGGING results for " + title)
        self.results.append(result)
        if testDef.options['elk_id'] is not None:
            self.log_to_elk(result, 'mtt-sec', testDef)
        return

    def outputLog(self):
        # cycle across the logged results and output
        # them to the logging file
        for result in self.results:
            try:
                if result['status'] is not None:
                    print("Section " + result['section'] + ": Status " + str(result['status']), file=self.fh)
                    sys.stdout.flush()
                    if 0 != result['status']:
                        try:
                            print("    " + result['stderr'], file=self.fh)
                            sys.stdout.flush()
                        except KeyError:
                            pass
            except KeyError:
                print("Section " + result['section'] + " did not return a status", file=self.fh)
                sys.stdout.flush()
        return

    def getLog(self, key):
        # if the key is None, then they want the entire
        # log list
        if key is None:
            return self.results
        # we have been passed the name of a section, so
        # see if we have its log in the results
        for result in self.results:
            try:
                if key == result['section']:
                    return result
            except KeyError:
                pass
        # if we get here, then the key wasn't found
        return None
