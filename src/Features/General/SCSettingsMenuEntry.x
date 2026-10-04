#import "../../InstagramHeaders.h"
#import "../../Settings/SCISettingsViewController.h"

// Since Instagram ~433 the profile navigation lives in a Swift module, so the
// old class name resolves to nil. Declare the mangled Swift class so Logos can hook it.
@interface _TtC19IGProfileNavigation24IGBadgedNavigationButton : UIView
@end

// Shared helpers -------------------------------------------------------------

static NSString *const kSCIGestureName = @"scinsta_settings_longpress";

static BOOL SCIIsProfileMoreButton(UIView *view) {
    NSString *ident = view.accessibilityIdentifier;
    return [ident isEqualToString:@"profile-more-button"]
        || [ident isEqualToString:@"profile-more-bar-button"];
}

static void SCIAttachSettingsLongPress(UIView *view, id target, SEL action, NSTimeInterval duration) {
    // Don't add our recognizer twice (replaces the old "gestureRecognizers == 0" guard,
    // which never passes on recent Instagram versions)
    for (UIGestureRecognizer *g in view.gestureRecognizers) {
        if ([g.name isEqualToString:kSCIGestureName]) return;
    }

    NSLog(@"[SCInsta] Adding tweak settings long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:target action:action];
    longPress.name = kSCIGestureName;
    longPress.minimumPressDuration = duration;

    // Make Instagram's own recognizers wait for ours to fail, so ours wins
    for (UIGestureRecognizer *existing in view.gestureRecognizers) {
        [existing requireGestureRecognizerToFail:longPress];
    }

    [view addGestureRecognizer:longPress];
}

// Show SCInsta tweak settings by holding on the settings/more icon under profile ----

// Old class name (Instagram <= 432)
%hook IGBadgedNavigationButton
- (void)didMoveToWindow {
    %orig;

    if (SCIIsProfileMoreButton(self)) {
        SCIAttachSettingsLongPress(self, self, @selector(handleLongPress:), 1.0);
    }
}

%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    NSLog(@"[SCInsta] Tweak settings gesture activated");
    [SCIUtils showSettingsVC:[self window]];
}
%end

// New Swift class name (Instagram 433+)
%hook _TtC19IGProfileNavigation24IGBadgedNavigationButton
- (void)didMoveToWindow {
    %orig;

    if (SCIIsProfileMoreButton(self)) {
        SCIAttachSettingsLongPress(self, self, @selector(handleLongPress:), 1.0);
    }
}

%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    NSLog(@"[SCInsta] Tweak settings gesture activated");
    [SCIUtils showSettingsVC:[self window]];
}
%end

// Quick access to tweak settings by holding on home tab button ----------------------
// CHANGED: this shortcut is now ALWAYS enabled (the "settings_shortcut" pref check was
// removed), so you can still open the settings even if the profile button is broken.
%hook IGTabBarButton
- (void)didMoveToSuperview {
    %orig;

    // Only work on home/feed tab
    if (![self.accessibilityIdentifier isEqualToString:@"mainfeed-tab"]) return;

    SCIAttachSettingsLongPress(self, self, @selector(handleLongPress:), 0.5);
}

%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    [SCIUtils showSettingsVC:[self window]];
}
%end
