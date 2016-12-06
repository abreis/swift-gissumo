set terminal postscript eps enhanced color
set output "dir/outfile.eps"
set size 1.4, 0.7 # Extra wide plot

set xlabel "Time Interval [s]"
set ylabel "Score" rotate by +90 center
unset key

set key autotitle columnhead # First lines are headers

set style data histograms
set style histogram rowstacked
set boxwidth 0.40 relative # Bar width
set style fill solid 1.00 noborder

set xtics nomirror
set ytics nomirror

plot 'dir/datafile.name' \
		   using 2:xticlabels(1) lc 4, \
		'' using 3:xticlabels(1) lc 5, \
		'' using ($4*-1.0):xticlabels(1) lc 7, \
		'' using 5:xticlabels(1) with points lc 8 lt 6