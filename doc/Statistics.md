Statistics Hooks
================
This is a list of available statistics hooks and what enabling each does. Four types of hooks are possible, based on their collection times:

- Interval: data is collected periodically as defined by `collectionInterval`.
- End: data is collected when the simulation ends.
- Trigger: data is collected when a specific event occurs (e.g.: a car parks).
- Immediate: same as 'Trigger', but the data is written to disk immediately. Useful for debugging and tracing.

Available hooks:

* entityCount (interval)

  Prints how many vehicles, roadside units and parked cars are active. Good for verifying the density of vehicles on the road over time, as SUMO doesn't have a way of enforcing this.


* cityCoverageMapEvolution (interval) [not implemented]

  Prints the coverage map of the complete city.


* cityCoverageEvolution (interval)

  Prints the number of cells covered, and signal level statistics.


* signalAndSaturationEvolution (interval)

  Prints the mean signal strength, mean RSU saturation, and the signal-to-saturation ratio.


* beaconCount (interval)

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


* decisionCCE (trigger)

  Prints the intermediate and final metrics used to compute the decision score when the CellCoverageEffects decision algorithm is selected.


* decisionDetailCCE (trigger)

  Prints a detailed log of all RSU election decisions, complete with all coverage maps received, resulting local maps, etcetera, for the CellCoverageEffects algorithm.


* decisionWPM (trigger)

  Prints the metrics used to compute the decision score when the WeightedProductModel decision algorithm is selected.


* decisionDetailWPM (trigger)

  Prints a detailed log of all RSU election decisions, complete with all coverage maps received, resulting local maps, etcetera, for the WeightedProductModel algorithm.


* movingAverageWPM (interval)

  Prints an exponential moving average of past decisions' signal and saturation stats of the winning combination.


* obstructionMask (end)

  Prints the map of obstructions being used for statistics, after cropping.


* packetTrace (immediate)

  Prints a trace of all packets that are broadcast in the simulation.
