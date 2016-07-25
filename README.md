# Swift-GISSUMO

## Getting Started
Edit [`module.map`](https://github.com/abreis/swift-gissumo/blob/master/src/lib/libpq/module.map) and point it to the location of `libpq-fe.h` in your system.

## Database Access
To enable database access from other hosts (for example, to visualize the shapefile data with QGIS), edit the [`pg_hba.conf`](https://github.com/abreis/swift-gissumo/blob/master/scripts/pg_hba.conf) and add an entry for your specific host or network. The database initialization scripts will load this file, and the provided Dockerfile exposes port 5432 on the container by default.

## License
See the [`LICENSE`](https://github.com/abreis/swift-gissumo/blob/master/LICENSE) file.
