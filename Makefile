TARGET := iphone:clang:6.1:5.0
ARCHS = armv7
INSTALL_TARGET_PROCESSES = AppStore itunesstored MobileStore Podcasts iBooks


include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AppStoreFix

AppStoreFix_FILES = Tweak.x ASFXBootstrapBridge.m ASFXStoreCompatibility.m
AppStoreFix_CFLAGS = -fobjc-arc -Wno-gcc-compat
AppStoreFix_FRAMEWORKS = Security

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += AppStoreFixPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk