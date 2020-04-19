CFLAGS += -std=gnu90

.PHONY: default
default: tracksplit

tracksplit: tracksplit.o common.o
	$(CC) $(CFLAGS) -o $@ $+ -lm

.PHONY: clean
clean:
	rm -f *.o tracksplit
