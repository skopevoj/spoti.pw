// The Lyrics page's Gemini section (GeminiTranslate.h): the switch, and the key while it is on.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "GeminiTranslate.h"

SGModSection *SGGeminiSection(void) {
    SGModRow *on = SGOptionRow(@"Translate with Gemini", @"For lyrics that come without a translation", SGKeyLyricsGemini);
    // Turned on while a song plays, it translates that song straight away.
    on.changed = ^(BOOL value) {
        [NSNotificationCenter.defaultCenter postNotificationName:SGGeminiKeyDidChangeNotification object:nil];
    };
    SGModRow *key = SGTextRow(@"Gemini API key", @"Paste an API key from Google AI Studio.", @"AIza…",
        ^NSString *{
            NSString *shown = SGGeminiKeyShown();
            return !shown ? @"Not set" : SGGeminiProblem() ?: shown;
        },
        ^NSString *(NSString *text) { return SGGeminiSetKey(text); });
    key.refreshOn = SGGeminiKeyDidChangeNotification;
    SGWaitsOn(key, SGKeyLyricsGemini, NO);
    SGModSection *section = SGNotedSection(@"Gemini translation", @[on, key],
        @"Lyrics without a translation are sent, text only, to Google's Gemini with a key of your own and translated "
         "into the translation language above, or this iPhone's language when that is Any. Turn translations on from "
         "the lyrics' own button. Make a free key at Google AI Studio.");
    section.footerLink = @"https://aistudio.google.com/apikey";
    return section;
}
