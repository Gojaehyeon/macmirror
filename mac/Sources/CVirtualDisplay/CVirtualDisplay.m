#import "CVirtualDisplay.h"
#import <Foundation/Foundation.h>

// ---------------------------------------------------------------------------
// Private CoreGraphics interfaces (from class-dump of CoreGraphics).
// These are undocumented; the same surface is used by BetterDummy/BetterDisplay.
// ---------------------------------------------------------------------------

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width
                       height:(unsigned int)height
                  refreshRate:(double)refreshRate;
@property(readonly, nonatomic) unsigned int width;
@property(readonly, nonatomic) unsigned int height;
@property(readonly, nonatomic) double refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic) unsigned int hiDPI;
@property(retain, nonatomic) NSArray *modes;
@end

@interface CGVirtualDisplayDescriptor : NSObject
@property(retain, nonatomic) dispatch_queue_t queue;
@property(retain, nonatomic) NSString *name;
@property(nonatomic) CGPoint whitePoint;
@property(nonatomic) CGPoint bluePrimary;
@property(nonatomic) CGPoint greenPrimary;
@property(nonatomic) CGPoint redPrimary;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int vendorID;
@property(copy, nonatomic) void (^terminationHandler)(void);
@end

@interface CGVirtualDisplay : NSObject
@property(readonly, nonatomic) unsigned int displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

// Owns the live CGVirtualDisplay so it isn't deallocated (which would tear the
// display down) until VDRelease is called.
@interface VDWrapper : NSObject
@property(strong, nonatomic) CGVirtualDisplay *display;
@end
@implementation VDWrapper
@end

// ---------------------------------------------------------------------------

VDHandle VDCreate(unsigned int width,
                  unsigned int height,
                  double refreshRate,
                  int hiDPI,
                  const char *name,
                  unsigned int *outDisplayID) {
    @autoreleasepool {
        CGVirtualDisplayDescriptor *desc = [[CGVirtualDisplayDescriptor alloc] init];
        desc.queue = dispatch_queue_create("com.mactesla.virtualdisplay", DISPATCH_QUEUE_SERIAL);
        desc.name = name ? [NSString stringWithUTF8String:name] : @"mactesla";

        // Headroom for the registered mode(s).
        desc.maxPixelsWide = width;
        desc.maxPixelsHigh = height;

        // Physical size assuming ~100 DPI; only affects reported size, not capture.
        desc.sizeInMillimeters = CGSizeMake(width * 25.4 / 100.0, height * 25.4 / 100.0);

        // Each virtual display needs a unique serial; reusing the same triple makes
        // macOS reject the second one (silent failure inside applySettings).
        static unsigned int gSerial = 1;
        desc.productID = 0x1234;
        desc.vendorID = 0x3456;
        desc.serialNum = gSerial++;

        // Standard sRGB primaries / D65 white point.
        desc.whitePoint   = CGPointMake(0.3127, 0.3290);
        desc.redPrimary   = CGPointMake(0.6800, 0.3200);
        desc.greenPrimary = CGPointMake(0.2650, 0.6900);
        desc.bluePrimary  = CGPointMake(0.1500, 0.0600);

        desc.terminationHandler = ^{
            // The system tore the display down (e.g. on logout). Nothing to do here;
            // VDRelease still owns the wrapper.
        };

        CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:desc];
        if (!display) {
            return NULL;
        }

        CGVirtualDisplaySettings *settings = [[CGVirtualDisplaySettings alloc] init];
        settings.hiDPI = hiDPI ? 1 : 0;

        CGVirtualDisplayMode *mode =
            [[CGVirtualDisplayMode alloc] initWithWidth:width
                                                 height:height
                                            refreshRate:refreshRate];
        settings.modes = @[mode];

        if (![display applySettings:settings]) {
            return NULL;
        }

        if (outDisplayID) {
            *outDisplayID = display.displayID;
        }

        VDWrapper *wrapper = [[VDWrapper alloc] init];
        wrapper.display = display;
        return (VDHandle)CFBridgingRetain(wrapper);
    }
}

unsigned int VDGetDisplayID(VDHandle handle) {
    if (!handle) {
        return 0;
    }
    VDWrapper *wrapper = (__bridge VDWrapper *)handle;
    return wrapper.display.displayID;
}

void VDRelease(VDHandle handle) {
    if (!handle) {
        return;
    }
    // Releases the wrapper -> releases CGVirtualDisplay -> display disappears.
    CFBridgingRelease(handle);
}
