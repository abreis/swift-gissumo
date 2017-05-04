import random, sys, math, bisect
import sumolib, route2trips

tripGenerator = None
minTripDistance = 100


###############
### CLASSES ###
###############

# Euclidean distance between two coordinates in the plane
def euclidean(a, b):
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2)

class RandomTripGenerator:
	def __init__(self, net, source_generator, sink_generator):
		self.source_generator = source_generator
		self.sink_generator = sink_generator
		self.net = net

	def getTrip(self, mindistance, maxtries=1000):
		for i in range(maxtries):
			source_edge = self.source_generator.get()
			sink_edge = self.sink_generator.get()
			destCoord = sink_edge.getToNode().getCoord()

			coords = ([source_edge.getFromNode().getCoord()] + [destCoord])
			distance = sum([euclidean(p, q) for p, q in zip(coords[:-1], coords[1:])])

			# This breaks the for cycle when a match is found
			if distance >= mindistance:
				return source_edge.getID(), sink_edge.getID()

	# Get a new trip pair forcing a source edge
	def getTripWithSource(self, sourceEdge, mindistance, maxtries=1000):
		source_edge = self.net.getEdge(sourceEdge)
		for i in range(maxtries):
			sink_edge = self.sink_generator.get()
			destCoord = sink_edge.getToNode().getCoord()

			coords = ([source_edge.getFromNode().getCoord()] + [destCoord])
			distance = sum([euclidean(p, q) for p, q in zip(coords[:-1], coords[1:])])

			# This breaks the for cycle when a match is found
			if distance >= mindistance:
				return source_edge.getID(), sink_edge.getID()

class InvalidGenerator(Exception):
    pass

class RandomEdgeGenerator:
    def __init__(self, net, weight_fun):
        self.net = net
        self.weight_fun = weight_fun
        self.cumulative_weights = []
        self.total_weight = 0
        for edge in self.net._edges:
            self.total_weight += weight_fun(edge)
            self.cumulative_weights.append(self.total_weight)
        if self.total_weight == 0:
            raise InvalidGenerator()

    def get(self):
        r = random.random() * self.total_weight
        index = bisect.bisect(self.cumulative_weights, r)
        return self.net._edges[index]


################
### ROUTINES ###
################

def get_prob_fun(fringe_factor, fringe_bonus, fringe_forbidden):
	def edge_probability(edge):
		if fringe_bonus is None and edge.is_fringe():
			return 0  # not suitable as intermediate way point
		if fringe_forbidden is not None and edge.is_fringe(getattr(edge, fringe_forbidden)):
			return 0  # the wrong kind of fringe
		prob = 1
		if (fringe_factor != 1.0
				and fringe_bonus is not None
				and edge.is_fringe(getattr(edge, fringe_bonus))):
			prob *= fringe_factor
		return prob

	# Return a pre-configured function
	return edge_probability




def makeNewTrip():
	global tripGenerator, minTripDistance

	if tripGenerator == None:
		print("Error: Set up a trip generator first.", file=sys.stderr)
		return

	return tripGenerator.getTrip(mindistance=minTripDistance)




def makeNewTripWithSource(sourceEdgeID):
	global tripGenerator, minTripDistance

	if tripGenerator == None:
		print("Error: Set up a trip generator first.", file=sys.stderr)
		return

	return tripGenerator.getTripWithSource(sourceEdge=sourceEdgeID, mindistance=minTripDistance)



def setup(netfile="map.net.xml", seed=31337, fringefactor=1.0, mindistance=100):
	global tripGenerator, minTripDistance
	minTripDistance = mindistance

	# Init random seed
	random.seed(seed)

	# Read net XML data
	sumoNet = sumolib.net.readNet(netfile)

	# Check whether mindistance is valid based on the size of this network
	bboxDiameter = sumoNet.getBBoxDiameter()
	if minTripDistance > bboxDiameter:
		print("Error: Cannot achieve a minimum trip length of {:d} in a network with diameter {:f}.".format(minTripDistance, bboxDiameter), file=sys.stderr)
		sys.exit(1)

	## Ready a trip generator
	# Setup generators for source and sink edges
	try:
		source_generator = RandomEdgeGenerator(sumoNet, get_prob_fun(fringefactor, "_incoming", "_outgoing"))
		sink_generator = RandomEdgeGenerator(sumoNet, get_prob_fun(fringefactor, "_outgoing", "_incoming"))
	except InvalidGenerator:
		print("Error: No valid edges for generating source or destination", file=sys.stderr)
		sys.exit(1)

	tripGenerator = RandomTripGenerator(sumoNet, source_generator, sink_generator)


