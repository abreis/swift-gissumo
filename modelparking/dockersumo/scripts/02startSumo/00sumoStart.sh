#!/bin/bash

nohup $(dirname $0)/sumoLooper.sh > sumo.log 2>&1 &
