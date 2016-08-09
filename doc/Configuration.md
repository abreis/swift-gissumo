Configuration File
==================
A GISSUMO configuration file is an XML Property List with the .plist extension.


* floatingCarDataFile

  An XML containing vehicular Floating Car Data in timestep divisions, obtained with SUMO.


* stopTime

  The time at which the simulation should stop. GISSUMO will also not load FCD data belonging to timesteps that occur after this time.


* innerBounds (x(min,max), y(min,max))

  An inner square area on which to collect statistics from. This helps the statistics module avoid fringe effects where the data might be suboptimal.


* stats

  A dictionary of (statistic, filename) pairs. The specified statistic will be collected and saved to the specified file. See `Statistics.md` for a list.


* gis

  The database connection parameters: host, port, database, username, password.


* debug

  A dictionary of (function, on/off) pairs. Enter a function name and a 'true' value to enable debug in that function. To see a list of debug points, run:
  
  $ find src -type f -iname '*.swift' -exec grep debug.contains {} +
