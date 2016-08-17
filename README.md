# Swift-GISSUMO

## Getting Started
Edit [`module.map`](https://github.com/abreis/swift-gissumo/blob/master/src/lib/libpq/module.map) and point it to the location of `libpq-fe.h` in your system.

## Database Access
To enable database access from other hosts (for example, to visualize the shapefile data with QGIS), edit [`pg_hba.conf`](https://github.com/abreis/swift-gissumo/blob/master/scripts/pg_hba.conf) and add an entry for your specific host or network. The database initialization scripts will load this file, and the provided Dockerfile exposes port 5432 on the container by default.

## Common Errors

> Error: The specified inner city bounds are larger than the outer bounds.

If the simulation time is short, the observed city size (obtained from vehicle positions in the Floating Car Data) may be smaller than expected, and smaller than the inner bounds specified. Increase simulation time or reduce the inner bounds.

> Error: Tried to initialize an even-sized cell map with center coordinates.

The simulator assumes that a Roadside Unit's coverage map is circular, therefore its cell map must be odd in both dimensions so that the RSU sits in the centre cell.

> [on stat file] Please generate and provide an obstruction mask first.

The statistics module relies on a map of obstructions to act as a mask, otherwise it cannot know the difference between, e.g., a cell where coverage is Zero because no RSUs cover it, and a cell where coverage is Zero because it is a building and not a road. Generage an obstruction mask by setting `tools/buildObstructionMask` to `true` in the configuration, then provide a large enough set of Floating Car Data and a large enough `stopTime` to be reasonably confident that vehicles traversed all roads in the city. The resulting map can be used for all (smaller) simulations.

## License
See the [`LICENSE`](https://github.com/abreis/swift-gissumo/blob/master/LICENSE) file.