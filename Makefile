XCRUN = xcrun --sdk macosx
CC = swiftc
CMODE = -emit-executable
OPTIMIZATION = -O -whole-module-optimization
INPUTS := $(shell find src -type f -iname *.swift)
SEARCHPATH = src/lib/libpq
OUTPUT = build/gissumo_fast

all:
	${XCRUN} ${CC} ${CMODE} ${OPTIMIZATION} ${INPUTS} -I ${SEARCHPATH} -o ${OUTPUT}
	@shasum ${OUTPUT}

clean:
	rm -rf ${OUTPUT}
