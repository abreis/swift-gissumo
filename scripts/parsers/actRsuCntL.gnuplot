set terminal postscript eps enhanced color
set output "dir/outfile.eps"
set size argwidth, 0.35

set xlabel "Simulation Time [s]"
set ylabel "Active Roadside Units" rotate by +90 center
unset key

set yrange [0:100]

plot 'dir/datafile.name' using 1:2 notitle with lines linecolor 1 linewidth 2

