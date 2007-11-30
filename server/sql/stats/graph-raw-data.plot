set title "Submissions per day/week/month"
set key left

set xdata time
set timefmt "%Y-%m-%d"
set format x "%Y/%m"
set xlabel "Date"
set xtics rotate by 90

set ylabel "Tuples per month (Thousands)"
set y2label "Tuples per day/week (Thousands)"
set y2tics 0, 100
set ytics nomirror

set grid xtics
set grid ytics
show grid


set terminal aqua
#set terminal postscript color lw 3
#set output "day-graph.ps"

plot \
     "raw-month.data" using 1:($2/1000) title "Total (per month)"  axis x1y1 with lines lt 1 lw 3, \
     "raw-week.data"  using 1:($2/1000) title "Total (per week)"   axis x1y2 with lines lt 2 lw 2, \
     "raw-day.data"   using 1:($2/1000) title "Total (per day)"    axis x1y2 with lines lt 3 lw 1

#plot "raw-day.data" using 1:2 title "Total"       with lines lt 1 lw 3, \
#     "raw-day.data" using 1:3 title "MPI Install" with lines lt 2 lw 3, \
#     "raw-day.data" using 1:4 title "Test Build"  with lines lt 3 lw 3, \
#     "raw-day.data" using 1:5 title "Test Run"    with lines lt 4 lw 3, \
#     "raw-day.data" using 1:6 title "Test Run (Perf)"    with lines lt 5 lw 3
