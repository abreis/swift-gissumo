set terminal postscript eps enhanced color
set output "dir/outfile.eps"
set size 0.7, 0.7

set xlabel "Average Signal Strength"
set ylabel "Average RSU Saturation" rotate by +90 center
unset key

set xrange [0:5]
set xtics autofreq 0,1,5 nomirror
set ytics nomirror

plot 'dir/datafile.name' using 4:6 notitle with points pointtype 7 linecolor 6 pointsize 0.20

