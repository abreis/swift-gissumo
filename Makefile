XCRUN = xcrun -sdk macosx --toolchain com.apple.dt.toolchain.Swift_2_3
CC = swiftc
CMODE = -emit-executable
OPTIMIZATION = -O -whole-module-optimization
INPUTS := $(shell find src -type f -iname *.swift)
SEARCHPATH = src/lib/libpq
OUTPUT = build/gissumo_fast

all:
	${XCRUN} ${CC} ${CMODE} ${OPTIMIZATION} ${INPUTS} -I ${SEARCHPATH} -o ${OUTPUT}

clean:
	rm -rf ${OUTPUT}
