#!/bin/bash
set -ev
testchange=`git diff --exit-code -- docs > /dev/null`
if [$testchange]; then
  deploy:
    provider: pages
    skip_cleanup: true
    github-token: $GH_TOKEN
    local_dir: docs/
    keep-history: true
    on:
      branch: master
fi

