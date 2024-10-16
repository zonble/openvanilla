#import "OVKeyMapping.h"

using namespace OpenVanilla;

@implementation OVKeyMapping

+ (UniChar)remapCode:(UniChar)unicharCode
{
    UniChar remappedKeyCode = unicharCode;

    // remap function key codes
    switch (unicharCode) {
        case NSUpArrowFunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::Up;
            break;
        case NSDownArrowFunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::Down;
            break;
        case NSLeftArrowFunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::Left;
            break;
        case NSRightArrowFunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::Right;
            break;
        case NSDeleteFunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::Delete;
            break;
        case NSHomeFunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::Home;
            break;
        case NSEndFunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::End;
            break;
        case NSPageUpFunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::PageUp;
            break;
        case NSPageDownFunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::PageDown;
            break;
        case NSF1FunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::F1;
            break;
        case NSF2FunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::F2;
            break;
        case NSF3FunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::F3;
            break;
        case NSF4FunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::F4;
            break;
        case NSF5FunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::F5;
            break;
        case NSF6FunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::F6;
            break;
        case NSF7FunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::F7;
            break;
        case NSF8FunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::F8;
            break;
        case NSF9FunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::F9;
            break;
        case NSF10FunctionKey:
            remappedKeyCode = (UniChar)OVKeyCode::F10;
            break;
    }
    return remappedKeyCode;
}


@end
