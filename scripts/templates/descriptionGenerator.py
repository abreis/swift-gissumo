#!/usr/bin/env python3
# This script will generate a description file, pulling entries from a plist config file and printing the ones that match a provided template.

import os
import plistlib
import shutil
import sys
import optparse
import collections


# Requires Python >3.5
assert sys.version_info >= (3,5)


# Process command line options
parser = optparse.OptionParser()
parser.add_option("-t", "--template", dest="templateFile", default="description.template", help="read list of entries from template", metavar="FILE")
parser.add_option("-c", "--config", dest="configFile", default="config.plist", help="fetch entries from configuration file", metavar="FILE")
parser.add_option("-o", "--output", dest="outputFile", default="description.txt", help="write description to file", metavar="FILE")

(options, args) = parser.parse_args()

if not os.path.isfile(options.templateFile):
	print("Error: Please provide a template file.")
	sys.exit(1)

if not os.path.isfile(options.configFile):
	print("Error: Please provide a configuration file.")
	sys.exit(1)


# Tree code
def tree(): return collections.defaultdict(tree)

def setInTree(t, path, value):
  i = 0
  for key in path:
    i = i + 1
    if i == len(path) and value != None:
      t[key] = value
    t = t[key]

def printTree(tree, depth=0):
	for rootKey in sorted(tree.keys()):
		print("{:s}{:s}".format(' '*depth, rootKey),  end='')
		if type(tree[rootKey]) == collections.defaultdict:
			print('')
			printTree(tree[rootKey], depth+1)
		elif tree[rootKey] != None:
			print(':', tree[rootKey])

def getNestedTreeEntry(tree, path):
	for key in path:
		tree = tree[key]
	return tree

# Read template file
with open(options.templateFile) as f_in:
	# read and strip \n
	entries = (line.rstrip() for line in f_in)
	# strip empties
	entries = list(line for line in entries if line)


# Push template entries into a tree
entriesTree = tree()

with open(options.configFile, 'rb') as configFileHandle:
	configFileDict = plistlib.load(configFileHandle, fmt=plistlib.FMT_XML)
	for entry in entries:
		entryComponents = entry.split('.')
		getNestedTreeEntry(configFileDict, entryComponents)
		setInTree(entriesTree, entryComponents, getNestedTreeEntry(configFileDict, entryComponents))

printTree(entriesTree)
