fname=$(basename $BASH_SOURCE)

echo "$fname: Start time "`date`

echo "$fname: pid = $$"

pid=`cat dummy_harass_pid`
echo "$fname: Killing pid $pid"
kill $pid
