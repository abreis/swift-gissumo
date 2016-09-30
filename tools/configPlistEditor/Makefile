XCRUN = xcrun --toolchain com.apple.dt.toolchain.Swift_2_3
CC = swiftc
CMODE = -emit-executable
OPTIMIZATION = -O -whole-module-optimization
INPUTS := $(shell find src -type f -iname *.swift)
OUTPUT = build/configPlistEditor

all:
	${XCRUN} ${CC} ${CMODE} ${OPTIMIZATION} ${INPUTS} -o ${OUTPUT}

clean:
	rm -rf ${OUTPUT}