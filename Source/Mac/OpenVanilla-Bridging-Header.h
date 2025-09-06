//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

// Enable Swift C++ interop for OpenVanilla C++ classes
#import "OVInputMethodController.h"

// Import OpenVanilla C++ framework headers for Swift C++ interop
#ifdef __cplusplus
#include "OpenVanilla.h"
#include "OVTextBufferImpl.h"
#include "OVTextBufferCombinator.h"
#endif
