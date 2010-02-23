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
    -cmd)
      COMMAND=${!i1}
      COMMAND=`echo ${COMMAND} | sed -e 's/ -x "custom_[^"]*"//g'`
      COMMAND=`echo ${COMMAND} | sed -e "s/ -x 'custom_[^']*'//g"`
      COMMAND=`echo ${COMMAND} | sed -e 's/ -x custom_[^ =]*="[^"]*"//g'`
      COMMAND=`echo ${COMMAND} | sed -e "s/ -x custom_[^ =]*='[^']*'//g"`
      COMMAND=`echo ${COMMAND} | sed -e "s/ -x custom_[^ \"']*//g"`
      i=$i+1
      ;;
    -help)
      echo "HPL parameters:"
      echo "-workdir: working dir"
      echo "-hosts: host list"
      echo "-cmd: command (mpirun and parameters)"
      exit 1
      ;;
  esac
done

if [ -z $WORKDIR ]; then
  echo "FATAL ERROR: Specify -workdir parameter."
  exit 1
fi

if [ "x" == "x$HOSTS" ]; then
  echo "FATAL ERROR: Specify -hosts parameter."
  exit 1
fi

if [ "x" == "x$COMMAND" ]; then
  echo "FATAL ERROR: Specify -cmd parameter."
  exit 1
fi

WORKDIR=$WORKDIR/$$

mkdir -p $WORKDIR
if ! [ -d $WORKDIR ]; then
  echo "FATAL ERROR: Can't create work directory: $WORKDIR"
  exit 1
fi

basedir=`pwd`

mydir=`dirname $0`
mydir="`readlink -f $mydir`"

cd $WORKDIR
WORKDIR=`pwd`
echo "OUTPUT: $WORKDIR"

echo Execute breate_conf.pl...
$mydir/bcreate_conf.pl -h $HOSTS -t $WORKDIR/HPL.dat
EXIT_VALUE=$?
echo End of execute bcreate_conf.pl
if [ $EXIT_VALUE != 0 ]; then
  exit $EXIT_VALUE;
fi

if [ ! -f $WORKDIR/HPL.dat ]; then
  echo "FATAL ERROR: Can't generate HPL.dat file: $WORKDIR/HPL.dat"
  exit 1
fi

MPI_HOSTS=`echo $HOSTS | sed 's/,/ /g'`

TOTAL_MHZ="0"

for host in $MPI_HOSTS ; do
    CPUS_PER_HOST=`ssh $host cat /proc/cpuinfo | grep processor | wc -l`
    CPU_MHZ=`ssh $host cat /proc/cpuinfo | grep "cpu MHz" | head -n 1 | sed s/.*://`
    TOTAL_MHZ=`echo "$TOTAL_MHZ + $CPUS_PER_HOST * $CPU_MHZ" | bc` 
done

echo TOTAL CPU MHZ: $TOTAL_MHZ

echo working dir:
ls

echo Start HPL...
$COMMAND < /dev/null
EXIT_VALUE=$?

cd $basedir
exit $EXIT_VALUE
