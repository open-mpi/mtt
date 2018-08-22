#!/bin/bash -ex

### INPUTS via environment variables ###
#  KERNEL_RELEASE
#  LOGFILE

kernel_release=${KERNEL_RELEASE:? KERNEL_RELEASE not set}
logfile=${LOGFILE:? LOGFILE not set}

# Check that the logfile has correct version string
# Remove the line in the logfile that was used for passing in KERNEL_RELEASE environment variable
# The logfile will live at the top of the <scratchdir>/<testname> directory structure
cat $logfile | grep -v KERNEL_RELEASE | grep $kernel_release
exit $?
