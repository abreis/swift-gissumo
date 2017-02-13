set terminal postscript eps enhanced color
set output "dir/outfile.eps"
set size 1.4, 0.35

set xlabel "Simulation Time [s]"
set ylabel "Active Roadside Units" rotate by +90 center
unset key

plot 'dir/datafile.name' using 1:2 notitle with lines linecolor 1 linewidth 2

