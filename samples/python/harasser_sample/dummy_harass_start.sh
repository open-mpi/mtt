fname=$(basename $BASH_SOURCE)

echo "$fname: Start time "`date`

echo "$fname: pid = $$"

nohup ./dummy_harass.sh &
pid=$!
echo $pid > dummy_harass_pid
echo "$fname: Started pid $pid"
wait
