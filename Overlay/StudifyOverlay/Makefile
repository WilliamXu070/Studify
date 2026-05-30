TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Spotify
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = StudifyOverlay

StudifyOverlay_FILES = $(shell find Sources/StudifyOverlay -name '*.swift') $(shell find Sources/StudifyOverlayC -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp')
StudifyOverlay_SWIFTFLAGS = -ISources/StudifyOverlayC/include -Osize
StudifyOverlay_CFLAGS = -fobjc-arc -ISources/StudifyOverlayC/include -Os
StudifyOverlay_FRAMEWORKS = UIKit Foundation AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk
