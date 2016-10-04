- `00setup.sh` - This script generates many sets of Floating Car Data by incrementing a starting seed. All relevant parameters are settable in the first few lines.

- `01simulateParallel.sh` - This script automates simulations based on FCD files. It creates a subfolder for each FCD, and stores the simulation log and stats files there. This is a parallel version of `01simulate.sh`: it runs multiple gissumo copies on separate threads, each using a separate GIS database.

Be sure to provide an obstruction mask before running a long set of simulations.

Be sure to use the latest version of the GIS setup script, that creates multiple GIS databases (named gis0..gis7) with the same obstruction data.
