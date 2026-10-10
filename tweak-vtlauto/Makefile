TARGET := iphone:clang:latest:16.0
ARCHS := arm64
FINALPACKAGE := 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := vtlauto
vtlauto_FILES := Sources/VTLAuto.x
vtlauto_CFLAGS := -fobjc-arc
vtlauto_FRAMEWORKS := UIKit
# Runtime swizzling instead of Substrate so the dylib has no extra dependency
# inside the IPA, same reasoning as the main tweak/Makefile.
vtlauto_LOGOS_DEFAULT_GENERATOR := internal

include $(THEOS_MAKE_PATH)/tweak.mk
