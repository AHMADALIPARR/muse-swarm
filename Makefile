CC      ?= gcc
CFLAGS  ?= -std=c11 -O2 -Wall -Wextra

all: fork
fork: fork.c
	$(CC) $(CFLAGS) -o $@ fork.c
test: fork
	sh tests/run-tests.sh
clean:
	rm -f fork
.PHONY: all test clean
