#!/bin/sh

set -x

echo THIS IS THE DEPLOY SCRIPT

git show remote
git show remote origin

git clone --depth=1 -b gh-pages https://github.com/open-mpi/mtt.git gh-pages
tar -C docs -xf - . | tar -C gh-pages -xvf -

cd gh-pages

if git diff --exit-code --quiet html > /dev/null 2>&1; then
    echo NOTHING TO PUSH
else
    echo PUSHING CHANGES
    git diff | grep ^diff
    git commit -a -m "Deploy open-mpi/mtt to gh-pages"
    # git push origin gh-pages
fi
