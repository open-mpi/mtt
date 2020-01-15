
from builtins import str
#!/usr/bin/env python
#
# Copyright (c) 2015-2020 Intel, Inc. All rights reserved.
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
from pathlib import Path
import pwd
import grp

## @addtogroup Utilities
# @{
# @section ElkLogger
# Log results to *.elog files with JSON entries to be later consumed by Elastic Stack (ELK)
# Uses pymtt.py options: elk_head, elk_id, elk_testcycle, elk_testcase, elk_debug, elk_chown, elk_maxsize, elk_nostdout, elk_nostderr 
#
# --elk_testcase specifies which testcase to log results as when using elk-friendly ouput. Also set through environment variable MTT_ELK_TESTCASE
# --elk_testcycle specifies which testcycle to log results as when using elk-friendly output. Also set through environment variable MTT_ELK_TESTCYCLE
# --elk_id specifies which execution id to log results as when using elk-friendly output. Also set through environment variable MTT_ELK_ID
# --elk_head specifies which location to log <caseid>_<elk_id>.elog files for elk_friendly output. Also set through environment variable MTT_ELK_HEAD
# --elk_chown specifies a max number of lines to log for stdout and stderr in elk-friendly output. Also set through environment variable MTT_ELK_CHOWN
# --elk_nostdout specifies whether to include stdout in elk-friendly output. Also set through environment variable MTT_ELK_NOSTDOUT
# --elk_nostderr specifies whether to include stderr in elk-friendly output. Also set through environment variable MTT_ELK_NOSTDERR
# --elk_debug specifies whether to output everything logged to *.elog files to the screen as extra verbose output. Also set through environment variable MTT_ELK_DEBUG
# --elk_hide_execmd comma delimited list of plugins and/or sections to hide execmd output from. Also set through environment variable MTT_ELK_HIDE_EXECMD. Use "Default" to hide execmd output when no plugin is specified.
# @}
class ElkLogger(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        self.options = {}
        self.elk_log = None
        self.execmds_stash = []

    def print_name(self):
        return "ElkLogger"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
            sys.stdout.flush()
        return

    def log_to_elk(self, result, logtype, testDef):
        result = result.copy()
        if testDef.options['elk_head'] is None or testDef.options['elk_id'] is None:
            testDef.logger.verbose_print('Error: entered log_to_elk() function without elk_id and elk_head specified')
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
                # generate list of plugins/sections to hide execmd output for
                if testDef.options['elk_hide_execmd']:
                    elk_hide_execmd = testDef.options['elk_hide_execmd'].lower().split(',')
                else:
                    elk_hide_execmd = []
                # find out what plugin was used
                plugin = 'Default'
                for (p1,p2) in result['parameters']:
                    if p1 == 'plugin':
                        plugin = p2
                        break
                # log execmd output
                if result['section'].lower() not in elk_hide_execmd and plugin.lower() not in elk_hide_execmd:
                    result['commands'] = {"command{}".format(i):c for i,c in enumerate(self.execmds_stash)}
                # clear execmd stash to prepare for next round of plugin execution
                self.execmds_stash = []

            # convert parameters, list of lists into a dictionary
            if 'parameters' in result:
                result['parameters'] = { p[0]:p[1] for p in result['parameters'] }

            # convert profile, list of lists into a dictionary
            if 'profile' in result:
                result['profile'] = { k:' '.join(v) for k,v in list(result['profile'].items()) }

        if testDef.options['elk_debug']:
            testDef.logger.verbose_print('Logging to elk_head={}/{}-{}.elog: {}'.format(testDef.options['elk_head'],
                                                                                        testDef.options['elk_testcase'],
                                                                                        testDef.options['elk_id'], result))

        if self.elk_log is None:
            allpath = '/'
            for d in os.path.normpath(testDef.options['elk_head']).split(os.path.sep):
                allpath = os.path.join(allpath, d)
                if not os.path.exists(allpath):
                    Path(allpath).mkdir(parents=True, exist_ok=True)
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
