// Gemini translation (Mod Settings > Lyrics, in the redesign): lyrics that come without a translation in
// the language asked for are translated line by line by Google's Gemini, with a key of the user's own
// (aistudio.google.com/apikey, free within Google's limits), and show under each line the way a
// source's own translation does (Redesigned/Lyrics/LyricsText.h). The whole song goes in one request
// as a numbered list and comes back as a JSON array of the same length; anything else is dropped.
// Answers are kept in memory for the session, by the text of the lines and the language.
//
// The key is stored under spotipw.gemini.key, outside the spotifyglass. prefix, so no settings
// backup, diagnostics dump or reset carries it, the way the Spicy Lyrics key is kept.
#import <Foundation/Foundation.h>

#define SGKeyLyricsGemini @"spotifyglass.lyricsGemini"   // off until switched on

extern NSNotificationName const SGGeminiKeyDidChangeNotification;

// The key as the row shows it (its ends only), nil when none is stored.
NSString *SGGeminiKeyShown(void);
// What is wrong with the text as a key, or nil once it is stored; an empty text removes the key.
NSString *SGGeminiSetKey(NSString *text);
// The last refusal from Google, said on the row, nil while none.
NSString *SGGeminiProblem(void);
// The language translations are made in: the Lyrics page's, or this iPhone's own when that says Any.
NSString *SGGeminiTargetLanguage(void);

@class SGModSection;
// GeminiSettings.m: the Lyrics page's section, the switch and the key.
SGModSection *SGGeminiSection(void);
