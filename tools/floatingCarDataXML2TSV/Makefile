XCRUN = xcrun --sdk macosx
CC = swiftc
CMODE = -emit-executable
OPTIMIZATION = -O -whole-module-optimization
INPUTS := $(shell find src -type f -iname *.swift)
OUTPUT = build/floatingCarDataXML2TSV

all:
	${XCRUN} ${CC} ${CMODE} ${OPTIMIZATION} ${INPUTS} -o ${OUTPUT}

clean:
	rm -rf ${OUTPUT}
