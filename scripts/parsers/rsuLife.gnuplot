set terminal postscript eps enhanced color
set output "dir/outfile.eps"
set size argwidth, 0.35

set xlabel "Roadside Unit Lifetime [s]"
set ylabel "Frequency" rotate by +90 center
unset key
set border 3

set xtics out nomirror
unset ytics
set style fill solid border lc rgb "white"
set yrange [0:0.5]

plot 'dir/datafile.name' using 1:2 with boxes lc rgb "#0074D9"
