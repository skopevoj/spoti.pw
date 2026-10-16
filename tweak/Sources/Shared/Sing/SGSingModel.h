// Sing's voice model on this iPhone. It is not in the IPA: the app downloads its five files from the model
// host once, each checked against the size and the SHA-256 pinned in SGSingModel.m (nothing the server says
// is trusted), into a staging folder, and moves them into place only when every one of them is right:
// Library/Application Support/spoti.pw/Sing/separator.mlmodelc in Spotify's container, kept out of the
// iCloud backup. The download runs in a background URL session, so it goes on while Spotify is away; a
// launch picks up one left running (SingModel.x), and a stopped one resumes from what already came in.
// Threading: main thread only; SGSingModelDidChangeNotification is posted on it.
#import <Foundation/Foundation.h>

// Set while a download should be running, to 1 when it keeps off metered networks and 2 when it may use
// them: a launch that finds it picks the download up.
#define SGKeySingModelDownload @"spotifyglass.sing.modelDownload"

typedef NS_ENUM(NSInteger, SGSingModelState) {
    SGSingModelMissing,       // not on this iPhone; SGSingModelReceived says how much a stopped download kept
    SGSingModelDownloading,   // files coming in, or waiting for a network to come in on
    SGSingModelChecking,      // everything is in, the last files are being checked
    SGSingModelInstalled,     // checked and in place
};

// Posted as the state or the progress changes, the progress at most four times a second.
extern NSNotificationName const SGSingModelDidChangeNotification;

SGSingModelState SGSingModelCurrentState(void);
int64_t SGSingModelSize(void);       // all of it, as pinned
int64_t SGSingModelReceived(void);   // what of it is on this iPhone, checked or not
NSString *SGSingModelFailure(void);  // why the last download stopped short, nil unless it did
// What SGSingModelPath answers without the downloaded model: Sing still works, on the built-in separator
// (SGStemCenterSeparator.swift), which needs nothing downloaded and is not as clean.
extern NSString *const SGSingModelBuiltIn;
BOOL SGSingModelIsBuiltIn(NSString *path);
NSString *SGSingModelPath(void);     // the installed separator.mlmodelc, or SGSingModelBuiltIn without one
NSString *SGSingModelBytesText(int64_t bytes);   // "467 MB", in the units the rows use

// What keeps a download from starting: too little free space, said with how much it needs. Nil when none.
NSString *SGSingModelSpaceProblem(void);

typedef NS_ENUM(NSInteger, SGSingModelNetwork) {
    SGSingModelOffline,
    SGSingModelUnmetered,   // Wi-Fi or wired
    SGSingModelMetered,     // cellular, a personal hotspot or Low Data Mode
};
// The network the phone is on now, asked once; `done` runs on the main queue.
void SGSingModelCheckNetwork(void (^done)(SGSingModelNetwork network));

// Starts the download, or resumes a stopped one. Without `metered` it keeps off cellular and Low Data Mode
// networks and waits for Wi-Fi when that is all there is.
void SGSingModelDownload(BOOL metered);
void SGSingModelCancel(void);   // keeps what came in, for the next Download
void SGSingModelRemove(void);   // the model and anything half downloaded

// SingModel.x: the app delegate hands over the background session's events, and a launch reconnects to a
// download that was running.
BOOL SGSingModelHandlesSession(NSString *identifier, void (^completion)(void));
void SGSingModelReconnect(void);
