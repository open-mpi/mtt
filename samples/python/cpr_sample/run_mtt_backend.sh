#!/bin/bash -l

cd $HOME/mtt
export MTT_HOME=$PWD
pyclient/pymtt.py --verbose run_tests.ini

