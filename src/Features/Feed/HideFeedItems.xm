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

     // Supprimer toutes les videos / Reels du feed d'accueil
        if (isFeed) {
            // Supprime les carrousels de Reels
            if ([obj isKindOfClass:%c(IGFeedScrollableClipsModel)]) {
                continue;
            }

            // Supprime tout post video / Reel individuel dans le feed
            if ([obj isKindOfClass:%c(IGMedia)]) {
                IGMedia *media = (IGMedia *)obj;
                // mediaType: 1 = Photo, 2 = Video/Reel
                if ([media respondsToSelector:@selector(mediaType)] && [media mediaType] == 2) {
                    continue;
                }
                if ([media respondsToSelector:@selector(isVideo)] && [media isVideo]) {
                    continue;
                }
            }
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

// ---- Feed limit settings (edit here) ----
static const NSUInteger kSCIFeedPostLimit = 3;        // max number of posts
static const double kSCIFeedSettleSeconds = 10.0;     // delay so Instagram can load the fresh feed at launch

// ---- In-memory state: resets when the app is closed and relaunched ----
static NSArray *sciFrozenFeed = nil;
static CFAbsoluteTime sciFirstFeedCall = 0;

static BOOL sciIsPost(id obj) {
    return [obj isKindOfClass:%c(IGMedia)] || [obj isKindOfClass:%c(IGFeedItem)];
}

// Keeps everything up to and including the Nth post (stories tray included) and drops the rest
// (more feed, loading spinner, end-of-feed). Returns nil while there are fewer than N posts.
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
    // Limit already reached: always return the same feed (no scroll, no refresh)
    if (sciFrozenFeed) return sciFrozenFeed;

    NSArray *filteredObjs = removeItemsInList(%orig, YES);

    if (sciFirstFeedCall == 0) sciFirstFeedCall = CFAbsoluteTimeGetCurrent();
    BOOL settled = (CFAbsoluteTimeGetCurrent() - sciFirstFeedCall) > kSCIFeedSettleSeconds;

    NSArray *limited = sciLimitedFeed(filteredObjs);

    if (limited) {
        NSLog(@"[SCInsta] Feed limited to %lu posts (frozen: %d)", (unsigned long)kSCIFeedPostLimit, settled);

        // Only freeze after the delay, so the cached launch feed isn't kept
        if (settled) sciFrozenFeed = limited;

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
