#!/bin/bash
#
# Copyright (c) 2009 Voltaire
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

for ((i=1;i<=$#;i++))
do
  declare -i i1
  i1=$i+1
  case ${!i} in
    -workdir)
      WORKDIR=${!i1}
      i=$i+1
      ;;
    -hosts)
      HOSTS=${!i1}
      i=$i+1
      ;;
    -np)
      NP=${!i1}
      i=$i+1
      ;;
    -mpiroot)
      MPIROOT=${!i1}
      i=$i+1
      ;;
    -mpiopt)
      MPIOPT=${!i1}
      i=$i+1
      ;;
    -mpiver)
      MPIVER=${!i1}
      i=$i+1
      ;;
    -inputfile)
      INPUT_FILE=${!i1}
      i=$i+1
      ;;
    -pamroot)
      PAMROOT=${!i1}
      i=$i+1
      ;;
    --help)
      echo "Parameters list:"
      echo "-workdir: path to work wirectory"
      echo "-hosts: list of used hosts"
      echo "-np: number of processes"
      echo "-mpiroot: path to mpi directory"
      echo "-mpiopt: mpi options (-mca, etc)"
      echo "-mpiver: must be openmpi-1.3"
      echo "-inputfile: input file path"
      echo "-pamroot: path to PamCrush directory"

      exit 1
  esac
done

if [ -z $WORKDIR ]; then
  echo "FATAL ERROR: Specify -workdir parameter."
  exit 1
fi

if [ -z $MPIROOT ]; then
  echo "FATAL ERROR: Specify -mpiroot parameter."
  exit 1
fi

if [ ! -e $INPUT_FILE ]; then
  echo "FATAL ERROR: Specify -inputfile parameter: $INPUT_FILE."
  exit 1
fi

mydir=`dirname $0`
mydir="`readlink -f $mydir`"

WORKDIR=$WORKDIR/$$
mkdir -p $WORKDIR
WORKDIR="`readlink -f $WORKDIR`"

cd $WORKDIR
echo CASE: `basename $INPUT_FILE`
echo OUTPUT: $WORKDIR/pamcrash.log

export PAMROOT=$PAMROOT
export PAMPROD=pamcrash_safe
export PAMVERS=2009.0
export PAMOS=Linux
#export PAMARCH=x86_64
export PAMARCH=em64t
export PAM_LMD_LICENSE_FILE=27000@bserver1
source $PAMROOT/esi_bash_profile
export PAMWORLD=$PAMROOT/vpsolver/$PAMVERS/pamworld
export LD_LIBRARY_PATH=$PAMROOT/$PAMPROD/$PAMVERS/$PAMOS/$PAMARCH/DMP/SP/lib

OMPI_DIR=$MPIROOT
OMPI_PARAMS="$MPIOPT"
OMPI_NP=$NP
OMPI_VER=$MPIVER

OMPI_HOSTS=`echo $HOSTS | sed 's/,/ /g'`

OMPI_NHOSTS=`echo $OMPI_HOSTS | wc -w`
for host in $OMPI_HOSTS ; do
	CPUS_PER_HOST=`ssh $host cat /proc/cpuinfo | grep processor | wc -l`
	echo $host $CPUS_PER_HOST >> $WORKDIR/clusterfile
done
echo `hostname` 0 >> $WORKDIR/clusterfile

INPUT_DIR=`dirname $INPUT_FILE`
#cd $INPUT_DIR
#pwd
INPUT_FILE_NAME=`basename $INPUT_FILE`
ln -s $INPUT_DIR/*.inc $WORKDIR/
ln -s $INPUT_DIR/*.pc $WORKDIR/
echo WORKING DIRECTORY:
ls
$PAMWORLD -wd $WORKDIR -np $OMPI_NP -cf $WORKDIR/clusterfile -mpiext "$OMPI_PARAMS" -mpi $OMPI_VER -mpidir $OMPI_DIR/bin -lic CRASHSAF $INPUT_FILE_NAME > $WORKDIR/pamcrash.log < /dev/null
EXIT_VALUE=$?
head -n 20 $WORKDIR/pamcrash.log | grep Version
echo Last 100 lines from log file
tail -100 $WORKDIR/pamcrash.log
exit $EXIT_VALUE
