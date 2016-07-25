CC = swiftc
CMODE = -emit-executable
INPUTS := $(shell find src -type f -iname '*.swift')
SEARCHPATH = src/lib/libpq
OUTPUT = build/gissumoc

all:
	${CC} ${CMODE} ${INPUTS} -I ${SEARCHPATH} -o ${OUTPUT}

clean:
	rm -rf ${OUTPUT}