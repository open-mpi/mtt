# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2019 Intel, Inc.  All rights reserved.
# Copyright (c) 2019      Triad National Security, LLC. All rights
#                         reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#


import os, shutil
from urllib.parse import urlparse
from FetchMTTTool import *
from distutils.spawn import find_executable

## @addtogroup Tools
# @{
# @addtogroup Fetch
# @section Git
# Plugin for getting software via Git
# @param url         URL to access the repository
# @param username    Username required for accessing the repository
# @param password    Password required for that user to access the repository
# @param pwfile      File where password can be found
# @param branch      Branch (if not master) to be downloaded; mutually exclusive with `commit` and `pr`
# @param commit      Commit (hash prefix, tag or other commit expression) to be downloaded; mutually exclusive with `branch` and `p`
# @param pr          Pull request to be downloaded; mutually exclusive with `branch` and `commit`
# @param subdir      Subdirectory of interest in repository
# @param modules_unload  Modules to unload
# @param modules         Modules to load
# @param modules_swap    Modules to swap
# @param retry           Number of times to retry on failure. Default is 0.
# @}
class Git(FetchMTTTool):

    def __init__(self):
        # initialise parent class
        FetchMTTTool.__init__(self)
        self.activated = False
        # track the repos we have processed so we
        # don't do them multiple times
        self.done = {}
        self.options = {}
        self.options['url'] = (None, "URL to access the repository")
        self.options['recursive'] = (False, "Recursively clone repository")
        self.options['username'] = (None, "Username required for accessing the repository")
        self.options['password'] = (None, "Password required for that user to access the repository")
        self.options['pwfile'] = (None, "File where password can be found")
        self.options['branch'] = (None, "Branch (if not master) to be downloaded; mutually exclusive with `commit` and `pr`")
        self.options['commit'] = (None, "Commit (hash prefix, tag or other commit expression) to be downloaded; mutually exclusive with `branch` and `pr`")
        self.options['pr'] = (None, "Pull request to be downloaded; mutually exclusive with `branch` and `commit`")
        self.options['subdir'] = (None, "Subdirectory of interest in repository")
        self.options['modules'] = (None, "Modules to load")
        self.options['modules_unload'] = (None, "Modules to unload")
        self.options['modules_swap'] = (None, "Modules to swap")
        self.options['retry'] = (0, "Number of times to retry on failure. Default is 0.")
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
        return "Git"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("Git Execute")
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
        testDef.logger.verbose_print("Working repo " + url)
        recursive = ""
        if cmds['recursive']:
            recursive = "--recurse-submodules"
            testDef.logger.verbose_print("Will attempt to recursively cloning repository")
        else:
            recursive = ""
            testDef.logger.verbose_print("Will not attempt to recursively cloning repository")
        testDef.logger.verbose_print("recurisve log: " + recursive)

        username = cmds['username']
        password = None
        # see if they gave us a password
        try:
            if cmds['password'] is not None:
                password = cmds['password']
            else:
                try:
                    if cmds['pwfile'] is not None:
                        if os.path.exists(cmds['pwfile']):
                            f = open(cmds['pwfile'], 'r')
                            password = f.readline().strip()
                            f.close()
                        else:
                            log['status'] = 1
                            log['stderr'] = "Password file " + cmds['pwfile'] + " does not exist"
                            return
                except KeyError:
                    pass
        except KeyError:
            # if not, did they give us a file where we can find the password
            try:
                if cmds['pwfile'] is not None:
                    if os.path.exists(cmds['pwfile']):
                        f = open(cmds['pwfile'], 'r')
                        password = f.readline().strip()
                        f.close()
                    else:
                        log['status'] = 1
                        log['stderr'] = "Password file " + cmds['pwfile'] + " does not exist"
                        return
            except KeyError:
                pass
        # check for sanity - if a password was given, then
        # we must have a username
        if password is not None:
            if username is None:
                log['status'] = 1
                log['stderr'] = "Password without username"
                return
            # find the "//"
            (leader,tail) = url.split("//", 1)
            # put the username:password into the url
            url = leader + "//" + username + ":" + password + "@" + tail
        elif username is not None:
            # find the "//"
            (leader,tail) = url.split("//", 1)
            # put the username:password into the url
            url = leader + "//" + username + "@" + tail
        testDef.logger.verbose_print("Working final repo " + url)
        # the path component of the parser output contains
        # the name of the repo
        repo = os.path.basename(urlparse(url).path)
        # check for edge case of path ending in .git
        if repo.endswith(".git"):
            repo = repo[0:len(repo)-4]

        dst = os.path.join(testDef.options['scratchdir'], log['section'].replace(":","_"))
        repo = os.path.join(dst, repo)

        # Apply any requested environment module settings
        status,stdout,stderr = testDef.modcmd.applyModules(log['section'], cmds, testDef)
        if 0 != status:
            log['status'] = status
            log['stdout'] = stdout
            log['stderr'] = stderr
            return

        # now look for the executable in our path
        if not find_executable("git"):
            log['status'] = 1
            log['stderr'] = "Executable git not found"
            return
        # see if they asked for a specific branch
        branch = None
        try:
            if cmds['branch'] is not None:
                branch = cmds['branch']
        except KeyError:
            pass
        # or if they asked for a specific commit
        commit = None
        try:
            if cmds['commit'] is not None:
                commit = cmds['commit']
        except KeyError:
            pass
        # or if they asked for a specific PR
        pr = None
        try:
            if cmds['pr'] is not None:
                pr = cmds['pr']
        except KeyError:
            pass
        # cannot have more than one
        if (1 if branch is not None else 0) + (1 if commit is not None else 0) + (1 if pr is not None else 0) > 1:
            log['status'] = 1
            log['stderr'] = "Cannot specify more than one of a branch, a commit, and a PR"
            return

        # see if we have already serviced this one
        try:
            rep = self.done[repo]
            if 0 != rep['status']:
                log['status'] = rep['status']
                log['stderr'] = "Prior attempt to clone or update repo {0} failed".format(repo)
                return
            # log the status
            log['status'] = rep['status']
            log['hash'] = rep['hash']
            # set the location
            try:
                try:
                    sbd = rep['subdir']
                    log['location'] = rep['location'][:-(len(sbd))]
                except:
                    log['location'] = rep['location']
                if cmds['subdir'] is not None:
                    # check that this subdirectory actually exists
                    ckdir = os.path.join(log['location'], cmds['subdir'])
                    if not os.path.exists(ckdir):
                        log['status'] = 1
                        log['stderr'] = "Subdirectory " + cmds['subdir'] + " was not found"
                        return
                    if not os.path.isdir(ckdir):
                        log['status'] = 1
                        log['stderr'] = "Subdirectory " + cmds['subdir'] + " is not a directory"
                        return
                    log['location'] = ckdir
            except:
                pass
            if branch is not None:
                try:
                    if branch == rep['branch']:
                        return
                except:
                    pass
            elif commit is not None:
                try:
                    if commit == rep['commit']:
                        return
                except:
                    pass
            elif pr is not None:
                try:
                    if pr == rep['pr']:
                        return
                except:
                    pass
            else:
                 return
        except:
            pass

        # record our current location
        cwd = os.getcwd()

        try:
            if not os.path.exists(dst): os.mkdir(dst)
        except:
            log['status'] = 1
            log['stderr'] = "Unable to create " + dst
            return

        retry = cmds['retry']

        if retry < 0:
            log['status'] = 1
            log['stderr'] = "the retry count must be >= 0"
            return
        try_count = 0

        while try_count <= retry:
            if try_count > 0:
                if 'stderr' in log:
                    testDef.logger.verbose_print("Error was: %s" % log['stderr'])
                testDef.logger.verbose_print("Retrying... (%s retries left)" % (retry - try_count))
            try_count += 1

            # change to the scratch directory
            os.chdir(dst)
            # see if this software has already been cloned
            results = {}
            if os.path.exists(repo):
                if not os.path.isdir(repo):
                    log['status'] = 1
                    log['stderr'] = "Cannot update or clone repository {0} as a file of that name already exists".format(repo)
                    # track that we serviced this one
                    rp = {}
                    rp['status'] = 1
                    if cmds['subdir'] is not None:
                        rp['subdir'] = cmds['subdir']
                    self.done[repo] = rp
                    os.chdir(cwd)
                    continue
                # if they specified a pull request, then just blow it away
                # and reinstall
                if pr is not None:
                    shutil.rmtree(repo)
                    cmd_args = ["git", "clone"]
                    if recursive != "":
                        cmd_args.append(recursive)
                    cmd_args.append(url)
                    results = testDef.execmd.execute(cmds, cmd_args, testDef)
                    if 0 != results['status']:
                        log['status'] = results['status']
                        log['stderr'] = "Cannot clone repository {0}".format(repo)
                        # track that we serviced this one
                        rp = {}
                        rp['status'] = results['status']
                        rp['pr'] = pr
                        if cmds['subdir'] is not None:
                            rp['subdir'] = cmds['subdir']
                        self.done[repo] = rp
                        os.chdir(cwd)
                        if log['status'] == 0:
                            return
                        else:
                            continue
                    os.chdir(repo)
                    ptgt = "pull/"+ pr + "/head:pull_" + pr
                    results = testDef.execmd.execute(cmds, ["git", "fetch", "origin", ptgt], testDef)
                    if 0 != results['status']:
                        log['status'] = results['status']
                        log['stderr'] = "Cannot fetch PR {0}".format(repo)
                        # track that we serviced this one
                        rp = {}
                        rp['status'] = results['status']
                        rp['pr'] = pr
                        if cmds['subdir'] is not None:
                            rp['subdir'] = cmds['subdir']
                        self.done[repo] = rp
                        os.chdir(cwd)
                        if log['status'] == 0:
                            return
                        else:
                            continue
                    results = testDef.execmd.execute(cmds, ["git", "checkout", "pull_" + pr], testDef)
                    if 0 != results['status']:
                        log['status'] = results['status']
                        log['stderr'] = "Cannot checkout PR branch {0}".format(repo)
                        # track that we serviced this one
                        rp = {}
                        rp['status'] = results['status']
                        rp['pr'] = pr
                        if cmds['subdir'] is not None:
                            rp['subdir'] = cmds['subdir']
                        self.done[repo] = rp
                        os.chdir(cwd)
                        if log['status'] == 0:
                            return
                        else:
                            continue
                else:
                    # move to that location
                    os.chdir(repo)
                    # if they specified a branch, see if we are on it
                    if branch is not None:
                        results = testDef.execmd.execute(cmds, ["git", "branch"], testDef)
                        if 0 != results['status']:
                            log['status'] = results['status']
                            log['stderr'] = results['stderr']
                            log['stdout'] = results['stdout']
                            os.chdir(cwd)
                            continue
                        if isinstance(results['stdout'], list):
                            if results['stdout']:
                                t = [line for line in results['stdout'] if line.startswith('*')][0]
                            else:
                                t = ''
                        else:
                            if results['stdout'].strip():
                                t = [line for line in results['stdout'].split('\n') if line.startswith('*')][0]
                            else:
                                t = ''
                        if branch not in t:
                            # we need to whack the current installation and reinstall it
                            os.chdir(dst)
                            shutil.rmtree(repo)
                            cmd_args = ["git", "clone", "-b", branch, "--single-branch"]
                            if recursive != "":
                                cmd_args.append(recursive)
                            cmd_args.append(url)
                            results = testDef.execmd.execute(cmds, cmd_args, testDef)
                            if 0 != results['status']:
                                log['status'] = results['status']
                                log['stderr'] = "Cannot clone repository branch {0}".format(repo)
                                # track that we serviced this one
                                rp = {}
                                rp['status'] = results['status']
                                rp['branch'] = branch
                                if cmds['subdir'] is not None:
                                    rp['subdir'] = cmds['subdir']
                                self.done[repo] = rp
                                os.chdir(cwd)
                                if log['status'] == 0:
                                    return
                                else:
                                    continue
                            os.chdir(repo)
                        else:
                            # if they want us to leave it as-is, then we are done
                            try:
                                if cmds['asis']:
                                    results['status'] = 0
                                    results['stdout'] = None
                                    results['stderr'] = None
                            except KeyError:
                                # since it already exists, let's just update it
                                results = testDef.execmd.execute(cmds, ["git", "pull"], testDef)
                                if 0 != results['status']:
                                    log['status'] = results['status']
                                    log['stderr'] = results['stderr']
                                    log['stdout'] = results['stdout']
                                    os.chdir(cwd)
                                    continue
                    # if they specified a commit, see if it gives the same hash we're on
                    elif commit is not None:
                        results = testDef.execmd.execute(cmds, ["git", "log", "HEAD", "-n1", "--format=%H"], testDef)
                        if 0 != results['status']:
                            log['status'] = results['status']
                            log['stderr'] = results['stderr']
                            log['stdout'] = results['stdout']
                            os.chdir(cwd)
                            continue
                        head_commit_hash, requested_commit_hash = None, None
                        if isinstance(results['stdout'], list):
                            if results['stdout']:
                                head_commit_hash = results['stdout'][0]
                        else:
                            if results['stdout'].strip():
                                head_commit_hash = results['stdout'].split('\n')[0]
                        # if getting results['stdout'] didn't work (f.e. because of merge_stdout_stderr)
                        # then don't even try for the requeted commit
                        if head_commit_hash != None:
                            results = testDef.execmd.execute(cmds, ["git", "log", commit, "-n1", "--format=%H"], testDef)
                            if 0 != results['status']:
                                log['status'] = results['status']
                                log['stderr'] = results['stderr']
                                log['stdout'] = results['stdout']
                                os.chdir(cwd)
                                continue
                            if isinstance(results['stdout'], list):
                                if results['stdout']:
                                    requested_commit_hash = results['stdout'][0]
                            else:
                                if results['stdout'].strip():
                                    requested_commit_hash = results['stdout'].split('\n')[0]
                        if head_commit_hash == None or head_commit_hash != requested_commit_hash:
                            # we need to whack the current installation and reinstall it
                            os.chdir(dst)
                            shutil.rmtree(repo)
                            cmd_args = ["git", "clone", "--no-checkout"]
                            if recursive != "":
                                cmd_args.append(recursive)
                            cmd_args.append(url)
                            results = testDef.execmd.execute(cmds, cmd_args, testDef)
                            if 0 != results['status']:
                                log['status'] = results['status']
                                log['stderr'] = "Cannot clone repository {0}".format(repo)
                                # track that we serviced this one
                                rp = {}
                                rp['status'] = results['status']
                                rp['commit'] = commit
                                if cmds['subdir'] is not None:
                                    rp['subdir'] = cmds['subdir']
                                self.done[repo] = rp
                                os.chdir(cwd)
                                if log['status'] == 0:
                                    return
                                else:
                                    continue
                            os.chdir(repo)
                            results = testDef.execmd.execute(cmds, ["git", "checkout", commit, "--detach"], testDef)
                            if 0 != results['status']:
                                log['status'] = results['status']
                                log['stderr'] = "Cannot checkout commit {0} of repository {1}".format(commit, repo)
                                # track that we serviced this one
                                rp = {}
                                rp['status'] = results['status']
                                rp['commit'] = head_commit_hash
                                if cmds['subdir'] is not None:
                                    rp['subdir'] = cmds['subdir']
                                self.done[repo] = rp
                                os.chdir(cwd)
                                if log['status'] == 0:
                                    return
                                else:
                                    continue
                        else:
                            # if they want us to leave it as-is, then we are done
                            try:
                                if cmds['asis']:
                                    results['status'] = 0
                                    results['stdout'] = None
                                    results['stderr'] = None
                            except KeyError:
                                # since it already exists, let's just update it
                                results = testDef.execmd.execute(cmds, ["git", "pull"], testDef)
                                if 0 != results['status']:
                                    log['status'] = results['status']
                                    log['stderr'] = results['stderr']
                                    log['stdout'] = results['stdout']
                                    os.chdir(cwd)
                                    continue
                    else:
                        # if they want us to leave it as-is, then we are done
                        try:
                            if cmds['asis']:
                                results['status'] = 0
                                results['stdout'] = None
                                results['stderr'] = None
                        except KeyError:
                            # since it already exists, let's just update it
                            results = testDef.execmd.execute(cmds, ["git", "pull"], testDef)
                            if 0 != results['status']:
                                log['status'] = results['status']
                                log['stderr'] = results['stderr']
                                log['stdout'] = results['stdout']
                                os.chdir(cwd)
                                continue
            else:
                # clone it
                if branch is not None:
                    cmd_args = ["git", "clone", "-b", branch, "--single-branch"]
                    if recursive != "":
                        cmd_args.append(recursive)
                    cmd_args.append(url)
                    results = testDef.execmd.execute(cmds, cmd_args, testDef)
                    if 0 != results['status']:
                        log['status'] = results['status']
                        log['stderr'] = results['stderr']
                        log['stdout'] = results['stdout']
                        os.chdir(cwd)
                        continue
                elif commit is not None:
                    cmd_args = ["git", "clone", "--no-checkout"]
                    if recursive != "":
                        cmd_args.append(recursive)
                    cmd_args.append(url)
                    results = testDef.execmd.execute(cmds, cmd_args, testDef)
                    if 0 != results['status']:
                        log['status'] = results['status']
                        log['stderr'] = "Cannot clone repository {0}".format(repo)
                        # track that we serviced this one
                        rp = {}
                        rp['status'] = results['status']
                        rp['commit'] = commit
                        if cmds['subdir'] is not None:
                            rp['subdir'] = cmds['subdir']
                        self.done[repo] = rp
                        os.chdir(cwd)
                        if log['status'] == 0:
                            return
                        else:
                            continue
                    os.chdir(repo)
                    results = testDef.execmd.execute(cmds, ["git", "checkout", commit, "--detach"], testDef)
                    if 0 != results['status']:
                        log['status'] = results['status']
                        log['stderr'] = results['stderr']
                        log['stdout'] = results['stdout']
                        os.chdir(cwd)
                        continue
                elif pr is not None:
                    cmd_args = ["git", "clone"]
                    if recursive != "":
                        cmd_args.append(recursive)
                    cmd_args.append(url)
                    results = testDef.execmd.execute(cmds, cmd_args, testDef)
                    if 0 != results['status']:
                        log['status'] = results['status']
                        log['stderr'] = "Cannot clone repository {0}".format(repo)
                        # track that we serviced this one
                        rp = {}
                        rp['status'] = results['status']
                        rp['pr'] = pr
                        if cmds['subdir'] is not None:
                            rp['subdir'] = cmds['subdir']
                        self.done[repo] = rp
                        os.chdir(cwd)
                        if log['status'] == 0:
                            return
                        else:
                            continue
                    os.chdir(repo)
                    ptgt = "pull/"+ pr + "/head:pull_" + pr
                    results = testDef.execmd.execute(cmds, ["git", "fetch", "origin", ptgt], testDef)
                    if 0 != results['status']:
                        log['status'] = results['status']
                        log['stderr'] = "Cannot fetch PR {0}".format(repo)
                        # track that we serviced this one
                        rp = {}
                        rp['status'] = results['status']
                        rp['pr'] = pr
                        if cmds['subdir'] is not None:
                            rp['subdir'] = cmds['subdir']
                        self.done[repo] = rp
                        os.chdir(cwd)
                        if log['status'] == 0:
                            return
                        else:
                            continue
                    results = testDef.execmd.execute(cmds, ["git", "checkout", "pull_" + pr], testDef)
                    if 0 != results['status']:
                        log['status'] = results['status']
                        log['stderr'] = results['stderr']
                        log['stdout'] = results['stdout']
                        os.chdir(cwd)
                        continue
                else:
                    cmd_args = ["git", "clone"]
                    if recursive != "":
                        cmd_args.append(recursive)
                    cmd_args.append(url)
                    results = testDef.execmd.execute(cmds, cmd_args, testDef)
                    if 0 != results['status']:
                        log['status'] = results['status']
                        log['stderr'] = results['stderr']
                        log['stdout'] = results['stdout']
                        os.chdir(cwd)
                        continue
                # move into it
                os.chdir(repo)
            # record the result
            log['status'] = results['status']
            log['stdout'] = results['stdout']
            log['stderr'] = results['stderr']
            # get the current hash and record it
            hashresult = testDef.execmd.execute(cmds, ["git", "log", "-1", "--oneline"], testDef)
            # the hash is the first field before the space
            if hashresult['stdout']:
                log['hash'] = hashresult['stdout'][0].split()[0]
            else:
                log['hash'] = None

            # log our absolute location so others can find it
            log['location'] = os.getcwd()
            # if they indicated that a specific subdirectory was
            # the target, then modify the location accordingly
            cmdlog = 'Fetch CMD: ' + ' '.join(cmds)
            testDef.logger.verbose_print(cmdlog)
            if cmds['subdir'] is not None:
                # check that this subdirectory actually exists
                ckdir = os.path.join(log['location'], cmds['subdir'])
                if not os.path.exists(ckdir):
                    log['status'] = 1
                    log['stderr'] = "Subdirectory " + cmds['subdir'] + " was not found"
                    status,stdout,stderr = testDef.modcmd.revertModules(log['section'], testDef)
                    os.chdir(cwd)
                    continue
                if not os.path.isdir(ckdir):
                    log['status'] = 1
                    log['stderr'] = "Subdirectory " + cmds['subdir'] + " is not a directory"
                    status,stdout,stderr = testDef.modcmd.revertModules(log['section'], testDef)
                    os.chdir(cwd)
                    continue
                log['location'] = ckdir
            # track that we serviced this one - save the absolute location so
            # any subsequent requests with a different subdir can be pointed to
            # the correct location
            rp = {}
            rp['status'] = results['status']
            rp['location'] = log['location']
            if pr is not None:
                rp['pr'] = pr
            elif commit is not None:
                rp['commit'] = commit
            elif branch is not None:
                rp['branch'] = branch
            if cmds['subdir'] is not None:
                rp['subdir'] = cmds['subdir']
            rp['hash'] = log['hash']
            self.done[repo] = rp

            # Revert any requested environment module settings
            status,stdout,stderr = testDef.modcmd.revertModules(log['section'], testDef)
            if 0 != status:
                log['status'] = status
                log['stdout'] = stdout
                log['stderr'] = stderr
                os.chdir(cwd)
                continue

            # change back to the original directory
            os.chdir(cwd)
            break

        return
