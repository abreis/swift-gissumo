set terminal postscript eps enhanced color
set output "dir/outfile.eps"
set size argwidth, 0.35

set xlabel "Simulation Time [s]"
set ylabel "Signal/Saturation Ratio" rotate by +90 center
unset key

plot 'dir/datafile.name' using 1:2 notitle with lines linecolor 7 linewidth 2

