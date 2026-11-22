TARGET := iphone:clang:6.1:5.0
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AppStoreFixPrefs

AppStoreFixPrefs_FILES = ASFXRootListController.m
AppStoreFixPrefs_FRAMEWORKS = UIKit
AppStoreFixPrefs_PRIVATE_FRAMEWORKS = Preferences
AppStoreFixPrefs_INSTALL_PATH = /Library/PreferenceBundles
AppStoreFixPrefs_CFLAGS = -fobjc-arc -Wno-gcc-compat

include $(THEOS_MAKE_PATH)/bundle.mk
