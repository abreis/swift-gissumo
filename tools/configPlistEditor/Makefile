CC = swiftc
CMODE = -emit-executable
OPTIMIZATION = -O -whole-module-optimization
INPUTS := $(shell find src -type f -iname *.swift)
OUTPUT = build/configPlistEditor

all:
	${CC} ${CMODE} ${OPTIMIZATION} ${INPUTS} -o ${OUTPUT}

clean:
	rm -rf ${OUTPUT}