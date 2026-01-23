#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "Headers/Localization.h"
#import "Headers/YTMToastController.h"
#import "Headers/YTPlayerViewController.h"

#define ytmuBool(key) [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"][key] boolValue]
#define ytmuInt(key) [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"][key] integerValue]

%hook YTPlayerViewController
%property (nonatomic, strong) NSMutableDictionary *sponsorBlockValues;

- (void)playbackController:(id)arg1 didActivateVideo:(id)arg2 withPlaybackData:(id)arg3 {
    %orig;

    if (!ytmuBool(@"sponsorBlock")) return;

    self.sponsorBlockValues = [NSMutableDictionary dictionary];

    // Check if currentVideoID is valid before proceeding
    NSString *videoID = self.currentVideoID;
    if (!videoID || videoID.length == 0) return;

    // Build categories array based on settings
    NSMutableArray *categories = [NSMutableArray arrayWithObject:@"music_offtopic"];
    
    // Add podcast categories if enabled
    if (ytmuBool(@"sponsorBlockPodcasts")) {
        [categories addObjectsFromArray:@[@"sponsor", @"selfpromo", @"interaction", @"intro", @"outro", @"preview", @"filler"]];
    }
    
    // Convert array format for API: ["cat1","cat2"] format
    NSMutableArray *quotedCategories = [NSMutableArray array];
    for (NSString *category in categories) {
        [quotedCategories addObject:[NSString stringWithFormat:@"\"%@\"", category]];
    }
    NSString *categoriesJSON = [NSString stringWithFormat:@"[%@]", [quotedCategories componentsJoinedByString:@","]];
    categoriesJSON = [categoriesJSON stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://sponsor.ajay.app/api/skipSegments?videoID=%@&categories=%@", videoID, categoriesJSON]]];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([NSJSONSerialization isValidJSONObject:jsonResponse] && videoID) {
                NSMutableDictionary *segments = [NSMutableDictionary dictionary];
                for (NSDictionary *segmentDict in jsonResponse) {
                    NSString *uuid = segmentDict[@"UUID"];
                    // Check UUID is not nil before using as dictionary key
                    if (uuid && [uuid isKindOfClass:[NSString class]]) {
                        [segments setObject:@(1) forKey:uuid];
                    }
                }

                // Only set if videoID is not nil
                if (videoID) {
                    [self.sponsorBlockValues setObject:jsonResponse forKey:videoID];
                    [self.sponsorBlockValues setObject:segments forKey:@"segments"];
                }
            }
        }
    }] resume];
}

- (void)singleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;

    [self skipSegment];
}

- (void)potentiallyMutatedSingleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;

    [self skipSegment];
}

%new
- (void)skipSegment {
    if (ytmuBool(@"sponsorBlock") && [NSJSONSerialization isValidJSONObject:self.sponsorBlockValues]) {
        NSString *videoID = self.currentVideoID;
        if (!videoID) return;
        
        NSDictionary *sponsorBlockValues = [self.sponsorBlockValues objectForKey:videoID];
        NSMutableDictionary *segmentSkipValues = [self.sponsorBlockValues objectForKey:@"segments"];
        
        if (!sponsorBlockValues || !segmentSkipValues) return;

        for (NSDictionary *jsonDictionary in sponsorBlockValues) {
            NSString *uuid = [jsonDictionary objectForKey:@"UUID"];
            if (!uuid) continue;
            
            NSNumber *segmentSkipValue = [segmentSkipValues objectForKey:uuid];

            NSString *category = [jsonDictionary objectForKey:@"category"];
            BOOL isMusicOfftopic = [category isEqual:@"music_offtopic"];
            BOOL isPodcastCategory = ytmuBool(@"sponsorBlockPodcasts") && 
                ([category isEqual:@"sponsor"] || [category isEqual:@"selfpromo"] || 
                 [category isEqual:@"interaction"] || [category isEqual:@"intro"] || 
                 [category isEqual:@"outro"] || [category isEqual:@"preview"] || 
                 [category isEqual:@"filler"]);
            
            if (segmentSkipValue && [segmentSkipValue isEqual:@(1)]
                && (isMusicOfftopic || isPodcastCategory)
                && self.currentVideoMediaTime >= [[jsonDictionary objectForKey:@"segment"][0] floatValue]
                && self.currentVideoMediaTime <= ([[jsonDictionary objectForKey:@"segment"][1] floatValue] - 1)) {

                [segmentSkipValues setObject:@(0) forKey:uuid];
                [self.sponsorBlockValues setObject:segmentSkipValues forKey:@"segments"];

                GOOHUDMessageAction *unskipAction = [[%c(GOOHUDMessageAction) alloc] init];
                unskipAction.title = LOC(@"UNSKIP");
                [unskipAction setHandler:^ {
                    [self seekToTime:[[jsonDictionary objectForKey:@"segment"][0] floatValue]];
                }];
                
                GOOHUDMessageAction *skipAction = [[%c(GOOHUDMessageAction) alloc] init];
                skipAction.title = LOC(@"SKIP");
                [skipAction setHandler:^ {
                    [self seekToTime:[[jsonDictionary objectForKey:@"segment"][1] floatValue]];

                    [[%c(YTMToastController) alloc] showMessage:LOC(@"SEGMENT_SKIPPED") HUDMessageAction:unskipAction infoType:0 duration:ytmuInt(@"sbDuration")];
                }];

                if (ytmuInt(@"sbSkipMode") == 0) {
                    [self seekToTime:[[jsonDictionary objectForKey:@"segment"][1] floatValue]];

                    [[%c(YTMToastController) alloc] showMessage:LOC(@"SEGMENT_SKIPPED") HUDMessageAction:unskipAction infoType:0 duration:ytmuInt(@"sbDuration")];
                }

                else {
                    [[%c(YTMToastController) alloc] showMessage:LOC(@"FOUND_SEGMENT") HUDMessageAction:skipAction infoType:0 duration:ytmuInt(@"sbDuration")];
                }
            }
        }
    }
}
%end

%ctor {
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"]];

    if (mutableDict[@"sbSkipMode"] == nil) {
        [mutableDict setObject:@(0) forKey:@"sbSkipMode"];
    }

    if (mutableDict[@"sbDuration"] == nil) {
        [mutableDict setObject:@(10) forKey:@"sbDuration"];
    }

    [[NSUserDefaults standardUserDefaults] setObject:mutableDict forKey:@"YTMUltimate"];
}