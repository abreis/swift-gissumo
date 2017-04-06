set terminal postscript eps enhanced color size 4cm,1cm
set output "rsuLifeCompact.eps"

set lmargin 0
set rmargin 0
set tmargin 0
set bmargin 0

#set xlabel "Roadside Unit Lifetime [s]"
#set ylabel "Frequency" rotate by +90 center
unset xlabel
unset key
set border 1

#unset xtics
set xtics (0,1800,3600) nomirror
unset ytics

set style fill solid noborder #lc rgb "white"
set xrange [-40:3720] # 80-width boxes, first: center 40, last: center 3640
set yrange [0:0.4]
set boxwidth 80 absolute

plot 'rsuLife.data' using 1:2 with boxes lc rgb "#0074D9"
