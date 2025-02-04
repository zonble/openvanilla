// ArrayKeySequence.h: KeySequence class for Array Input Method
//
// Copyright (c) 2004-2008 The OpenVanilla Project (http://openvanilla.org)
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Neither the name of OpenVanilla nor the names of its contributors
//    may be used to endorse or promote products derived from this software
//    without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#ifndef _ARRAYKEYSEQUENCE_H
#define _ARRAYKEYSEQUENCE_H

#include "LegacyOpenVanilla.h"
#include "OVKeySequence.h"
#include <string>

class ArrayKeySequence : public OVKeySequenceSimple
{
protected:
    OpenVanilla::OVCINDataTable* cinTable;
public:
    ArrayKeySequence(OpenVanilla::OVCINDataTable* tab) : cinTable(tab) {}
    virtual int length() { return len; }
    virtual bool add(char c){
//        if (valid(c) == 0) return 0;
        return OVKeySequenceSimple::add(c);
    }
    virtual int valid(char c){
        std::string inKey(1, c);
        if (cinTable->findKeyname(inKey).empty()) return 0;
        return 1;
    
    }
    virtual std::string& compose(std::string& s){
        for (int i=0; i<len; i++)
        {
            std::string inKey;
            inKey.push_back(seq[i]);
            s.append(cinTable->findKeyname(inKey));
        }
        return s;
    }
    virtual char* getSeq() { return seq; }

    virtual bool hasOnlyWildcardCharacter()
    {
        if (len == 0) {
            return false;
        }
        for (int i = 0; i < len; i++) {
            if (seq[i] != '?' && seq[i] != '*') {
                return false;
            }
        }
        return true;
    }

	virtual bool hasWildcardCharacter()
	{
        for (int i = 0; i < len; i++) {
            if (seq[i] == '?' || seq[i] == '*') {
                return true;
            }
        }

		return false;
	}
};

#endif
