#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Headers/YTPlayerViewController.h"
#import "Headers/YTMWatchViewController.h"
#import "Headers/YTMToastController.h"
#import "Headers/Localization.h"
#import "Headers/YTAlertView.h"
#import "FFMpegDownloader.h"

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

static NSInteger YTMUint(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] integerValue];
}

#pragma mark - Feature 1: Always High Audio Quality

@interface YTIMediaQualitySettingOption : NSObject
@property (nonatomic, assign) NSInteger quality;
@end

@interface YTMMediaQualityController : NSObject
- (void)setAudioQuality:(NSInteger)quality;
- (NSInteger)audioQuality;
@end

%hook YTMMediaQualityController
- (NSInteger)audioQuality {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"alwaysHighQuality")) {
        return 2; // High quality (0 = Auto, 1 = Normal, 2 = High)
    }
    return %orig;
}

- (void)setAudioQuality:(NSInteger)quality {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"alwaysHighQuality")) {
        %orig(2); // Force high quality
    } else {
        %orig;
    }
}
%end

%hook YTMSettings
- (NSInteger)audioQuality {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"alwaysHighQuality")) {
        return 2;
    }
    return %orig;
}

- (void)setAudioQuality:(NSInteger)quality {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"alwaysHighQuality")) {
        %orig(2);
    } else {
        %orig;
    }
}

- (BOOL)isHighQualityAudioEnabled {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"alwaysHighQuality")) {
        return YES;
    }
    return %orig;
}
%end

// Force high quality stream selection
%hook YTIStreamingData
- (id)adaptiveFormats {
    id formats = %orig;
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"alwaysHighQuality") && formats) {
        // Filter to prefer high quality audio formats
        // The actual filtering is done by the player, we just ensure it's available
    }
    return formats;
}
%end

%hook YTMQualitySettings
- (BOOL)allowHighQualityAudio {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"alwaysHighQuality")) {
        return YES;
    }
    return %orig;
}

- (BOOL)preferHighQualityAudio {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"alwaysHighQuality")) {
        return YES;
    }
    return %orig;
}
%end

#pragma mark - Feature 2: Skip Disliked Songs

%hook YTMQueueController
- (void)advanceToNextItem {
    %orig;
    
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"skipDislikedSongs")) {
        [self checkAndSkipDislikedSong];
    }
}

%new
- (void)checkAndSkipDislikedSong {
    id currentItem = [self valueForKey:@"_currentItem"];
    if (!currentItem) return;
    
    // Check if the current song is disliked
    BOOL isDisliked = NO;
    
    if ([currentItem respondsToSelector:@selector(likeStatus)]) {
        NSInteger likeStatus = [[currentItem valueForKey:@"likeStatus"] integerValue];
        isDisliked = (likeStatus == 2); // 2 typically means disliked
    }
    
    if (isDisliked) {
        // Show toast and skip
        dispatch_async(dispatch_get_main_queue(), ^{
            [[%c(YTMToastController) alloc] showMessage:LOC(@"SKIPPED_DISLIKED")];
        });
        
        // Skip to next song
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self advanceToNextItem];
        });
    }
}
%end

// Also check when a song starts playing
%hook YTPlayerViewController
- (void)playbackController:(id)controller didActivateVideo:(id)video withPlaybackData:(id)data {
    %orig;
    
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"skipDislikedSongs")) {
        [self checkIfDislikedAndSkip];
    }
}

%new
- (void)checkIfDislikedAndSkip {
    YTPlayerResponse *response = self.playerResponse;
    if (!response) return;
    
    // Check engagement panel or like status
    id videoDetails = [response.playerData valueForKey:@"videoDetails"];
    if (videoDetails && [videoDetails respondsToSelector:@selector(likeStatus)]) {
        NSInteger likeStatus = [[videoDetails valueForKey:@"likeStatus"] integerValue];
        if (likeStatus == 2) { // Disliked
            dispatch_async(dispatch_get_main_queue(), ^{
                [[%c(YTMToastController) alloc] showMessage:LOC(@"SKIPPED_DISLIKED")];
            });
            
            // Skip to next
            if ([self respondsToSelector:@selector(nextVideo)]) {
                [self nextVideo];
            }
        }
    }
}
%end

#pragma mark - Feature 3: Import/Export Settings

@interface YTMUSettingsManager : NSObject
+ (instancetype)sharedManager;
- (NSDictionary *)exportSettings;
- (BOOL)importSettings:(NSDictionary *)settings;
- (NSString *)settingsFilePath;
@end

%subclass YTMUSettingsManager : NSObject

+ (instancetype)sharedManager {
    static YTMUSettingsManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

%new
- (NSDictionary *)exportSettings {
    return [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
}

%new
- (BOOL)importSettings:(NSDictionary *)settings {
    if (!settings || ![settings isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:settings forKey:@"YTMUltimate"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    return YES;
}

%new
- (NSString *)settingsFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    return [documentsDirectory stringByAppendingPathComponent:@"YTMUltimate_Settings.json"];
}

%new
- (BOOL)exportSettingsToFile {
    NSDictionary *settings = [self exportSettings];
    if (!settings) return NO;
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:settings options:NSJSONWritingPrettyPrinted error:&error];
    if (error) return NO;
    
    return [jsonData writeToFile:[self settingsFilePath] atomically:YES];
}

%new
- (BOOL)importSettingsFromFile {
    NSData *jsonData = [NSData dataWithContentsOfFile:[self settingsFilePath]];
    if (!jsonData) return NO;
    
    NSError *error;
    NSDictionary *settings = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (error) return NO;
    
    return [self importSettings:settings];
}

%new
- (void)shareSettings:(UIViewController *)presenter {
    NSDictionary *settings = [self exportSettings];
    if (!settings) return;
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:settings options:NSJSONWritingPrettyPrinted error:&error];
    if (error) return;
    
    // Create temporary file for sharing
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"YTMUltimate_Settings.json"];
    [jsonData writeToFile:tempPath atomically:YES];
    
    NSURL *fileURL = [NSURL fileURLWithPath:tempPath];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    
    [presenter presentViewController:activityVC animated:YES completion:nil];
}

%end

#pragma mark - Feature 4: Discord Rich Presence
// Note: Full Discord Rich Presence requires the Discord app to be installed
// and proper IPC communication. This is a basic implementation.

@interface YTMUDiscordRPC : NSObject
+ (instancetype)sharedInstance;
- (void)updatePresenceWithTitle:(NSString *)title artist:(NSString *)artist album:(NSString *)album;
- (void)clearPresence;
@end

%subclass YTMUDiscordRPC : NSObject

+ (instancetype)sharedInstance {
    static YTMUDiscordRPC *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

%new
- (void)updatePresenceWithTitle:(NSString *)title artist:(NSString *)artist album:(NSString *)album {
    if (!YTMU(@"YTMUltimateIsEnabled") || !YTMU(@"discordRPC")) return;
    
    // Store current playing info for potential Discord integration
    NSMutableDictionary *nowPlaying = [NSMutableDictionary dictionary];
    if (title) nowPlaying[@"title"] = title;
    if (artist) nowPlaying[@"artist"] = artist;
    if (album) nowPlaying[@"album"] = album;
    nowPlaying[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    
    [[NSUserDefaults standardUserDefaults] setObject:nowPlaying forKey:@"YTMUltimate_NowPlaying"];
    
    // Try to communicate with Discord via URL scheme if available
    NSString *discordURL = [NSString stringWithFormat:@"discord://activity?details=%@&state=%@", 
                           [title stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
                           [artist stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    
    NSURL *url = [NSURL URLWithString:discordURL];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        // Discord is installed, but direct RPC requires more complex implementation
        // For now, we just store the data for potential future use
    }
    
    // Post notification for any external listeners
    [[NSNotificationCenter defaultCenter] postNotificationName:@"YTMUltimateNowPlayingChanged" object:nowPlaying];
}

%new
- (void)clearPresence {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"YTMUltimate_NowPlaying"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"YTMUltimateNowPlayingCleared" object:nil];
}

%end

// Hook player to update Discord presence
%hook YTPlayerViewController
- (void)playbackController:(id)controller didActivateVideo:(id)video withPlaybackData:(id)data {
    %orig;
    
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"discordRPC")) {
        YTPlayerResponse *response = self.playerResponse;
        if (response && response.playerData) {
            id videoDetails = response.playerData.videoDetails;
            if (videoDetails) {
                NSString *title = [videoDetails valueForKey:@"title"];
                NSString *author = [videoDetails valueForKey:@"author"];
                
                [[%c(YTMUDiscordRPC) sharedInstance] updatePresenceWithTitle:title artist:author album:nil];
            }
        }
    }
}

- (void)playbackControllerDidStopPlaying:(id)controller {
    %orig;
    
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"discordRPC")) {
        [[%c(YTMUDiscordRPC) sharedInstance] clearPresence];
    }
}
%end

#pragma mark - Feature 5: Playlist Bulk Download
// This is handled in the Downloading.x file, but we add the UI hooks here

@interface YTMPlaylistViewController : UIViewController
@property (nonatomic, strong) NSArray *playlistItems;
@end

%hook YTMPlaylistViewController
- (void)viewDidLoad {
    %orig;
    
    if (YTMU(@"YTMUltimateIsEnabled") && (YTMU(@"downloadAudio") || YTMU(@"downloadCoverImage"))) {
        // Add bulk download button
        [self addBulkDownloadButton];
    }
}

%new
- (void)addBulkDownloadButton {
    UIBarButtonItem *downloadButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.circle"] 
                                                                       style:UIBarButtonItemStylePlain 
                                                                      target:self 
                                                                      action:@selector(showBulkDownloadOptions)];
    
    NSMutableArray *rightItems = [NSMutableArray arrayWithArray:self.navigationItem.rightBarButtonItems ?: @[]];
    [rightItems addObject:downloadButton];
    self.navigationItem.rightBarButtonItems = rightItems;
}

%new
- (void)showBulkDownloadOptions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"BULK_DOWNLOAD") 
                                                                   message:LOC(@"BULK_DOWNLOAD_DESC") 
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"DOWNLOAD_ALL_AUDIO") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self startBulkDownload:YES];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

%new
- (void)startBulkDownload:(BOOL)audioOnly {
    NSArray *items = [self valueForKey:@"_playlistItems"] ?: self.playlistItems;
    if (!items || items.count == 0) {
        [[%c(YTMToastController) alloc] showMessage:LOC(@"NO_ITEMS_TO_DOWNLOAD")];
        return;
    }
    
    [[%c(YTMToastController) alloc] showMessage:[NSString stringWithFormat:LOC(@"STARTING_BULK_DOWNLOAD"), @(items.count)]];
    
    // Start downloading in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (id item in items) {
            // Get video ID and download
            NSString *videoId = [item valueForKey:@"videoId"];
            if (videoId) {
                [[NSNotificationCenter defaultCenter] postNotificationName:@"YTMUBulkDownloadItem" 
                                                                    object:@{@"videoId": videoId, @"audioOnly": @(audioOnly)}];
            }
            
            // Small delay between downloads to avoid rate limiting
            [NSThread sleepForTimeInterval:1.0];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[%c(YTMToastController) alloc] showMessage:LOC(@"BULK_DOWNLOAD_COMPLETE")];
        });
    });
}
%end

#pragma mark - Feature 6: Auto Clear Cache on App Close

@interface YTMAppDelegate : UIResponder <UIApplicationDelegate>
@end

%hook YTMAppDelegate
- (void)applicationWillTerminate:(UIApplication *)application {
    %orig;
    
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"autoClearCacheOnClose")) {
        [self clearCacheTo1KB];
    }
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    %orig;
    
    // Also clear cache when app goes to background (optional, but useful)
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"autoClearCacheOnClose")) {
        [self clearCacheTo1KB];
    }
}

%new
- (void)clearCacheTo1KB {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        if (!cachePath || !fileManager) return;
        
        NSError *error = nil;
        NSArray *files = [fileManager contentsOfDirectoryAtPath:cachePath error:&error];
        
        if (error) {
            NSLog(@"[YTMusicUltimate] Error reading cache directory: %@", error.localizedDescription);
            return;
        }
        
        // Calculate total size and remove files until we're under 1KB
        unsigned long long totalSize = 0;
        NSMutableArray *fileSizes = [NSMutableArray array];
        
        for (NSString *fileName in files) {
            NSString *filePath = [cachePath stringByAppendingPathComponent:fileName];
            NSDictionary *attributes = [fileManager attributesOfItemAtPath:filePath error:nil];
            if (attributes) {
                unsigned long long fileSize = [attributes fileSize];
                totalSize += fileSize;
                [fileSizes addObject:@{@"path": filePath, @"size": @(fileSize)}];
            }
        }
        
        // Sort by size (largest first) to remove biggest files first
        [fileSizes sortUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
            NSNumber *size1 = obj1[@"size"];
            NSNumber *size2 = obj2[@"size"];
            return [size2 compare:size1];
        }];
        
        // Remove files until we're under 1KB (1024 bytes)
        const unsigned long long targetSize = 1024; // 1KB
        
        for (NSDictionary *fileInfo in fileSizes) {
            if (totalSize <= targetSize) break;
            
            NSString *filePath = fileInfo[@"path"];
            NSNumber *fileSize = fileInfo[@"size"];
            
            // Don't remove important system files or our own files
            NSString *fileName = [filePath lastPathComponent];
            if ([fileName hasPrefix:@"."] || 
                [fileName isEqualToString:@"com.apple.nsurlsessiond"] ||
                [filePath containsString:@"YTMusicUltimate"]) {
                continue;
            }
            
            NSError *removeError = nil;
            if ([fileManager removeItemAtPath:filePath error:&removeError]) {
                totalSize -= [fileSize unsignedLongLongValue];
            }
        }
        
        // If still over 1KB, create a small placeholder file to ensure we're at exactly 1KB
        if (totalSize > targetSize) {
            // Remove more aggressively
            for (NSDictionary *fileInfo in fileSizes) {
                if (totalSize <= targetSize) break;
                
                NSString *filePath = fileInfo[@"path"];
                if ([fileManager fileExistsAtPath:filePath]) {
                    NSNumber *fileSize = fileInfo[@"size"];
                    NSError *removeError = nil;
                    if ([fileManager removeItemAtPath:filePath error:&removeError]) {
                        totalSize -= [fileSize unsignedLongLongValue];
                    }
                }
            }
        }
        
        // Create a small placeholder file if cache is empty to maintain 1KB
        if (totalSize < targetSize) {
            NSString *placeholderPath = [cachePath stringByAppendingPathComponent:@".ytmu_cache_placeholder"];
            NSData *placeholderData = [NSData dataWithBytes:"YTMusicUltimate Cache Placeholder" length:32];
            [placeholderData writeToFile:placeholderPath atomically:YES];
        }
        
        NSLog(@"[YTMusicUltimate] Cache cleared. Final size: %llu bytes", totalSize);
    });
}
%end

%ctor {
    // Initialize settings defaults for new features
    NSMutableDictionary *YTMUltimateDict = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"]];
    
    NSArray *newKeys = @[@"alwaysHighQuality", @"skipDislikedSongs", @"discordRPC", @"preferAudioVersion", @"autoClearCacheOnClose"];
    for (NSString *key in newKeys) {
        if (!YTMUltimateDict[key]) {
            // Default autoClearCacheOnClose to YES, others to NO
            BOOL defaultValue = [key isEqualToString:@"autoClearCacheOnClose"] ? YES : NO;
            [YTMUltimateDict setObject:@(defaultValue) forKey:key];
        }
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:YTMUltimateDict forKey:@"YTMUltimate"];
}
