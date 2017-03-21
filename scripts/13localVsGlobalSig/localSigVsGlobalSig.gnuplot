set terminal postscript eps enhanced color
set output "localSigVsGlobalSig.eps"
set size 0.7, 0.7

set xlabel "Simulation Time [s]"
set ylabel "Mean Signal Strength" rotate by +90 center
unset key

set xtics nomirror
set ytics nomirror

set key autotitle columnheader
set key inside bottom right

set yrange [3.5:4.5]

plot 'sigLocalEMA.data' using 1:2 title "Local Decisions" with lines linecolor 4 linewidth 2, \
		'sigGlobal.data' using 1:2 title "Citywide View" with lines linecolor 1 linewidth 2
