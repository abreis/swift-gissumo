Statistics Hooks
================
This is a list of availabe statistics hooks and what enabling each does.


* activeVehicleCount (interval)

  Prints how many vehicles are active. Good for verifying the density of vehicles on the road over time, as SUMO doesn't have a way of enforcing this.


* activeRoadsideUnitCount (interval)

  Prints how many roadside units are active.


* cityCoverageMapEvolution (interval) [not implemented]

  Prints the coverage map of the complete city.


* cityCoverageEvolution (interval)

  Prints the number of cells covered, and signal level statistics.


* beaconCounts (interval)

  Prints the number of packets with Beacon payloads being sent and received.


* finalRoadsideUnitCoverageMaps (end)

  Prints the coverage map of every active roadside unit.


* finalCityCoverageMap (end)

  Prints a map of signal coverage in the city.


* finalCitySaturationMap (end)

  Prints a map of RSU saturation in the city.


* finalCityEntitiesMap (end)

  Prints a map with the entities in the city.


* finalCityCoverageStats (end)

  Prints statistics of cell signal coverage in the city.


* finalCitySaturationStats (end)

  Prints statistics of cell saturation in the city.


* obstructionMask (end)

  Prints the map of obstructions being used for statistics, after cropping.


