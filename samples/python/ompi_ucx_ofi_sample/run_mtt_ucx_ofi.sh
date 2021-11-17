#!/bin/bash -l

cd <<<<path to mtt folder>>>
export MTT_HOME=$PWD
echo "============== Testing with UCX ================"
SCRATCH_DIR="scratch_dir/ucx"
rm -f -r $SCRATCH_DIR/*
pyclient/pymtt.py --verbose  ompi_nightly_ucx.ini
echo "============== Testing with OFI ================"
SCRATCH_DIR="scratch_dir/ofi"
rm -f -r $SCRATCH_DIR/*
pyclient/pymtt.py --verbose  ompi_nightly_ofi.ini

