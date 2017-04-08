set terminal postscript eps enhanced color
set output "dir/outfile.eps"
set size argwidth, 0.35

set xlabel "Roadside Unit Lifetime [s]"
set ylabel "Frequency" rotate by +90 center
unset key
set key autotitle columnhead

set xtics out nomirror
unset ytics
set style fill solid border lc rgb "white"

# binning limits
binmin = 0
binmax = 7200
set xrange [-360:7560] # +- 5%
set yrange [0:2000]

# number of bins
bincount = 40

binwidth = (binmax-binmin)/bincount
bin(x) = binwidth*(floor((x-binmin)/binwidth)+0.5) + binmin

plot 'dir/datafile.name' using (bin($1)):(1.0) smooth freq with boxes lc rgb "#0074D9"
