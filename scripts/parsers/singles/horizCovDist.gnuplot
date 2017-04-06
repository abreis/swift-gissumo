set terminal postscript eps enhanced color size 1cm,10cm
set output "dir/outfile.eps"

set lmargin 0
set rmargin 0
set tmargin 0
set bmargin 0

unset xlabel
unset ylabel
unset key
unset border
unset xtics
unset ytics

set style data histograms
set style histogram rowstacked
set boxwidth 1.0 relative # Bar width
set style fill solid 1.00 border lc rgb "white"
set xrange [-0.5:0.5]
set yrange [0:650]

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

plot '<(sed -n 2p dir/datafile.name)' \
		   using 8  lc rgb "#FD7400" lw 6, \
		'' using 9  lc rgb "#FFE11A" lw 6, \
		'' using 10 lc rgb "#BEDB39" lw 6, \
		'' using 11 lc rgb "#1F8A70" lw 6
