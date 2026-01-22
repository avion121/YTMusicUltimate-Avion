#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Headers/YTPlayerViewController.h"
#import "Headers/YTMToastController.h"
#import "Headers/Localization.h"

static BOOL YTMU(NSString *key) {
    NSDictionary *dict =
        [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [dict[key] boolValue];
}

#pragma mark - Always High Audio Quality

%hook YTMMediaQualityController
- (NSInteger)audioQuality {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"alwaysHighQuality")) {
        return 2;
    }
    return %orig;
}

- (void)setAudioQuality:(NSInteger)quality {
    %orig(YTMU(@"alwaysHighQuality") ? 2 : quality);
}
%end

#pragma mark - Skip Disliked Songs

%hook YTMQueueController

%new
- (void)checkAndSkipDislikedSong {
    SEL valueForKeySel = @selector(valueForKey:);
    id currentItem =
        ((id (*)(id, SEL, id))objc_msgSend)(self, valueForKeySel, @"_currentItem");

    if (!currentItem) return;

    SEL likeStatusSel = NSSelectorFromString(@"likeStatus");
    if (!class_getInstanceMethod(object_getClass(currentItem), likeStatusSel)) return;

    NSInteger status =
        ((NSInteger (*)(id, SEL))objc_msgSend)(currentItem, likeStatusSel);

    if (status == 2) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[%c(YTMToastController) alloc]
                showMessage:LOC(@"SKIPPED_DISLIKED")];
        });

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            SEL nextSel = @selector(advanceToNextItem);
            if (class_getInstanceMethod(object_getClass(self), nextSel)) {
                ((void (*)(id, SEL))objc_msgSend)(self, nextSel);
            }
        });
    }
}

- (void)advanceToNextItem {
    %orig;

    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"skipDislikedSongs")) {
        SEL checkSel = @selector(checkAndSkipDislikedSong);
        if (class_getInstanceMethod(object_getClass(self), checkSel)) {
            ((void (*)(id, SEL))objc_msgSend)(self, checkSel);
        }
    }
}
%end

#pragma mark - Discord Presence (storage only)

@interface YTMUDiscordRPC : NSObject
+ (instancetype)sharedInstance;
- (void)updatePresenceWithTitle:(NSString *)title artist:(NSString *)artist;
- (void)clearPresence;
@end

%subclass YTMUDiscordRPC : NSObject

+ (instancetype)sharedInstance {
    static YTMUDiscordRPC *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

%new
- (void)updatePresenceWithTitle:(NSString *)title artist:(NSString *)artist {
    if (!YTMU(@"YTMUltimateIsEnabled") || !YTMU(@"discordRPC")) return;

    // Ensure we have non-nil strings before creating dictionary
    NSString *safeTitle = title ?: @"";
    NSString *safeArtist = artist ?: @"";
    
    NSDictionary *nowPlaying = @{
        @"title": safeTitle,
        @"artist": safeArtist
    };

    [[NSUserDefaults standardUserDefaults]
        setObject:nowPlaying
           forKey:@"YTMUltimate_NowPlaying"];
}

%new
- (void)clearPresence {
    [[NSUserDefaults standardUserDefaults]
        removeObjectForKey:@"YTMUltimate_NowPlaying"];
}
%end

%hook YTPlayerViewController
- (void)playbackController:(id)controller didActivateVideo:(id)video withPlaybackData:(id)data {
    %orig;
    
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"discordRPC")) {
        @try {
            YTPlayerResponse *response = self.playerResponse;
            if (response && response.playerData) {
                id videoDetails = response.playerData.videoDetails;
                if (videoDetails && [videoDetails respondsToSelector:@selector(valueForKey:)]) {
                    id titleObj = [videoDetails valueForKey:@"title"];
                    id authorObj = [videoDetails valueForKey:@"author"];
                    
                    NSString *title = ([titleObj isKindOfClass:[NSString class]]) ? titleObj : nil;
                    NSString *author = ([authorObj isKindOfClass:[NSString class]]) ? authorObj : nil;
                    
                    // Update Discord RPC with safe values
                    [[%c(YTMUDiscordRPC) sharedInstance] updatePresenceWithTitle:title artist:author];
                }
            }
        } @catch (NSException *exception) {
            // Silently handle any exceptions when accessing video details
            NSLog(@"[YTMusicUltimate] Error updating Discord RPC: %@", exception);
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

#pragma mark - Auto Clear Cache

%hook YTMAppDelegate

%new
- (void)ytmu_clearCache {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSString *path =
            NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                NSUserDomainMask,
                                                YES).firstObject;
        if (path) {
            [[NSFileManager defaultManager]
                removeItemAtPath:path
                           error:nil];
        }
    });
}

- (void)applicationWillTerminate:(UIApplication *)application {
    %orig;

    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"autoClearCacheOnClose")) {
        SEL sel = @selector(ytmu_clearCache);
        if (class_getInstanceMethod(object_getClass(self), sel)) {
            ((void (*)(id, SEL))objc_msgSend)(self, sel);
        }
    }
}
%end

%ctor {
    @try {
        NSMutableDictionary *dict =
            [NSMutableDictionary dictionaryWithDictionary:
                [[NSUserDefaults standardUserDefaults]
                    dictionaryForKey:@"YTMUltimate"] ?: @{}];

        NSDictionary *defaults = @{
            @"alwaysHighQuality": @NO,
            @"skipDislikedSongs": @NO,
            @"discordRPC": @NO,
            @"autoClearCacheOnClose": @YES
        };

        for (NSString *key in defaults) {
            // Safety check: ensure key is not nil before using it
            if (key && [key isKindOfClass:[NSString class]] && !dict[key]) {
                dict[key] = defaults[key];
            }
        }

        [[NSUserDefaults standardUserDefaults]
            setObject:dict
               forKey:@"YTMUltimate"];
    } @catch (NSException *exception) {
        NSLog(@"[YTMusicUltimate] Error in constructor: %@", exception);
    }
}
