# The third-party C of the audio effects (README.md), built into one static library per platform with flags
# of its own: out of the tweak's -Werror, and its symbols hidden so none can clash with Spotify's.
#   make PLATFORM=ios|sim|mac [SANITIZE=thread|address]   ->   build/<platform>[-<sanitize>]/libsgaudio.a
PLATFORM ?= ios
SANITIZE ?=

ifeq ($(PLATFORM),ios)
  SDK := iphoneos
  TARGET := arm64-apple-ios16.0
else ifeq ($(PLATFORM),sim)
  SDK := iphonesimulator
  TARGET := arm64-apple-ios17.0-simulator
else ifeq ($(PLATFORM),mac)
  SDK := macosx
  TARGET := arm64-apple-macos13.0
else
  $(error PLATFORM is ios, sim or mac)
endif

BUILD := build/$(PLATFORM)$(if $(SANITIZE),-$(SANITIZE))
CC := xcrun -sdk $(SDK) clang
CFLAGS := -target $(TARGET) -O2 -g -w -fvisibility=hidden -DEEL_TARGET_PORTABLE -DNSEEL_LOOPFUNC_SUPPORT_MAXLEN=1048576 \
          -Ieel2-parser -Iwdl/eel2 $(if $(SANITIZE),-fsanitize=$(SANITIZE) -fno-omit-frame-pointer)

SOURCES := libbs2b/bs2b.c wdl/eel2/nseel-compiler.c wdl/eel2/nseel-eval.c wdl/eel2/nseel-ram.c eel2-parser/nseel-parse.c
OBJECTS := $(patsubst %.c,$(BUILD)/%.o,$(SOURCES))
HEADERS := $(wildcard libbs2b/*.h wdl/*.h wdl/eel2/*.h eel2-parser/*.h)

$(BUILD)/libsgaudio.a: $(OBJECTS)
	@rm -f $@
	@xcrun libtool -static -o $@ $^ 2>/dev/null

$(BUILD)/%.o: %.c $(HEADERS) Makefile
	@mkdir -p $(dir $@)
	@$(CC) $(CFLAGS) -c $< -o $@

.PHONY: clean
clean:
	rm -rf build
