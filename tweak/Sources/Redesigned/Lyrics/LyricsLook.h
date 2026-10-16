// The lyrics look editor (Mod Settings > Lyrics > Lyrics look, in the redesign): the size and weight of the
// redesign's Apple Music style lyrics, how much the lines away from the sung one blur, and how bright the
// lines not yet sung are. SGRKaraokeView reads them as it lays a song out and lays it out again as one
// changes, so everything applies at once, to every lyrics view there is.
#import <UIKit/UIKit.h>

#define SGRKeyLyricsLookSize @"spotifyglass.redesign.lyricsLook.size"       // percent of Apple Music's 30 pt, 100 unset
#define SGRKeyLyricsLookWeight @"spotifyglass.redesign.lyricsLook.weight"   // index into the page's weights, Bold unset
#define SGRKeyLyricsLookBlur @"spotifyglass.redesign.lyricsLook.blur"       // percent of the blur, 100 unset, 0 none
#define SGRKeyLyricsLookDim @"spotifyglass.redesign.lyricsLook.dim"         // percent opacity of a line not lit, 30 unset

// Posted on the main queue when any of them changes.
extern NSNotificationName const SGRLyricsLookDidChangeNotification;

CGFloat SGRLyricsLookScale(void);        // 1 for Apple Music's size
UIFontWeight SGRLyricsLookWeight(void);  // the lyrics' and the pronunciation's
UIFontWeight SGRLyricsLookLightWeight(void);   // the translation's: a step lighter
CGFloat SGRLyricsLookBlurScale(void);    // 1 for Apple Music's blur, 0 for none
CGFloat SGRLyricsLookDim(void);          // a line not lit, as an alpha

@class SGModRow;
// The Lyrics page's row opening the editor.
SGModRow *SGRLyricsLookRow(void);
