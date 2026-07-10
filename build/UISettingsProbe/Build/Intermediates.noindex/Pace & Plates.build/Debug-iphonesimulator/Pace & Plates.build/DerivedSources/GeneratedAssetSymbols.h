#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"Jorsh.WorkingOut";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "BackgroundColor" asset catalog color resource.
static NSString * const ACColorNameBackgroundColor AC_SWIFT_PRIVATE = @"BackgroundColor";

/// The "SecondaryBackgroundColor" asset catalog color resource.
static NSString * const ACColorNameSecondaryBackgroundColor AC_SWIFT_PRIVATE = @"SecondaryBackgroundColor";

/// The "TextColor" asset catalog color resource.
static NSString * const ACColorNameTextColor AC_SWIFT_PRIVATE = @"TextColor";

/// The "LaunchImage" asset catalog image resource.
static NSString * const ACImageNameLaunchImage AC_SWIFT_PRIVATE = @"LaunchImage";

/// The "PPWorkoutIcon" asset catalog image resource.
static NSString * const ACImageNamePPWorkoutIcon AC_SWIFT_PRIVATE = @"PPWorkoutIcon";

#undef AC_SWIFT_PRIVATE
