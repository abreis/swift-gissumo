set terminal postscript eps enhanced color
set output "dir/outfile.eps"
set size 0.7, 0.35	# Half height plot

set xlabel "Time Interval [s]"
set ylabel "Count" rotate by +90 center
unset key

set key autotitle columnhead # First lines are headers
set key horizontal outside

set style data histograms
set style histogram rowstacked
set boxwidth 0.40 relative # Bar width
set style fill solid 1.00 noborder

set xtics nomirror rotate by -90
set ytics nomirror

# Neutral blue
#rgb "#91AA9D"
#rgb "#D1DBBD"
#rgb "#3E606F"
# Sandy stone beach
#rgb "#A7A37E"
#rgb "#E6E2AF"
#rgb "#046380"

plot 'dir/datafile.name' \
		   using 2:xticlabels(1)	lc rgb "#9C9B7A", \
		'' using 3:xticlabels(1) 	lc rgb "#FFD393"
		#'' using ($0):($2+$3+1.0):(sprintf('%.0f', $6)) notitle with labels font "Arial,8"
