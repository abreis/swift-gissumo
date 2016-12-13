set terminal postscript eps enhanced color
set output "dir/outfile.eps"
set size 0.7, 0.70

set xlabel "Time Interval [s]"
set ylabel "Count" rotate by +90 center
unset key

set key autotitle columnhead # First lines are headers
set key top left reverse samplen 1.0

set style data histograms
set style histogram rowstacked
set boxwidth 0.60 relative # Bar width
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
#Vitamin C
#rgb "#004358"
#rgb "#1F8A70"
#rgb "#BEDB39"
#rgb "#FFE11A"

plot 'dir/datafile.name' \
		   using 8:xticlabels(1) title "2" 	lc rgb "#FD7400", \
		'' using 9:xticlabels(1) title "3" 	lc rgb "#FFE11A", \
		'' using 10:xticlabels(1) title "4" lc rgb "#BEDB39", \
		'' using 11:xticlabels(1) title "5" lc rgb "#1F8A70"
