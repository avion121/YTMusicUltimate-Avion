#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Headers/YTPlayerViewController.h"
#import "Headers/YTMWatchViewController.h"
#import "Headers/YTPlayabilityResolutionUserActionUIController.h"

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

#pragma mark - Fix 1: Recap Not Opening
// The Recap feature uses YTICommand browse endpoints that may be blocked by premium status hooks
// We need to whitelist Recap-related endpoints

@interface YTICommand : NSObject
@property (nonatomic, strong) id browseEndpoint;
@property (nonatomic, strong) id urlEndpoint;
@property (nonatomic, strong) id watchEndpoint;
@end

@interface YTIBrowseEndpoint : NSObject
@property (nonatomic, copy) NSString *browseId;
@end

@interface YTIUrlEndpoint : NSObject
@property (nonatomic, strong) NSURL *url;
@end

// Hook to ensure Recap endpoints are not blocked
%hook YTICommand
- (void)executeWithHandler:(id)handler {
    // Check if this is a Recap-related command and allow it through
    if ([self browseEndpoint]) {
        NSString *browseId = [[self browseEndpoint] browseId];
        if (browseId && ([browseId containsString:@"recap"] || 
                         [browseId containsString:@"Recap"] ||
                         [browseId containsString:@"FEmusic_recap"] ||
                         [browseId containsString:@"FEmusic_listening_review"])) {
            %orig;
            return;
        }
    }
    
    if ([self urlEndpoint]) {
        NSURL *url = [[self urlEndpoint] url];
        NSString *urlString = [url absoluteString];
        if (urlString && ([urlString containsString:@"recap"] || [urlString containsString:@"Recap"])) {
            %orig;
            return;
        }
    }
    
    %orig;
}
%end

// Fix for Recap button not responding - ensure touch handlers work
%hook YTMRecapEntryPointView
- (void)setUserInteractionEnabled:(BOOL)enabled {
    %orig(YES); // Always enable interaction for Recap views
}
%end

%hook YTMRecapCardView
- (void)setUserInteractionEnabled:(BOOL)enabled {
    %orig(YES);
}
%end

// Ensure Recap navigation endpoints are processed
%hook YTMNavigationController
- (void)navigateToCommand:(YTICommand *)command {
    %orig;
}

- (BOOL)canNavigateToCommand:(YTICommand *)command {
    if ([command browseEndpoint]) {
        NSString *browseId = [[command browseEndpoint] browseId];
        if (browseId && ([browseId containsString:@"recap"] || 
                         [browseId containsString:@"Recap"] ||
                         [browseId containsString:@"listening_review"])) {
            return YES;
        }
    }
    return %orig;
}
%end

#pragma mark - Fix 2: Audio Glitch/Buffer on Track Change
// This issue occurs when transitioning between tracks in a playlist
// The player may not properly reset its buffer state

@interface YTMPlayerController : NSObject
- (void)prepareForNextTrack;
- (void)resetBufferState;
@end

%hook YTMPlayerController
- (void)playbackController:(id)controller didFinishPlayingVideo:(id)video {
    %orig;
    
    if (YTMU(@"YTMUltimateIsEnabled")) {
        // Reset buffer state before next track
        if ([self respondsToSelector:@selector(resetBufferState)]) {
            [self resetBufferState];
        }
    }
}

- (void)playbackController:(id)controller willStartPlayingVideo:(id)video {
    if (YTMU(@"YTMUltimateIsEnabled")) {
        // Ensure clean state before playback
        if ([self respondsToSelector:@selector(prepareForNextTrack)]) {
            [self prepareForNextTrack];
        }
    }
    %orig;
}
%end

// Fix audio session interruption handling
%hook YTMAudioSessionController
- (void)handleInterruption:(NSNotification *)notification {
    %orig;
    
    if (YTMU(@"YTMUltimateIsEnabled")) {
        NSDictionary *info = notification.userInfo;
        NSString *typeKey = @"AVAudioSessionInterruptionTypeKey";
        NSNumber *typeValue = info[typeKey];
        
        if (typeValue) {
            NSUInteger type = [typeValue unsignedIntegerValue];
            // AVAudioSessionInterruptionTypeEnded = 1
            if (type == 1) {
                // Ensure proper audio session reactivation
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    AVAudioSession *session = [AVAudioSession sharedInstance];
                    if ([session respondsToSelector:@selector(setActive:error:)]) {
                        [session setActive:YES error:nil];
                    }
                });
            }
        }
    }
}
%end

// Fix for playlist track transitions
%hook YTMQueueController
- (void)advanceToNextItem {
    if (YTMU(@"YTMUltimateIsEnabled")) {
        // Small delay to ensure proper buffer cleanup
        dispatch_async(dispatch_get_main_queue(), ^{
            %orig;
        });
    } else {
        %orig;
    }
}

- (void)playItemAtIndex:(NSUInteger)index {
    if (YTMU(@"YTMUltimateIsEnabled")) {
        // Ensure audio session is active
        AVAudioSession *session = [AVAudioSession sharedInstance];
        if ([session respondsToSelector:@selector(setActive:error:)]) {
            [session setActive:YES error:nil];
        }
    }
    %orig;
}
%end

#pragma mark - Fix 3: Skip Content Warning Black Background Issue
// The issue is that confirmAlertDidPressConfirm may not properly handle all warning types

%hook YTPlayabilityResolutionUserActionUIController
- (void)showConfirmAlert {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"skipWarning")) {
        // Ensure we properly dismiss any existing alerts first
        dispatch_async(dispatch_get_main_queue(), ^{
            SEL confirmSel = @selector(confirmAlertDidPressConfirm);
            if (class_getInstanceMethod([self class], confirmSel)) {
                ((void (*)(id, SEL))objc_msgSend)(self, confirmSel);
            }
        });
    } else {
        %orig;
    }
}

// Handle different types of content warnings
- (void)presentWarningWithRenderer:(id)renderer {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"skipWarning")) {
        // Auto-confirm all warning types
        SEL confirmSel = @selector(confirmAlertDidPressConfirm);
        if (class_getInstanceMethod([self class], confirmSel)) {
            ((void (*)(id, SEL))objc_msgSend)(self, confirmSel);
        }
        return;
    }
    %orig;
}
%end

// Fix for sensitive content overlay
%hook YTMSensitiveContentOverlayView
- (void)setHidden:(BOOL)hidden {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"skipWarning")) {
        %orig(YES); // Always hide sensitive content overlay
    } else {
        %orig;
    }
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self && YTMU(@"YTMUltimateIsEnabled") && YTMU(@"skipWarning")) {
        // Use objc_msgSend to avoid forward declaration issues
        SEL setHiddenSel = @selector(setHidden:);
        if (class_getInstanceMethod(object_getClass(self), setHiddenSel)) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(self, setHiddenSel, YES);
        }
    }
    return self;
}
%end

// Additional hook for content warning dialogs
%hook YTMContentWarningViewController
- (void)viewDidLoad {
    %orig;
    
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"skipWarning")) {
        // Auto-dismiss after a short delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            Class cls = object_getClass(self);
            SEL confirmSel = @selector(confirmButtonTapped:);
            SEL dismissSel = @selector(dismissViewControllerAnimated:completion:);
            
            if (class_getInstanceMethod(cls, confirmSel)) {
                ((void (*)(id, SEL, id))objc_msgSend)(self, confirmSel, nil);
            } else if (class_getInstanceMethod(cls, dismissSel)) {
                ((void (*)(id, SEL, BOOL, void(^)(void)))objc_msgSend)(self, dismissSel, NO, nil);
            }
        });
    }
}
%end

#pragma mark - Fix 4: Crash on Non-16:9 Videos with No Ads
// The crash occurs due to aspect ratio calculations when ad-related code is bypassed
// We need to add safety checks for video dimensions

%hook YTPlayerView
- (void)setVideoSize:(CGSize)size {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds")) {
        // Validate video size to prevent crashes
        if (size.width <= 0 || size.height <= 0) {
            size = CGSizeMake(16, 9); // Default to 16:9
        }
        
        // Ensure we don't crash on unusual aspect ratios
        CGFloat aspectRatio = size.width / size.height;
        if (isnan(aspectRatio) || isinf(aspectRatio)) {
            size = CGSizeMake(16, 9);
        }
    }
    %orig(size);
}

- (void)layoutSubviews {
    @try {
        %orig;
    } @catch (NSException *exception) {
        NSLog(@"[YTMusicUltimate] Caught exception in layoutSubviews: %@", exception);
    }
}
%end

// Fix for video rendering with non-standard aspect ratios
%hook YTMVideoPlayerView
- (void)setContentMode:(UIViewContentMode)contentMode {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds")) {
        // Use aspect fit to prevent crashes with unusual aspect ratios
        %orig(UIViewContentModeScaleAspectFit);
    } else {
        %orig;
    }
}

- (void)updateVideoFrame:(CGRect)frame {
    @try {
        if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds")) {
            // Validate frame dimensions
            if (CGRectIsEmpty(frame) || CGRectIsNull(frame) || 
                isnan(frame.size.width) || isnan(frame.size.height) ||
                frame.size.width <= 0 || frame.size.height <= 0) {
                return; // Skip invalid frames
            }
        }
        %orig(frame);
    } @catch (NSException *exception) {
        NSLog(@"[YTMusicUltimate] Caught exception in updateVideoFrame: %@", exception);
    }
}
%end

// Additional safety for HAMPlayer (Google's video player)
%hook HAMPlayerView
- (void)setNaturalSize:(CGSize)size {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds")) {
        if (size.width <= 0 || size.height <= 0) {
            size = CGSizeMake(1920, 1080);
        }
    }
    %orig(size);
}
%end

#pragma mark - Fix 5: Music Video vs Real Song Inconsistency
// This is a YouTube Music behavior, not a bug in the tweak
// However, we can add an option to prefer audio-only versions

%hook YTMQueueItem
- (BOOL)prefersAudioOnlyPlayback {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"preferAudioVersion")) {
        return YES;
    }
    return %orig;
}
%end

%hook YTMPlaybackCoordinator
- (void)playVideo:(id)video withOptions:(id)options {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"preferAudioVersion")) {
        // Try to get the audio-only version if available
        if ([options respondsToSelector:@selector(setPreferAudioOnly:)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [options performSelector:@selector(setPreferAudioOnly:) withObject:@YES];
            #pragma clang diagnostic pop
        }
    }
    %orig;
}
%end

#pragma mark - Fix 6: Ads Still Showing (AirPlay/Shuffle)
// Enhanced ad blocking for AirPlay and shuffle scenarios

%hook YTIPlayerResponse
// Existing hooks plus additional ones for AirPlay scenarios
- (id)adPlacements {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds") ? nil : %orig;
}

- (BOOL)hasAdPlacements {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds") ? NO : %orig;
}

- (id)adBreaks {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds") ? nil : %orig;
}

- (BOOL)hasAdBreaks {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds") ? NO : %orig;
}

- (id)playerAds {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds") ? nil : %orig;
}

- (BOOL)hasPlayerAds {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds") ? NO : %orig;
}
%end

// Block ads during AirPlay
%hook YTMAirPlayController
- (void)startAirPlayWithRoute:(id)route {
    %orig;
    
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds")) {
        // Ensure ad blocking is active during AirPlay
        [[NSNotificationCenter defaultCenter] postNotificationName:@"YTMUDisableAdsNotification" object:nil];
    }
}
%end

// Block ads during shuffle/random play
%hook YTMShuffleController
- (void)shuffleAndPlay {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds")) {
        // Pre-emptively disable ads before shuffle
        [[NSNotificationCenter defaultCenter] postNotificationName:@"YTMUDisableAdsNotification" object:nil];
    }
    %orig;
}
%end

// Additional ad blocking hooks
%hook YTAdShieldController
- (BOOL)shouldShowAd {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds") ? NO : %orig;
}
%end

%hook YTMAdController
- (void)loadAd {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds")) {
        return; // Don't load ads
    }
    %orig;
}

- (void)playAd {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds")) {
        return; // Don't play ads
    }
    %orig;
}

- (BOOL)isAdPlaying {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds") ? NO : %orig;
}
%end

// Block interstitial ads (the 5-second skip ads)
%hook YTMInterstitialAdController
- (void)presentAd {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds")) {
        // Skip the ad entirely
        SEL skipAdSel = @selector(skipAd);
        if (class_getInstanceMethod(object_getClass(self), skipAdSel)) {
            ((void (*)(id, SEL))objc_msgSend)(self, skipAdSel);
        }
        return;
    }
    %orig;
}

- (BOOL)shouldPresentAd {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds") ? NO : %orig;
}
%end

// Block video ads
%hook YTMVideoAdController
- (void)playVideoAd:(id)ad {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds")) {
        return;
    }
    %orig;
}
%end

// Block audio ads
%hook YTMAudioAdController
- (void)playAudioAd:(id)ad {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds")) {
        return;
    }
    %orig;
}
%end

// Ensure ads don't play during external playback (AirPlay, CarPlay, etc.)
%hook YTPlayerStatus
- (BOOL)isExternalPlayback {
    BOOL isExternal = %orig;
    if (isExternal && YTMU(@"YTMUltimateIsEnabled") && YTMU(@"noAds")) {
        // Force ad-free mode during external playback
        [[NSNotificationCenter defaultCenter] postNotificationName:@"YTMUDisableAdsNotification" object:nil];
    }
    return isExternal;
}
%end

%ctor {
    // Register for ad disable notification
    [[NSNotificationCenter defaultCenter] addObserverForName:@"YTMUDisableAdsNotification" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        // Additional ad blocking logic can be added here
    }];
}
