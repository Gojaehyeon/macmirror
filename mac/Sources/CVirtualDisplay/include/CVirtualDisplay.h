#ifndef CVIRTUALDISPLAY_H
#define CVIRTUALDISPLAY_H

#include <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle that owns a live virtual display.
/// While the handle is alive the display exists in the macOS display arrangement;
/// releasing it tears the display down.
typedef void *VDHandle;

/// Create a virtual (extended) display.
///
/// @param width        Mode width in pixels.
/// @param height       Mode height in pixels.
/// @param refreshRate  Refresh rate in Hz (e.g. 60.0).
/// @param hiDPI        Non-zero to mark the mode as HiDPI (Retina); the logical
///                     resolution becomes half of width/height.
/// @param name         Display name shown in System Settings (may be NULL).
/// @param outDisplayID Receives the CGDirectDisplayID on success (may be NULL).
/// @return An owning handle, or NULL on failure.
VDHandle VDCreate(unsigned int width,
                  unsigned int height,
                  double refreshRate,
                  int hiDPI,
                  const char *name,
                  unsigned int *outDisplayID);

/// CGDirectDisplayID backing the handle (0 if the handle is NULL).
unsigned int VDGetDisplayID(VDHandle handle);

/// Tear down the virtual display and free the handle.
void VDRelease(VDHandle handle);

#ifdef __cplusplus
}
#endif

#endif /* CVIRTUALDISPLAY_H */
