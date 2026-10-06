TARGET := iphone:clang:6.0:6.0
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AppStoreFixPrefs

AppStoreFixPrefs_FILES = ASFXRootListController.m
AppStoreFixPrefs_FRAMEWORKS = UIKit
AppStoreFixPrefs_PRIVATE_FRAMEWORKS = Preferences
AppStoreFixPrefs_INSTALL_PATH = /Library/PreferenceBundles
AppStoreFixPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
