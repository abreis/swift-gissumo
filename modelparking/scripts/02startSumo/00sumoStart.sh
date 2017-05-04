#!/bin/bash
ln -sfr ./interact/map_clean3.net.xml /work/map.net.xml
nohup $(dirname $0)/sumoLooper.sh > sumo.log 2>&1 &
