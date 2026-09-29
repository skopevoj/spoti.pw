// Mod > Licenses: the mod's own license, then each third-party one the build ships code under, in full,
// since the MIT license asks for its text to travel with every copy.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"

static NSString *const kMIT =
    @"Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated "
    @"documentation files (the \"Software\"), to deal in the Software without restriction, including without "
    @"limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the "
    @"Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\n"
    @"The above copyright notice and this permission notice shall be included in all copies or substantial portions "
    @"of the Software.\n\n"
    @"THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED "
    @"TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE "
    @"AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF "
    @"CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER "
    @"DEALINGS IN THE SOFTWARE.";

static NSString *const kZlib =
    @"This software is provided 'as-is', without any express or implied warranty. In no event will the authors be "
    @"held liable for any damages arising from the use of this software.\n\n"
    @"Permission is granted to anyone to use this software for any purpose, including commercial applications, and "
    @"to alter it and redistribute it freely, subject to the following restrictions:\n\n"
    @"1. The origin of this software must not be misrepresented; you must not claim that you wrote the original "
    @"software. If you use this software in a product, an acknowledgment in the product documentation would be "
    @"appreciated but is not required.\n\n"
    @"2. Altered source versions must be plainly marked as such, and must not be misrepresented as being the "
    @"original software.\n\n"
    @"3. This notice may not be removed or altered from any source distribution.";

UIViewController *SGLicensesPage(void) {
    SGModRow *mod = SGLinkRow(@"spoti.pw", @"PolyForm Strict License 1.0.0", [SGRepoURL stringByAppendingString:@"/blob/main/LICENSE"]);
    SGModRow *bs2b = SGLinkRow(@"libbs2b", @"Crossfeed · MIT License", @"https://github.com/alexmarsev/libbs2b");
    SGModRow *wdl = SGLinkRow(@"WDL", @"Liveprog's EEL2 · zlib License", @"https://github.com/justinfrankel/WDL");
    return [[SGModPage alloc] initWithTitle:@"Licenses" intro:@"The mod's own license, and the code from others it includes." sections:@[
        SGSection(nil, @[mod]),
        SGNotedSection(nil, @[bs2b], [@"Copyright (c) 2005 Boris Mikhaylov\n\n" stringByAppendingString:kMIT]),
        SGNotedSection(nil, @[wdl], [@"Copyright (C) 2004-2013 Cockos Incorporated\nCopyright (C) 1999-2003 Nullsoft, Inc.\n\n"
                                     stringByAppendingString:kZlib]),
    ] footer:nil];
}
