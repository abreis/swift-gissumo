#!/bin/bash
ln -sfr ./interact/map_clean3.net.xml /work/map.net.xml
gunzip ./interact/map_clean3.net.xml.gz
gunzip ./interact/modules/perSecondArrayNorm.csv.gz

nohup $(dirname $0)/sumoLooper.sh > sumo.log 2>&1 &
