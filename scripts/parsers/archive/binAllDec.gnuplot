set terminal postscript eps enhanced color
set output "dir/outfile.eps"
set size 0.7, 0.7

set xlabel "Time Interval [s]"
set ylabel "Score" rotate by +90 center

set key autotitle columnhead # First lines are headers
set key top right samplen 1.0

set style data histograms
set style histogram rowstacked
set boxwidth 0.40 relative # Bar width
set style fill solid 1.00 noborder

set xtics nomirror rotate by -90
set ytics nomirror

lcnew = 4
lcboost = 5
lcsat = 7
lcscore = 8

plot 'dir/datafile.name' \
		   using 2:xticlabels(1) lc lcnew, \
		'' using 3:xticlabels(1) lc lcboost, \
		'' using ($4*-1.0):xticlabels(1) lc lcsat, \
		'' using 5:xticlabels(1) with points lc lcscore lt 6
