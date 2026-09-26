// The areas the redesign stripped and SGRRepaint.x keeps transparent when Spotify repaints them, each
// set by the part of the redesign that owns it.
#import <UIKit/UIKit.h>

extern __weak UIView *sgr_nowPlayingRoot;   // Redesigned/NowPlayingBar/NowPlayingBar.x, the bar
extern __weak UIView *sgr_nowPlayingCard;   // the bar's painted card, learnt from the album-colour paint
// Whether Spotify painted `view` in the now playing bar the way it paints a card, though the paint was
// kept off: the track's card, or another strip such as a Jam's.
BOOL SGRPaintedAsCard(UIView *view);
extern __weak UIView *sgr_lyricsPageRoot;   // Redesigned/Lyrics/LyricsPage.x
// Redesigned/Playlist/PlaylistField.x, the playlist page. Only the base surface Spotify paints the page,
// its list and its rows with goes clear here: the artwork field is underneath, and the greys of a
// placeholder or a badge are what still has to read against it.
extern __weak UIView *sgr_playlistRoot;
// Redesigned/Album/AlbumField.x, the album page, kept clear the same way and for the same reason.
extern __weak UIView *sgr_albumRoot;
// Redesigned/Artist/ArtistField.x, the artist page, kept clear the same way and for the same reason.
extern __weak UIView *sgr_artistRoot;
