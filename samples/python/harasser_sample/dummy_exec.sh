dummy_sleep_time=$DUMMY_EXEC_TIME

fname=$(basename $BASH_SOURCE)

echo "$fname: Start time "`date`

echo "$fname: pid = $$"

ps

echo "$fname: $dummy_sleep_time seconds left"
for (( i=1; i<=$dummy_sleep_time; i++ ))
do
    sleep 1
    echo "$fname: "`expr $dummy_sleep_time - $i`" seconds left"
done
