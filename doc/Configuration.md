Configuration File
==================
A GISSUMO configuration file is an XML Property List with the .plist extension.


* `floatingCarDataFile`

  An XML containing vehicular Floating Car Data in timestep divisions, obtained with SUMO.


* `stopTime`

  The time at which the simulation should stop. GISSUMO will also not load FCD data belonging to timesteps that occur after this time.


* `locationSRID`

  The best SRID for the area of the city under simulation, for accurate distance calculations. Not required if using the Haversine formula.


* `useHaversine`

  Instead of querying the GIS database, use the Haversine formula to approximate the distance between two points. This formula typically shows 0.5% error, but it can reduce the simulation time in ~20%-30%.


* `dataFlushInterval`

  For longer simulations, setting a time (in simulation seconds) in this parameter causes the simulator to flush data to all files periodically, and to flush old simulation events, thereby keeping memory usage in check.


* `rangeMultiplier`

  A multiplier that scales the range of the propagation models used in the simulator. It affects the maximum range and coverage map cell size.


* `innerBounds` (x(min,max), y(min,max))

  An inner square area on which to collect statistics from. This helps the statistics module avoid fringe effects where the data might be suboptimal.


* `parking`

  Parking model configuration.

  - `seed`: a random seed to initialize random parking duration generators.
  - `inUse`: select a parking model to use, by name.
  - `<modelName>`: the parameters of a given model.


* `stats`

  Statistics module configuration.

  - `statsFolder`: subfolder to store statistics files in.
  - `collectionInterval`: for intervalled statistics, the time in seconds between each sampling event.
  - `collectionStartTime`: the time to start intervalled collection at. 
  - `obstructionMaskFile`: path to a file containing an obstruction mask that lists open and blocked cells. See `tools/buildObstructionMask` below.
  - `hooks`: a dictionary of (statistic, on/off) pairs. The specified statistic will be collected and saved to a file with the same name. See `Statistics.md` for a list.


* `decision`

  Decision module configuration.

  - `triggerDelay`: time, in seconds, to wait before the decision algorithms are executed (e.g., to allow cars to build their coverage maps).
  - `algorithm/inUse`: select a decision algorithm to use, by name.
  - `algorithm/<algorithmName>`: the parameters of a given algorithm.

  Decision algorithms:

  - `CellCoverageEffects`:
    - `kappa`, `lambda`, `mu`: coefficients for d_new, d_boost, d_sat.
    - `mapRequestReach`: choose from:
      - `1hop`, `2hop`: a 1-hop/2-hop request.
      - `geocast2r`: a geocast request to a circle of range 2*radioRange.
    - `saturationThreshold`: d_sat only starts to count above this value.

  - `WeightedProductModel`:
    - `wsig`, `wsat`, `wcov`, `wbat`: WPM attribute weights.
    - `minRedundancy`: desired RSU redundancy level, for the saturation attribute.
	- `mapRequestDepth`: how many hops to ask for coverage maps (implemented: 1, 2).
	- `disableThreshold`: decisions that disable RSUs must exceed this specified percentage over the null decision.

* `gis`

  The database connection parameters: host, port, database, username, password.


* `debug`

  A dictionary of (function, on/off) pairs. Enter a function name and a 'true' value to enable debug in that function. To see a list of debug points, run:

  ```bash
  $ find src -type f -iname '*.swift' -exec grep debug.contains {} +
  ```


* `tools`

  Simulation tools and extras.

  - `buildObstructionMask`: generage an obstruction mask from the provided Floating Car Data. The mask tags cells with [O]pen or [B]locked, depending on whether vehicles were seen at the cells or not.
