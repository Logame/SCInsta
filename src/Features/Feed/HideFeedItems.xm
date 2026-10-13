#import "../../Utils.h"
#import "../../InstagramHeaders.h"

static NSArray *removeItemsInList(NSArray *list, BOOL isFeed) {
    NSArray *originalObjs = list;
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {

        // Suppression de toutes les videos et Reels dans le feed d'accueil
        if (isFeed) {
            // 1. Carrousel de Reels
            if ([obj isKindOfClass:%c(IGFeedScrollableClipsModel)]) {
                continue;
            }

            // 2. Publication video individuelle directe (IGMedia)
            if ([obj isKindOfClass:%c(IGMedia)]) {
                @try {
                    id mType = [obj valueForKey:@"mediaType"];
                    if (mType && [mType integerValue] == 2) {
                        continue;
                    }
                } @catch (NSException *e) {}
            }

            // 3. Publication encapsulée (IGFeedItem)
            if ([obj isKindOfClass:%c(IGFeedItem)]) {
                @try {
                    id media = [obj valueForKey:@"media"];
                    if (media) {
                        id mType = [media valueForKey:@"mediaType"];
                        if (mType && [mType integerValue] == 2) {
                            continue;
                        }
                    }
                } @catch (NSException *e) {}
            }
        }

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

// Hook feed principal
%hook IGMainFeedListAdapterDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {
    NSArray *filteredObjs = removeItemsInList(%orig, YES);

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

%hook IGExploreListKitDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        return removeItemsInList(%orig, NO);
    }
    return %orig;
}
%end

%hook _TtC28IGExploreViewControllerSwift26IGExploreListKitDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        return removeItemsInList(%orig, NO);
    }
    return %orig;
}
%end

%hook _TtC35IGCommentThreadCommerceCarouselPill31IGCommentThreadCommerceCarousel
- (id)initWithFrame:(CGRect)frame pillText:(id)text pillStyle:(NSInteger)style {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        return nil;
    }
    return %orig(frame, text, style);
}
%end

%hook _TtC27IGShoppableEverythingCommon23IGRapEntrypointResolver
- (id)initWithLauncherSet:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        return nil;
    }
    return %orig(arg1);
}
%end

%hook _TtC32IGSundialOrganicCTAContainerView32IGSundialOrganicCTAContainerView
- (void)didMoveToWindow {
    %orig;

    if ([SCIUtils getBoolPref:@"hide_ads"]) {
        [self removeFromSuperview];
    }
}
%end

%hook IGEndOfFeedDemarcatorCellTopOfFeed
- (void)configureWithViewConfig:(id)arg1 {
    %orig;

    if ([SCIUtils getBoolPref:@"no_suggested_post"]) {
        NSLog(@"[SCInsta] Hiding end of feed message");

        UILabel *_titleLabel = MSHookIvar<UILabel *>(self, "_titleLabel");
        if (_titleLabel != nil) {
            [_titleLabel setText:@""];
        }
    }
    return;
}
%end
