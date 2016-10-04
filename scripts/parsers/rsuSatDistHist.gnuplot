set terminal postscript eps enhanced color
set output "dir/outfile.eps"
set size 0.7, 0.7

set datafile separator ","

set xlabel "RSU Saturation"
set ylabel "Frequency" rotate by +90 center
unset key

stats 'dir/datafile.name' nooutput

min=0		# where binning starts
max=10		# where binning ends
nbins=10	# the number of bins
binwidth = (max-min)/nbins # binwidth; evaluates to 1.0
bin(x,width) = (width*(floor((x-min)/width)+0.5) + min)

set boxwidth binwidth*0.9
set style fill solid 1

set xrange [-4:15]
set xtics autofreq 0,1,10 offset 1.0 nomirror

plot 'dir/datafile.name' using (bin($1,binwidth)):(1.0/STATS_records) smooth freq with boxes lc 6
