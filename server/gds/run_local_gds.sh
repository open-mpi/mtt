#!/bin/sh
#
#   This script downloads, installs and loading GDS server on local host
#
#

HOME_PATH=`dirname $0`     # exec name cutting
mkdir -p $HOME_PATH/build


cd ${HOME_PATH}
HOME_PATH=`pwd`/build
cd ${HOME_PATH}

PORT=8080
if [ $# -eq 1 ]; then
    PORT=$1
fi

LOCAL_PATH=../tests
APP_PATH=../
APPENGINE_PATH=${HOME_PATH}/google_appengine

if [ -e ${APPENGINE_PATH} ] 
then
    echo " GDS server already installed"
else
    echo "Installing GDS server"
#    download and install the newest version
#    wget http://code.google.com/appengine/downloads.html
#    link=`cat downloads.html  |grep google_appengine |awk '{ print $2}' | cut -d= -f2 |cut -d'"' -f2 `
#    rm -f downloads.html
#    wget $link
#    unzip google_appengine*

#   currently get the working version 1.2.7
    wget http://googleappengine.googlecode.com/files/google_appengine_1.2.7.zip
    unzip google_appengine_1.2.7.zip
fi


file=../main.py
line_num=`grep -rn " COMMENT FOLLOWING THREE LINES" $file | awk '{ print $1}' |sed 's/:#//g'`
if [ ${line_num} ]
then 
    echo "Backing up $file to  ${file}.bak"
    cp $file ${file}.bak
    echo "modifying $file to run locally"
    sed -i $line_num,+4d $file
fi

logfile=$HOME_PATH/gds_`date +%s`.log
echo "starting GDS server, all output goes to $logfile"

python25 "${APPENGINE_PATH}/dev_appserver.py" -d --address="`hostname`" --port=$PORT --datastore_path="${LOCAL_PATH}/db$PORT" --history_path="${LOCAL_PATH}/db$PORT.history" "${APP_PATH}" 2>&1|tee >  $logfile &

