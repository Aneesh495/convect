CC ?= clang
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -O3 -fPIC
LDFLAGS ?= -lm

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    SHLIB_EXT := dylib
    SHLIB_FLAGS := -dynamiclib
else
    SHLIB_EXT := so
    SHLIB_FLAGS := -shared
endif

BUILD_DIR := build
STATIC_LIB := $(BUILD_DIR)/libconvect_spatial.a
SHARED_LIB := $(BUILD_DIR)/libconvect_spatial.$(SHLIB_EXT)

SRCS := spatial_types.c \
        rtree/rtree.c \
        geohash/geohash.c \
        quadtree/quadtree.c \
        hilbert/hilbert.c \
        h3/h3_lite.c \
        lsm/spatial_lsm.c

OBJS := $(patsubst %.c,$(BUILD_DIR)/%.o,$(SRCS))

.PHONY: all clean test

all: $(STATIC_LIB) $(SHARED_LIB)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)/rtree $(BUILD_DIR)/geohash $(BUILD_DIR)/quadtree $(BUILD_DIR)/hilbert $(BUILD_DIR)/h3 $(BUILD_DIR)/lsm

$(BUILD_DIR)/%.o: %.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(STATIC_LIB): $(OBJS)
	ar rcs $@ $^

$(SHARED_LIB): $(OBJS)
	$(CC) $(SHLIB_FLAGS) -o $@ $^ $(LDFLAGS)

test: all
	$(CC) $(CFLAGS) ../tests/c/test_spatial.c $(STATIC_LIB) -o $(BUILD_DIR)/test_spatial $(LDFLAGS)
	$(BUILD_DIR)/test_spatial

clean:
	rm -rf $(BUILD_DIR)
