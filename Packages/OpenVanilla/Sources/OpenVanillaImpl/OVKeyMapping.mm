//
// OVKeyMapping.m
//
// Copyright (c) 2004-2012 Lukhnos Liu (lukhnos at openvanilla dot org)
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.
//

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
