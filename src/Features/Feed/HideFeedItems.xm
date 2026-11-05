#import "../../Utils.h"
#import "../../InstagramHeaders.h"

static NSArray *removeItemsInList(NSArray *list, BOOL isFeed) {
    NSArray *originalObjs = list;
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {
        // Remove suggested posts
        if (isFeed && [SCIUtils getBoolPref:@"no_suggested_post"]) {

            // Posts
            if (
                ([obj isKindOfClass:%c(IGMedia)] && [((IGMedia *)obj).explorePostInFeed isEqual:@YES])
                || ([obj isKindOfClass:%c(IGFeedGroupHeaderViewModel)] && [[obj title] isEqualToString:@"Suggested Posts"])
            ) {
                NSLog(@"[SCInsta] Removing suggested posts");

                continue;
            }

            // Suggested stories (carousel)
            if ([obj isKindOfClass:%c(IGInFeedStoriesTrayModel)]) {
                NSLog(@"[SCInsta] Hiding suggested stories carousel");

                continue;
            }

        }

        // Remove suggested reels (carousel)
        if (isFeed && [SCIUtils getBoolPref:@"no_suggested_reels"]) {
            if ([obj isKindOfClass:%c(IGFeedScrollableClipsModel)]) {
                NSLog(@"[SCInsta] Hiding suggested reels carousel");

                continue;
            }
        }
        
        // Remove suggested for you (accounts)
        if ([SCIUtils getBoolPref:@"no_suggested_account"]) {
            
            // Feed
            if (isFeed && [obj isKindOfClass:%c(IGHScrollAYMFModel)]) {
                NSLog(@"[SCInsta] Hiding accounts suggested for you (feed)");

                continue;
            }

            // Reels
            if ([obj isKindOfClass:%c(IGSuggestedUserInReelsModel)]) {
                NSLog(@"[SCInsta] Hiding accounts suggested for you (reels)");

                continue;
            }
        }

        // Remove suggested threads posts
        if ([SCIUtils getBoolPref:@"no_suggested_threads"]) {

            // Feed (carousel)
            if (isFeed) {
                if ([obj isKindOfClass:%c(IGBloksFeedUnitModel)] || [obj isKindOfClass:objc_getClass("IGThreadsInFeedModels.IGThreadsInFeedModel")]) {
                    NSLog(@"[SCInsta] Hiding suggested threads posts (carousel)");

                    continue;
                }
            }

            // Reels
            if ([obj isKindOfClass:%c(IGSundialNetegoItem)]) {
                NSLog(@"[SCInsta] Hiding suggested threads posts (reels)");

                continue;
            }

        }        

        // Remove story tray
        if (isFeed && [SCIUtils getBoolPref:@"hide_stories_tray"]) {
            if ([obj isKindOfClass:%c(IGStoryDataController)]) {
                NSLog(@"[SCInsta] Hiding stories tray");

                continue;
            }
        }

        // Hide entire feed
        if (isFeed && [SCIUtils getBoolPref:@"hide_entire_feed"]) {
            if ([obj isKindOfClass:%c(IGPostCreationManager)] || [obj isKindOfClass:%c(IGMedia)] || [obj isKindOfClass:%c(IGEndOfFeedDemarcatorModel)] || [obj isKindOfClass:%c(IGSpinnerLabelViewModel)]) {
                NSLog(@"[SCInsta] Hiding entire feed");

                continue;
            }
        }

        // Remove ads
        if ([SCIUtils getBoolPref:@"hide_ads"]) {
            if (
                ([obj isKindOfClass:%c(IGFeedItem)] && ([obj isSponsored] || [obj isSponsoredApp]))
                || ([obj isKindOfClass:%c(IGDiscoveryGridItem)] && [[obj model] isKindOfClass:%c(IGAdItem)])
                || [obj isKindOfClass:%c(IGAdItem)]
            ) {
                NSLog(@"[SCInsta] Removing ads");

                continue;
            }
        }

        [filteredObjs addObject:obj];
    }

    return [filteredObjs copy];
}

// ---- Feed quota settings (edit here) ----
// TEST VALUES: after testing, set the limit to 25 and the cooldown to 2.0 * 60 * 60 (2h)
static const NSUInteger kSCIFeedPostLimit = 5;             // max number of posts per session
static const double kSCIFeedSettleSeconds = 10.0;          // delay so Instagram can load the fresh feed at launch
static const double kSCICooldownSeconds = 120.0;           // pause after the limit is reached (seconds)
static NSString *const kSCILockUntilKey = @"sci_feed_lock_until";

// ---- State ----
static NSArray *sciFrozenFeed = nil;          // in memory: resets on relaunch
static CFAbsoluteTime sciFirstFeedCall = 0;
static BOOL sciAlertShown = NO;

static BOOL sciIsPost(id obj) {
    return [obj isKindOfClass:%c(IGMedia)] || [obj isKindOfClass:%c(IGFeedItem)];
}

// Persistent cooldown (survives closing the app)
static double sciLockUntil(void) {
    return [[NSUserDefaults standardUserDefaults] doubleForKey:kSCILockUntilKey];
}

static BOOL sciIsLocked(void) {
    return [[NSDate date] timeIntervalSince1970] < sciLockUntil();
}

static void sciStartCooldown(void) {
    double until = [[NSDate date] timeIntervalSince1970] + kSCICooldownSeconds;
    [[NSUserDefaults standardUserDefaults] setDouble:until forKey:kSCILockUntilKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static void sciShowLockAlert(void) {
    if (sciAlertShown) return;
    sciAlertShown = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { window = w; break; }
                }
            }
            if (window) break;
        }

        UIViewController *vc = window.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        if (!vc) return;

        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"HH:mm";
        NSString *hour = [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:sciLockUntil()]];

        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Terminé pour le moment"
            message:[NSString stringWithFormat:@"Tu as vu tes %lu posts. Reviens à %@.", (unsigned long)kSCIFeedPostLimit, hour]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:alert animated:YES completion:nil];
    });
}

// Keeps everything up to and including the Nth post and drops the rest.
// Returns nil while there are fewer than N posts.
static NSArray *sciLimitedFeed(NSArray *list) {
    NSMutableArray *limited = [NSMutableArray array];
    NSUInteger posts = 0;

    for (id obj in list) {
        [limited addObject:obj];

        if (sciIsPost(obj)) {
            posts++;
            if (posts >= kSCIFeedPostLimit) return [limited copy];
        }
    }

    return nil;
}

// Suggested posts/reels
%hook IGMainFeedListAdapterDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {
    // Quota reached this session: always return the same feed
    if (sciFrozenFeed) return sciFrozenFeed;

    NSArray *filteredObjs = removeItemsInList(%orig, YES);

    // Cooldown still active (even after closing the app): feed without posts
    if (sciIsLocked()) {
        NSLog(@"[SCInsta] Feed locked until %f", sciLockUntil());
        sciShowLockAlert();

        return [filteredObjs filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary *bindings) {
                return !sciIsPost(obj)
                    && ![obj isKindOfClass:[%c(IGSpinnerLabelViewModel) class]]
                    && ![obj isKindOfClass:[%c(IGEndOfFeedDemarcatorModel) class]];
            }]
        ];
    }

    if (sciFirstFeedCall == 0) sciFirstFeedCall = CFAbsoluteTimeGetCurrent();
    BOOL settled = (CFAbsoluteTimeGetCurrent() - sciFirstFeedCall) > kSCIFeedSettleSeconds;

    NSArray *limited = sciLimitedFeed(filteredObjs);

    if (limited) {
        NSLog(@"[SCInsta] Feed limited to %lu posts (settled: %d)", (unsigned long)kSCIFeedPostLimit, settled);

        // Freeze and start the cooldown only after the delay, so the cached launch feed isn't counted
        if (settled) {
            sciFrozenFeed = limited;
            sciStartCooldown();
        }

        return limited;
    }

    // Fewer than N posts for now: remove the end-of-feed spinner like before
    return [filteredObjs filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary *bindings) {
            return ![obj isKindOfClass:[%c(IGSpinnerLabelViewModel) class]];
        }]
    ];
}
%end
%hook IGSundialFeedDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {
    NSArray *filteredList = removeItemsInList(%orig, NO);

    if ([SCIUtils getBoolPref:@"prevent_doom_scrolling"]) {
        double reelCount = [SCIUtils getDoublePref:@"doom_scrolling_reel_count"];
        return [filteredList subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)reelCount, filteredList.count))];
    }

    return filteredList;
}
%end
%hook IGContextualFeedViewController
- (NSArray *)objectsForListAdapter:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        return removeItemsInList(%orig, NO);
    }

    return %orig;
}
%end
%hook IGVideoFeedViewController
- (NSArray *)objectsForListAdapter:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        return removeItemsInList(%orig, NO);
    }

    return %orig;
}
%end
%hook IGChainingFeedViewController
- (NSArray *)objectsForListAdapter:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        return removeItemsInList(%orig, NO);
    }

    return %orig;
}
%end
%hook IGStoryAdPool
- (id)initWithUserSession:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        NSLog(@"[SCInsta] Removing ads");

        return nil;
    }

    return %orig;
}
%end
%hook IGStoryAdsManager
- (id)initWithUserSession:(id)arg1 storyViewerLoggingContext:(id)arg2 storyFullscreenSectionLoggingContext:(id)arg3 viewController:(id)arg4 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        NSLog(@"[SCInsta] Removing ads");

        return nil;
    }

    return %orig;
}
%end
%hook IGStoryAdsFetcher
- (id)initWithUserSession:(id)arg1 delegate:(id)arg2 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        NSLog(@"[SCInsta] Removing ads");

        return nil;
    }

    return %orig;
}
%end
// IG 148.0
%hook IGStoryAdsResponseParser
- (id)parsedObjectFromResponse:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        NSLog(@"[SCInsta] Removing ads");

        return nil;
    }

    return %orig;
}
- (id)initWithReelStore:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        NSLog(@"[SCInsta] Removing ads");

        return nil;
    }

    return %orig;
}
%end
%hook IGStoryAdsOptInTextView
- (id)initWithBrandedContentStyledString:(id)arg1 sponsoredPostLabel:(id)arg2 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        NSLog(@"[SCInsta] Removing ads");

        return nil;
    }

    return %orig;
}
%end
%hook IGSundialAdsResponseParser
- (id)parsedObjectFromResponse:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        NSLog(@"[SCInsta] Removing ads");

        return nil;
    }

    return %orig;
}
- (id)initWithMediaStore:(id)arg1 userStore:(id)arg2 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        NSLog(@"[SCInsta] Removing ads");
        
        return nil;
    }
    
    return %orig;
}
%end
// "Sponsored" posts on discover/search page
%hook IGExploreListKitDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        return removeItemsInList(%orig, NO);
    }

    return %orig;
}
%end
// Demangled name: IGExploreViewControllerSwift.IGExploreListKitDataSource
%hook _TtC28IGExploreViewControllerSwift26IGExploreListKitDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        return removeItemsInList(%orig, NO);
    }

    return %orig;
}
%end

// Hide shopping carousel in reel comments
// Demangled name: IGCommentThreadCommerceCarouselPill.IGCommentThreadCommerceCarousel
%hook _TtC35IGCommentThreadCommerceCarouselPill31IGCommentThreadCommerceCarousel
- (id)initWithFrame:(CGRect)frame pillText:(id)text pillStyle:(NSInteger)style {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        return nil;
    }

    return %orig(frame, text, style);
}
%end

// Hide suggested search/shopping on reels

// Demangled name: IGShoppableEverythingCommon.IGRapEntrypointResolver
%hook _TtC27IGShoppableEverythingCommon23IGRapEntrypointResolver
- (id)initWithLauncherSet:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        return nil;
    }

    return %orig(arg1);
}
%end
// Demangled name: IGSundialOrganicCTAContainerView.IGSundialOrganicCTAContainerView
%hook _TtC32IGSundialOrganicCTAContainerView32IGSundialOrganicCTAContainerView
- (void)didMoveToWindow {
    %orig;

    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        [self removeFromSuperview];
    }
}
%end


// Hide "suggested for you" text at end of feed
%hook IGEndOfFeedDemarcatorCellTopOfFeed
- (void)configureWithViewConfig:(id)arg1 {
    %orig;

    if ([SCIUtils getBoolPref:@"no_suggested_post"]) {
        NSLog(@"[SCInsta] Hiding end of feed message");

        // Hide suggested for you text
        UILabel *_titleLabel = MSHookIvar<UILabel *>(self, "_titleLabel");

        if (_titleLabel != nil) {
            [_titleLabel setText:@""];
        }
    }

    return;
}
%end
