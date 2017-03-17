set terminal postscript eps enhanced color
set output "dir/outfile.eps"
set size 0.35, 0.7

set datafile separator ","

set xlabel "Signal Strength"
set ylabel "Frequency" rotate by +90 center
unset key

stats 'dir/datafile.name' nooutput

min=0		# where binning starts
max=5		# where binning ends
nbins=5		# the number of bins
binwidth = (max-min)/nbins # binwidth; evaluates to 1.0
bin(x,width) = (width*(floor((x-min)/width)+0.5) + min)

set boxwidth binwidth*0.9
set style fill solid 1

set xrange [-1:7]
set xtics autofreq 0,1,5 offset 1.5 nomirror

plot 'dir/datafile.name' using (bin($1,binwidth)):(1.0/STATS_records) smooth freq with boxes lc 6
