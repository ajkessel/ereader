CC = arm-kobo-linux-gnueabihf-c++
CFLAGS = -fPIC -O2 -Wall
LDFLAGS = -shared
TARGET = instapapersecrets.so
SRC = src/secrets.cpp

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	rm -f $(TARGET)

.PHONY: clean