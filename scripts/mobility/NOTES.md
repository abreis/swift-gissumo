The scripts in this folder generate Floating Car Data from OpenStreetMap data.

The data is processed in the following order:
OSM -> SUMO Net -> SUMO Trips -> SUMO Routes -> SUMO FCD

Each individual script moves from one step to the next, except for `osm5fcd.sh`, which runs all five steps in sequence, and does not recreate data that has already been computed.
