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
      echo "HPCC parameters:"
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
$mydir/bcreate_conf.pl -hpcc -h $HOSTS -t $WORKDIR/hpccinf.txt
EXIT_VALUE=$?
echo End of execute bcreate_conf.pl
if [ $EXIT_VALUE != 0 ]; then
  exit $EXIT_VALUE;
fi

echo Start HPCC...
$COMMAND < /dev/null
EXIT_VALUE=$?

cd $basedir
exit $EXIT_VALUE
