# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2018 Intel, Inc.  All rights reserved.
# Copyright (c) 2017-2018 Los Alamos National Security, LLC. All rights
#                         reserved.
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
from urllib.parse import urlparse
from FetchMTTTool import *
from distutils.spawn import find_executable
import requests
import sys
import shutil

## @addtogroup Tools
# @{
# @addtogroup Fetch
# @section OMPI_Snapshot
# Plugin for getting software via OMPI Nightly tarballs
# @param url            URL to access the OMPI nightly tarball (e.g. https://www.open-mpi.org/nightly/v2.x)
# @param version_file   optional file containing name of most recent tarball version tested
# @param mpi_name       optional name for the OMPI snapshot tarball
# @}
class OMPI_Snapshot(FetchMTTTool):

    def __init__(self):
        # initialise parent class
        FetchMTTTool.__init__(self)
        self.activated = False
        # track the repos we have processed so we
        # don't do them multiple times
        self.done = {}
        self.options = {}
        self.options['url'] = (None, "URL to access the repository")
        self.options['version_file'] = (None, "File containing name of most recent tarball version tested")
        self.options['mpi_name'] = (None, "Name of OMPI tarball being tested")
        return

    def activate(self):
        if not self.activated:
            # use the automatic procedure from IPlugin
            IPlugin.activate(self)
        return

    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "OMPI_Snapshot"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("OMP_Snapshot Execute")
        # parse any provided options - these will override the defaults
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        # check that they gave us a URL
        try:
            if cmds['url'] is not None:
                url = cmds['url']
        except KeyError:
            log['status'] = 1
            log['stderr'] = "No repository URL was provided"
            return
        testDef.logger.verbose_print("Download OMPI url " + url)
        # get the tarball snapshot name, e.g. v2.x-201711210241-e92a637
        snapshot_url = url + '/latest_snapshot.txt'
        try:
            snapshot_req = requests.get(snapshot_url)
#           Assumes the error is HTTPError
#           Then raise HTTP status error response
            snapshot_req.raise_for_status()
        except requests.exceptions.HTTPError as error:
            testDef.logger.verbose_print("HTTP Error: ",error)
            log['status'] = 1
            log['stderr'] = "HTTP error"
            sys.exit(-1)
        except requests.exceptions.ConnectionError as connection_error:
            testDef.logger.verbose_print("Error connecting: ", connection_error)
            log['status'] = 1
            log['stderr'] = "Error connecting"
            sys.exit(-1)
        except requests.exceptions.Timeout:
            testDef.logger.verbose_print("Timeout error ")
            log['status'] = 1
            log['stderr'] = "Timeout error"
            sys.exit(-1)
        except requests.exceptions.RequestException as base_class_error:
            testDef.logger.verbose_print("An error occured: ", base_class_error)
            log['status'] = 1
            log['stderr'] = "An error occured"
            sys.exit(-1)

        # check to see if we have already processed this tarball
        try:
            if cmds['version_file'] is not None:
                if os.path.exists(cmds['version_file']):
                    try:
                        f = open(cmds['version_file'], 'r')
                        last_version = f.readline().strip()
                        f.close()
                        if last_version == snapshot_req.text.strip():
                            log['status'] = 1
                            log['stderr'] = "No new tarballs to test"
                            testDef.logger.verbose_print("No new tarballs to test")
                            return
                    except IOError:
                        log['status'] = 1
                        log['stderr'] = "An error occurred reading version file: " + cmds['version_file']
                        testDef.logger.verbose_print("An error occurred reading version file: " + cmds['version_file'])
                        return
                else:
                    testDef.logger.verbose_print("Version file does not exist")
                    pass
        except KeyError:
            pass

        # build the tarball name, using a base and then full name
        tarball_base_name = 'openmpi-' + snapshot_req.text.strip()
        tarball_name = tarball_base_name + '.tar.gz'
        download_url = url + '/' + tarball_name

        try:
            if self.done[tarball_base_name] is not None:
                log['status'] = self.done[tarball_base_name][0]
                log['location'] = self.done[tarball_base_name][1]
                return
        except KeyError:
            pass
        # now look for the executable in our path
        if not find_executable("curl"):
            log['status'] = 1
            log['stderr'] = "curl command not found"
            return

        # record our current location
        cwd = os.getcwd()

        dst = os.path.join(testDef.options['scratchdir'], log['section'].replace(":","_"))
        try:
            if not os.path.exists(dst): os.mkdir(dst)
        except:
            log['status'] = 1
            log['stderr'] = "Unable to create " + dst
            return

        # change to the scratch directory
        os.chdir(dst)
        # see if this software has already been cloned
        if os.path.exists(tarball_base_name):
            if not os.path.isdir(tarball_base_name):
                log['status'] = 1
                log['stderr'] = "Cannot update requested OMPI tarball as a file of that name already exists".format(tarball_base_name)
                # track that we serviced this one
                self.done.append((tarball_base_name, 1))
                return
            # if they want us to leave it as-is, then we are done
            try:
                if cmds['asis']:
                    status = 0
                    stdout = None
                    stderr = None
            # If not as-is clear directory and download the tarball
            except KeyError:
                shutil.rmtree(tarball_base_name)
                # download the tarball - TODO probably need to do a try on these
                testDef.logger.verbose_print("downloading tarball " + tarball_name + "url: " + download_url)
                status, stdout, stderr, _ = testDef.execmd.execute(None, ["curl", "-o", tarball_name, download_url], testDef)
                if 0 != status:
                    log['status'] = 1
                    log['stderr'] = "download for tarball " + tarball_name + "url: " + download_url + "FAILED"
                    return
                # untar the tarball
                testDef.logger.verbose_print("untarring tarball " + tarball_name)
                status, stdout, stderr, _ = testDef.execmd.execute(None, ["tar", "-zxf", tarball_name], testDef)
                if 0 != status:
                    log['status'] = 1
                    log['stderr'] = "untar of tarball " + tarball_name + "FAILED"
                    return
        else:
            # download the tarball - TODO probably need to do a try on these
            testDef.logger.verbose_print("downloading tarball " + tarball_name + "url: " + download_url)
            status, stdout, stderr, _ = testDef.execmd.execute(None, ["curl", "-o", tarball_name, download_url], testDef)
            if 0 != status:
                log['status'] = 1
                log['stderr'] = "download for tarball " + tarball_name + "url: " + download_url + "FAILED"
                return
            # untar the tarball
            testDef.logger.verbose_print("untarring tarball " + tarball_name)
            status, stdout, stderr, _ = testDef.execmd.execute(None, ["tar", "-zxf", tarball_name], testDef)
            if 0 != status:
                log['status'] = 1
                log['stderr'] = "untar of tarball " + tarball_name + "FAILED"
                return
        # move into the resulting directory
        os.chdir(tarball_base_name)
        # record the result
        log['status'] = status
        log['stdout'] = stdout
        log['stderr'] = stderr
        log['mpi_info'] = {'name' : cmds['mpi_name'], 'version' : snapshot_req.text.strip()}
        testDef.logger.verbose_print("setting mpi_info to " + str(log.get('mpi_info')))

        # log our absolute location so others can find it
        log['location'] = os.getcwd()
        # track that we serviced this one
        self.done[tarball_base_name] = (status, log['location'])
        # update version file if we're using one
        try:
            if cmds['version_file'] is not None:
                try:
                    f = open(cmds['version_file'], 'w')
                    print(snapshot_req.text.strip(), file=f)
                except:
                    log['status'] = 1
                    log['stderr'] = "FAILED to update version file"
                    testDef.logger.verbose_print("FAILED TO UPDATE VERSION FILE - EXITING")
                    os.chdir(cwd)
                    return
        except KeyError:
            pass
        # change back to the original directory
        os.chdir(cwd)

        return
