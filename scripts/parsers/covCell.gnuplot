set terminal postscript eps enhanced color
set output "dir/outfile.eps"
set size argwidth, 0.35

set xlabel "Simulation Time [s]"
set ylabel "% City Covered" rotate by +90 center
unset key

set yrange [0:1]

plot 'dir/datafile.name' using 1:2 with filledcurves x1 fc rgb "#E27A3F"
