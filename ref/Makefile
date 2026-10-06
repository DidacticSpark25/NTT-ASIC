# Builds the pq-crystals reference NTT harnesses used to cross-check the golden model.
CC     ?= gcc
CFLAGS ?= -O2 -Wall -Wno-unused-function

all: harness_kyber harness_dilithium

harness_kyber: harness.c kyber/ntt.c kyber/reduce.c
	$(CC) $(CFLAGS) -DSCHEME_KYBER -Ikyber -o $@ harness.c kyber/ntt.c kyber/reduce.c

harness_dilithium: harness.c dilithium/ntt.c dilithium/reduce.c
	$(CC) $(CFLAGS) -DSCHEME_DILITHIUM -Idilithium -o $@ harness.c dilithium/ntt.c dilithium/reduce.c

clean:
	rm -f harness_kyber harness_dilithium

.PHONY: all clean
