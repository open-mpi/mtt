#!/bin/bash -l

cd $HOME/mtt
SCRATCH_FILE="scratch"
SCRATCH_DIR=$HOME/mtt/$SCRATCH_FILE
rm -f -r $SCRATCH_DIR
export MTT_HOME=$PWD
pyclient/pymtt.py --verbose  get_build_ompi.ini
if [ $? -ne 0 ]
then
    echo "Something went wrong with fetch/build phase"
    exit -1
fi
echo "============== Submitting batch job for Testing  ==============="
jobid=`sbatch -o slurm.out --wait --parsable -N 4 --time=6:00:00 --tasks-per-node=8 ./run_mtt_backend.sh`
if [ $jobid -eq 1 ]; then
    echo "Something went wrong with batch job"
    exit -1
fi
pyclient/pymtt.py --verbose  report_results.ini

