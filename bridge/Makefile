CC ?= clang
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -O3 -fPIC
LDFLAGS ?= -lm

JAVA_HOME ?= $(shell /usr/libexec/java_home 2>/dev/null || echo "/usr/lib/jvm/default-java")
JNI_INCLUDES := -I$(JAVA_HOME)/include

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    SHLIB_EXT := dylib
    SHLIB_FLAGS := -dynamiclib
    JNI_INCLUDES += -I$(JAVA_HOME)/include/darwin
else
    SHLIB_EXT := so
    SHLIB_FLAGS := -shared
    JNI_INCLUDES += -I$(JAVA_HOME)/include/linux
endif

BUILD_DIR := build
TARGET := $(BUILD_DIR)/libconvect_spatial_jni.$(SHLIB_EXT)
INDEX_LIB := ../index/build/libconvect_spatial.a

SRCS := convect_spatial_bridge.c
OBJS := $(BUILD_DIR)/convect_spatial_bridge.o

.PHONY: all clean

all: $(TARGET)

$(INDEX_LIB):
	$(MAKE) -C ../index all

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(OBJS): $(SRCS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(JNI_INCLUDES) -I../index -c $< -o $@

$(TARGET): $(OBJS) $(INDEX_LIB)
	$(CC) $(SHLIB_FLAGS) -o $@ $(OBJS) $(INDEX_LIB) $(LDFLAGS)

clean:
	rm -rf $(BUILD_DIR)
