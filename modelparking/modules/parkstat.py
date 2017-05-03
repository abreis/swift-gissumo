import sys, math
import csv

parkingProbabilitiesFile='modules/perSecondArrayNorm.csv'

# This routine distributes a number of parking events over a particular
# timeframe, returning a dictionary array of how many parking events
# should occur on each second. Expects time in seconds, matching
# real-life time.
def distributeEvents(numberOfEvents, startTime=10800, endTime=75600):
	parkingEventDictionary = {}

	# Import parking probability density (in 1-second intervals, 24-hour, Chicago2007)
	csvfile=open(parkingProbabilitiesFile, newline='')
	pdfdata = csv.reader(csvfile, delimiter=',')

	# Go through probability data and perform necessary calculations
	remainder=0
	for row in pdfdata:
		csvTime=int(row[0])
		if csvTime < startTime:
			continue
		elif csvTime >= endTime:
			break

		numParkingEvents = float(row[1])*numberOfEvents+remainder
		parkingEventDictionary[csvTime] = int( math.modf(numParkingEvents)[1] )
		remainder = math.modf(numParkingEvents)[0]

	return parkingEventDictionary
