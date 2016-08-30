Configuration File
==================
A GISSUMO configuration file is an XML Property List with the .plist extension.


* `floatingCarDataFile`

  An XML containing vehicular Floating Car Data in timestep divisions, obtained with SUMO.


* `stopTime`

  The time at which the simulation should stop. GISSUMO will also not load FCD data belonging to timesteps that occur after this time.


* `innerBounds` (x(min,max), y(min,max))

  An inner square area on which to collect statistics from. This helps the statistics module avoid fringe effects where the data might be suboptimal.


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
