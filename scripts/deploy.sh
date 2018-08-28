#!/bin/bash

# check to see if the docs directory changed - if not,
# then git will return a 0 exit code. If it did change,
# then git will return a 1. Only deploy the docs directory
# if a change occurred.
testchange=`git diff --exit-code -- docs > /dev/null`
if [ $? -ne 0 ]; then
  deploy:
    provider: pages
    skip_cleanup: true
    github-token: $GH_TOKEN
    local_dir: docs/
    keep-history: true
    on:
      branch: master
fi

