//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import "OVInputMethodController.h"

// C++ headers for Swift C++ interop
#ifdef __cplusplus
#include <string>
#include "../../../Packages/OpenVanilla/Sources/OpenVanilla/include/OVKey.h"
#include "../../../Packages/OpenVanilla/Sources/OpenVanillaImpl/include/OVTextBufferImpl.h"
#include "../../../Packages/OpenVanilla/Sources/OpenVanilla/include/OVEventHandlingContext.h"
#include "../../../Packages/OpenVanilla/Sources/OpenVanillaImpl/include/OVTextBufferCombinator.h"
#include "../../../Packages/OpenVanilla/Sources/OpenVanilla/include/OVKeyCode.h"

// Make C++ types available to Swift
using OVTextBufferImplCpp = OpenVanilla::OVTextBufferImpl;
using OVEventHandlingContextCpp = OpenVanilla::OVEventHandlingContext;
using OVKeyCpp = OpenVanilla::OVKey;
using OVTextBufferCombinatorCpp = OpenVanilla::OVTextBufferCombinator;
#endif
