#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, DPTweak) {
    DPEdgeToEdge, DPHideToolbar, DPSquareSidebarCorners, DPAnimatedCount,
    DPHideChatButton = DPAnimatedCount, DPHideSidebarButton, DPHideChatsButton, DPHideDownloadsButton, DPHideRecentTabsButton, DPHidePinnedTabsBackground, DPHideWindowControls, DPHidePinnedTabBorder, DPLiquidGlassBackground, DPLargerWindowCorners, DPShowExtensionsButton, DPRevealToolbarOnHover, DPTweakCount
};

static NSString *const DPKeys[DPTweakCount] = {@"edgeToEdge", @"hideToolbar", @"squareSidebarCorners", @"hideChatButton", @"hideSidebarButton", @"hideChatsButton", @"hideDownloadsButton", @"hideRecentTabsButton", @"hidePinnedTabsBackground", @"hideWindowControls", @"hidePinnedTabBorder", @"liquidGlassBackground", @"largerWindowCorners", @"extensionsButton", @"revealToolbarOnHover"};
static const BOOL DPDefaultsOn[DPTweakCount] = {YES, NO, YES, NO, NO, NO, NO, NO, NO, NO, NO, NO, NO, YES, YES};
static const CGFloat DPWindowPadding = 6;
static const CFTimeInterval DPAnimationDuration = 0.25;
static const CGFloat DPLargerCornerRadius = 26;
static const CGFloat DPToolbarButtonSize = 30, DPToolbarSlot = 35;  // Dia's translate button and the gap after it
static const CGFloat DPRevealEdge = 8;  // how near the top of the page the pointer brings back a hidden toolbar
static const NSTimeInterval DPRevealDelay = 0.12, DPConcealDelay = 1.4;

static BOOL DPOn[DPTweakCount];
static CGFloat DPProgress[DPAnimatedCount];
static NSUserDefaults *DPDefaults;
static NSHashTable<NSView *> *DPContainers, *DPPanes, *DPBars, *DPSuppressed;
static char DPRequestedFrameKey, DPAssignedFrameKey, DPButtonKey, DPBaseRadiusKey, DPAssignedRadiusKey, DPFillsKey, DPChatKey, DPOriginalPathKey, DPAssignedPathKey, DPGlassKey, DPWindowColorKey, DPCornerRadiusKey, DPExtensionsKey, DPRevealedKey, DPPendingRevealKey;

static NSString *DPCLI(void) {
    return [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"DiaPatches/bin/diapatch"];
}

static void DPRunCLI(NSArray<NSString *> *args, void (^completion)(NSString *output)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSTask *task = [NSTask new];
        task.executableURL = [NSURL fileURLWithPath:DPCLI()];
        task.arguments = args;
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError = NSFileHandle.fileHandleWithNullDevice;
        NSString *output = nil;
        if ([task launchAndReturnError:nil]) {
            NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
            [task waitUntilExit];
            if (task.terminationStatus == 0) output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(output); });
    });
}

static void DPHandOffAndQuit(NSString *command) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:DPCLI()];
    task.arguments = @[command, @"--wait", @(getpid()).stringValue, @"--relaunch"];
    if ([task launchAndReturnError:nil]) [NSApp terminate:nil];
}

static NSView *DPFindView(NSView *root, BOOL (^match)(NSView *)) {
    if (!root || match(root)) return root;
    for (NSView *sub in root.subviews) {
        NSView *found = DPFindView(sub, match);
        if (found) return found;
    }
    return nil;
}

#pragma mark - Hooks

typedef struct { Class cls; SEL sel; IMP imp; } DPOriginal;
static DPOriginal DPOriginals[64];
static int DPOriginalCount;

static void DPHook(Class cls, SEL sel, IMP replacement) {
    Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
    if (!method || method_getImplementation(method) == replacement || DPOriginalCount == 64) return;
    IMP original = method_getImplementation(method);
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(method))) method_setImplementation(method, replacement);
    DPOriginals[DPOriginalCount++] = (DPOriginal){cls, sel, original};
}

static IMP DPOriginalIMP(id object, SEL sel) {
    for (Class c = object_getClass(object); c; c = class_getSuperclass(c))
        for (int i = 0; i < DPOriginalCount; i++)
            if (DPOriginals[i].cls == c && DPOriginals[i].sel == sel) return DPOriginals[i].imp;
    abort();
}

#define DPCallOriginal(type, object, sel, ...) ((type)DPOriginalIMP(object, sel))(object, sel, ##__VA_ARGS__)

#pragma mark - Toolbar buttons

static Class DPDownloadsButtonClass(void) {
    static Class cls;
    return cls = cls ?: NSClassFromString(@"_TtC10TabSurface19DownloadsButtonView");
}

static Class DPChatsButtonClass(void) {
    static Class cls;
    return cls = cls ?: NSClassFromString(@"_TtC10DiaLibrary17LibraryButtonView");
}

static Class DPChatsRowClass(void) {
    static Class cls;
    return cls = cls ?: NSClassFromString(@"_TtC10TabSidebar15LibraryCellView");
}

static Class DPSidebarFooterClass(void) {
    static Class cls;
    return cls = cls ?: NSClassFromString(@"_TtC10TabSidebar26SidebarContainerFooterView");
}

static Class DPWindowControlsClass(void) {
    static Class cls;
    return cls = cls ?: NSClassFromString(@"_TtC5ARCUI21WindowStandardButtons");
}

static Class DPSelectionOutlineClass(void) {
    static Class cls;
    return cls = cls ?: NSClassFromString(@"_TtC5TabUIP33_CFF5B89D7BC9743BBA6108D119E2E37020SelectionOutlineView");
}

static Class DPPinnedTabsClass(void) {
    static Class cls;
    return cls = cls ?: NSClassFromString(@"_TtC8TabStrip16TabStripDockView");
}

static Class DPDebossedClass(void) {
    static Class cls;
    return cls = cls ?: NSClassFromString(@"_TtC5TabUI12DebossedView");
}

static NSInteger DPButtonTweak(NSView *view) {
    NSNumber *tweak = objc_getAssociatedObject(view, &DPButtonKey);
    if (tweak) return tweak.integerValue;
    NSString *label = view.accessibilityLabel;
    NSInteger match = [label isEqualToString:@"Chat with this tab"] ? DPHideChatButton
                    : [label isEqualToString:@"Toggle sidebar"]     ? DPHideSidebarButton
                    : [label isEqualToString:@"Recent tabs"]        ? DPHideRecentTabsButton
                    : [view isKindOfClass:DPDownloadsButtonClass()] ? DPHideDownloadsButton
                    : [view isKindOfClass:DPChatsButtonClass()]     ? DPHideChatsButton
                    : [view isKindOfClass:DPChatsRowClass()]        ? DPHideChatsButton
                    : [view isKindOfClass:DPWindowControlsClass()]  ? DPHideWindowControls
                    : [view isKindOfClass:DPSelectionOutlineClass()] ? DPHidePinnedTabBorder
                    : [view isKindOfClass:DPDebossedClass()] && [view.superview isKindOfClass:DPPinnedTabsClass()] ? DPHidePinnedTabsBackground
                                                                    : -1;
    if (match >= 0) objc_setAssociatedObject(view, &DPButtonKey, @(match), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return match;
}

static void DPButton_setHidden(NSView *self, SEL _cmd, BOOL hidden) {
    NSInteger tweak = DPButtonTweak(self);
    BOOL suppress = !hidden && tweak >= 0 && DPOn[tweak];
    if (suppress) [DPSuppressed addObject:self];
    else [DPSuppressed removeObject:self];
    DPCallOriginal(void (*)(id, SEL, BOOL), self, _cmd, hidden || suppress);
}

static void DPEnforceButton(NSView *view) {
    NSInteger tweak = DPButtonTweak(view);
    if (tweak < 0) return;
    DPHook(view.class, @selector(setHidden:), (IMP)DPButton_setHidden);
    if (!DPOn[tweak] || view.hidden) return;
    [DPSuppressed addObject:view];
    DPCallOriginal(void (*)(id, SEL, BOOL), view, @selector(setHidden:), YES);
}

static void DPButton_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(void (*)(id, SEL), self, _cmd);
    DPEnforceButton(self);
}

static BOOL DPEnforceButtons(NSView *view) {
    if (DPButtonTweak(view) >= 0) {
        DPHook(view.class, @selector(viewDidMoveToWindow), (IMP)DPButton_viewDidMoveToWindow);
        BOOL wasHidden = view.hidden;
        DPEnforceButton(view);
        return view.hidden != wasHidden;
    }
    BOOL changed = NO;
    for (NSView *sub in view.subviews) changed |= DPEnforceButtons(sub);
    return changed;
}

static void DPApplyExtensionsButton(NSView *bar);

static void DPBar_layout(NSView *self, SEL _cmd) {
    [DPBars addObject:self];
    DPEnforceButtons(self);
    DPCallOriginal(void (*)(id, SEL), self, _cmd);
    DPApplyExtensionsButton(self);
}

// Dia lays out the tab strip's buttons here and closes the gap for Recent tabs, but not for Downloads.
static void DPTabStrip_viewWillLayout(NSViewController *self, SEL _cmd) {
    NSView *strip = self.view, *downloads = nil, *chats = nil;
    [DPBars addObject:strip];
    for (NSView *sub in strip.subviews) {
        NSInteger tweak = DPButtonTweak(sub);
        if (tweak < 0) continue;
        DPEnforceButtons(sub);
        if (tweak == DPHideDownloadsButton) downloads = sub;
        if (tweak == DPHideChatsButton) chats = sub;
    }
    DPCallOriginal(void (*)(id, SEL), self, _cmd);
    if (DPOn[DPHideDownloadsButton] && downloads && chats) [chats setFrameOrigin:downloads.frame.origin];
}

// With nothing left in it, the sidebar header shrinks to the window padding and the pinned tabs move up. It stays in place because it's what drags the window.
static void DPCollapseSidebarHeader(NSView *sidebar) {
    if (!DPOn[DPHideWindowControls]) return;
    NSView *header = nil;
    for (NSView *sub in sidebar.subviews) if ([sub isKindOfClass:NSClassFromString(@"_TtC10TabSidebar17SidebarHeaderView")]) header = sub;
    NSView *stack = DPFindView(header, ^BOOL(NSView *v) { return [v isKindOfClass:NSStackView.class]; });
    if (!stack) return;
    for (NSView *item in stack.subviews) if (!item.hidden && item.subviews.count) return;
    CGFloat bottom = NSMaxY(header.frame), gap = NSHeight(header.frame) - DPWindowPadding;
    if (gap <= 0) return;
    for (NSView *sub in sidebar.subviews) {
        if (fabs(NSMinY(sub.frame) - bottom) > 0.5) continue;
        NSRect frame = sub.frame;
        frame.origin.y -= gap;
        frame.size.height += gap;
        sub.frame = frame;
    }
    [header setFrameSize:NSMakeSize(NSWidth(header.frame), DPWindowPadding)];
}

// With both of its items hidden the sidebar footer is an empty band, so the tab list takes its place.
static void DPSidebar_viewWillLayout(NSViewController *self, SEL _cmd) {
    DPCallOriginal(void (*)(id, SEL), self, _cmd);
    NSView *sidebar = self.view, *footer = nil;
    [DPBars addObject:sidebar];
    DPCollapseSidebarHeader(sidebar);
    for (NSView *sub in sidebar.subviews) if ([sub isKindOfClass:DPSidebarFooterClass()]) footer = sub;
    if (!footer) return;
    BOOL empty = DPOn[DPHideChatsButton] && DPOn[DPHideRecentTabsButton];
    if (!empty) {
        if ([DPSuppressed containsObject:footer]) footer.hidden = NO;
        [DPSuppressed removeObject:footer];
        return;
    }
    if (!footer.hidden) {
        footer.hidden = YES;
        [DPSuppressed addObject:footer];
    }
    for (NSView *sub in sidebar.subviews) {
        if (fabs(NSMaxY(sub.frame) - NSMinY(footer.frame)) > 0.5) continue;
        NSRect frame = sub.frame;
        frame.size.height += NSHeight(footer.frame);
        sub.frame = frame;
    }
}

// The visible border is a masked gradient layer. Dia shows and hides it with selection and never touches its opacity.
static void DPPinnedTab_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(void (*)(id, SEL), self, _cmd);
    [DPBars addObject:self];
    DPEnforceButtons(self);
    for (CALayer *layer in self.subviews.firstObject.layer.sublayers)
        if ([layer isKindOfClass:CAGradientLayer.class]) layer.opacity = DPOn[DPHidePinnedTabBorder] ? 0 : 1;
}

// Dia creates this background lazily, and each tab inside has a debossed view of its own, so only direct children count.
static void DPPinnedTabs_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(void (*)(id, SEL), self, _cmd);
    [DPBars addObject:self];
    for (NSView *sub in self.subviews) if (DPButtonTweak(sub) >= 0) DPEnforceButtons(sub);
}

static void DPRelayoutBars(void) {
    for (NSView *bar in DPBars.allObjects) {
        bar.needsLayout = YES;
        [bar layoutSubtreeIfNeeded];
    }
}

static void DPRestoreButtons(DPTweak tweak) {
    for (NSView *view in DPSuppressed.allObjects)
        if (DPButtonTweak(view) == tweak) view.hidden = NO;
}

#pragma mark - Edge-to-edge

// With Chat open Dia animates sidebar changes from its own geometry, so edge-to-edge steps aside.
static NSView *DPChatCard(NSView *container) {
    NSView *content = DPFindView(container, ^BOOL(NSView *v) { return v != container && v.layer.masksToBounds && v.layer.cornerRadius > 0; });
    NSSize size = content.bounds.size;
    BOOL (^isCard)(NSView *) = ^BOOL(NSView *v) {
        return v.layer.masksToBounds && v.layer.cornerRadius > 0 && NSWidth(v.bounds) > size.width / 4 && NSHeight(v.bounds) > size.height / 2;
    };
    for (NSView *root in content.subviews)
        for (NSView *host in root.subviews) {
            if (NSMinX(host.frame) < 2 && NSMinY(host.frame) < 2) continue;
            if (isCard(host)) return host;
            for (NSView *card in host.subviews) if (isCard(card)) return card;
        }
    return nil;
}

static NSRect DPEdgeToEdgeFrame(NSView *view, NSRect frame) {
    CGFloat inset = DPProgress[DPEdgeToEdge] * DPWindowPadding;
    NSView *superview = view.superview;
    if (inset == 0 || !superview || DPChatCard(view)) return frame;
    NSRect bounds = superview.bounds;
    CGFloat left = NSMinX(frame) - NSMinX(bounds), right = NSMaxX(bounds) - NSMaxX(frame);
    CGFloat top = superview.isFlipped ? NSMinY(frame) - NSMinY(bounds) : NSMaxY(bounds) - NSMaxY(frame);
    CGFloat bottom = superview.isFlipped ? NSMaxY(bounds) - NSMaxY(frame) : NSMinY(frame) - NSMinY(bounds);
    BOOL (^isPadding)(CGFloat) = ^BOOL(CGFloat gap) { return fabs(gap - DPWindowPadding) < 0.5; };
    if (isPadding(left)) frame.origin.x -= inset, frame.size.width += inset;
    if (isPadding(right)) frame.size.width += inset;
    // The top gap also includes any title bar or menu bar offset.
    if (top > DPWindowPadding - 0.5) {
        frame.size.height += inset;
        if (superview.isFlipped) frame.origin.y -= inset;
    }
    if (isPadding(bottom)) {
        frame.size.height += inset;
        if (!superview.isFlipped) frame.origin.y -= inset;
    }
    return frame;
}

// Keeps the page concentric with the window when the window's corners grow.
static CGFloat DPWindowCornerGrowth(NSWindow *window) {
    NSNumber *original = window ? objc_getAssociatedObject(window, &DPCornerRadiusKey) : nil;
    return DPOn[DPLargerWindowCorners] && original ? DPLargerCornerRadius - original.doubleValue : 0;
}

static void DPSetCornerRadius(NSView *container, CGFloat inset) {
    static ptrdiff_t offset = -1;
    if (offset < 0) {
        Ivar ivar = class_getInstanceVariable(container.class, "cornerRadius");
        offset = ivar ? ivar_getOffset(ivar) : 0;
    }
    if (!offset) return;
    CGFloat *radius = (CGFloat *)((uint8_t *)(__bridge void *)container + offset);
    NSNumber *assigned = objc_getAssociatedObject(container, &DPAssignedRadiusKey);
    CGFloat base = assigned && assigned.doubleValue == *radius ? [objc_getAssociatedObject(container, &DPBaseRadiusKey) doubleValue] : *radius;
    CGFloat target = base + inset + DPWindowCornerGrowth(container.window);
    objc_setAssociatedObject(container, &DPBaseRadiusKey, @(base), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(container, &DPAssignedRadiusKey, @(target), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (*radius == target) return;
    *radius = target;
    container.needsLayout = YES;
}

static void DPContainer_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    objc_setAssociatedObject(self, &DPRequestedFrameKey, [NSValue valueWithRect:frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [DPContainers addObject:self];
    NSRect adjusted = DPEdgeToEdgeFrame(self, frame);
    DPSetCornerRadius(self, NSEqualRects(adjusted, frame) ? 0 : DPProgress[DPEdgeToEdge] * DPWindowPadding);
    DPCallOriginal(void (*)(id, SEL, NSRect), self, _cmd, adjusted);
}

// Scales the corners of the path's first subpath in place; same elements, so Dia's path animations still interpolate.
static CGPathRef DPReshapeCorners(CGPathRef path, CGFloat extent, CGFloat rightScale, CGFloat leftScale) {
    if (!path) return NULL;
    __block CGRect box = CGRectNull;
    __block int subpath = 0;
    CGPathApplyWithBlock(path, ^(const CGPathElement *element) {
        if (element->type == kCGPathElementMoveToPoint && !CGRectIsNull(box)) subpath++;
        int count = element->type == kCGPathElementAddCurveToPoint ? 3 : element->type == kCGPathElementAddQuadCurveToPoint ? 2
                  : element->type == kCGPathElementCloseSubpath ? 0 : 1;
        for (int i = 0; i < count && subpath == 0; i++) box = CGRectUnion(box, (CGRect){element->points[i], CGSizeZero});
    });
    CGMutablePathRef reshaped = CGPathCreateMutable();
    subpath = 0;
    __block BOOL started = NO;
    CGPoint (^move)(CGPoint) = ^CGPoint(CGPoint p) {
        if (subpath > 0) return p;
        CGFloat cx = p.x - CGRectGetMinX(box) < extent ? CGRectGetMinX(box) : CGRectGetMaxX(box) - p.x < extent ? CGRectGetMaxX(box) : NAN;
        CGFloat cy = p.y - CGRectGetMinY(box) < extent ? CGRectGetMinY(box) : CGRectGetMaxY(box) - p.y < extent ? CGRectGetMaxY(box) : NAN;
        if (isnan(cx) || isnan(cy)) return p;
        CGFloat scale = cx == CGRectGetMinX(box) ? leftScale : rightScale;
        return CGPointMake(cx + (p.x - cx) * scale, cy + (p.y - cy) * scale);
    };
    CGPathApplyWithBlock(path, ^(const CGPathElement *element) {
        const CGPoint *p = element->points;
        switch (element->type) {
            case kCGPathElementMoveToPoint:
                if (started) subpath++;
                started = YES;
                CGPathMoveToPoint(reshaped, NULL, move(p[0]).x, move(p[0]).y);
                break;
            case kCGPathElementAddLineToPoint: CGPathAddLineToPoint(reshaped, NULL, move(p[0]).x, move(p[0]).y); break;
            case kCGPathElementAddQuadCurveToPoint:
                CGPathAddQuadCurveToPoint(reshaped, NULL, move(p[0]).x, move(p[0]).y, move(p[1]).x, move(p[1]).y);
                break;
            case kCGPathElementAddCurveToPoint:
                CGPathAddCurveToPoint(reshaped, NULL, move(p[0]).x, move(p[0]).y, move(p[1]).x, move(p[1]).y, move(p[2]).x, move(p[2]).y);
                break;
            case kCGPathElementCloseSubpath: CGPathCloseSubpath(reshaped); break;
        }
    });
    return (CGPathRef)CFAutorelease(reshaped);
}

static void DPApplySquareCorners(NSView *container) {
    NSView *content = DPFindView(container, ^BOOL(NSView *v) { return v != container && v.layer.masksToBounds && v.layer.cornerRadius > 0; });
    CALayer *layer = content.layer;
    if (!layer) return;
    layer.cornerCurve = kCACornerCurveContinuous;
    CGFloat square = NSMinX(container.frame) > DPWindowPadding + 1 && !DPChatCard(container)
        ? DPProgress[DPSquareSidebarCorners] * DPProgress[DPEdgeToEdge] : 0;
    CACornerMask left = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner, right = kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (square == 0 || square == 1) {
        layer.mask = nil;
        layer.maskedCorners = square == 1 ? right : left | right;
    } else {
        CALayer *mask = layer.mask.sublayers.count == 2 ? layer.mask : [CALayer layer];
        if (mask != layer.mask) {
            for (int i = 0; i < 2; i++) {
                CALayer *half = [CALayer layer];
                half.backgroundColor = NSColor.blackColor.CGColor;
                half.cornerCurve = kCACornerCurveContinuous;
                half.maskedCorners = i ? right : left;
                [mask addSublayer:half];
            }
        }
        CGRect bounds = layer.bounds;
        CGFloat half = CGRectGetWidth(bounds) / 2;
        mask.frame = bounds;
        mask.sublayers[0].frame = CGRectMake(0, 0, half + 1, CGRectGetHeight(bounds));
        mask.sublayers[1].frame = CGRectMake(half - 1, 0, half + 1, CGRectGetHeight(bounds));
        mask.sublayers[0].cornerRadius = layer.cornerRadius * (1 - square);
        mask.sublayers[1].cornerRadius = layer.cornerRadius;
        layer.mask = mask;
        layer.maskedCorners = 0;
    }

    CGFloat base = [objc_getAssociatedObject(container, &DPBaseRadiusKey) doubleValue] ?: layer.cornerRadius;
    CGFloat grow = base > 0 ? layer.cornerRadius / base : 1;
    for (NSView *sub in container.subviews)
        for (CALayer *sublayer in sub.layer.sublayers) {
            CAShapeLayer *shape = [sublayer isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)sublayer
                                : [sublayer.mask isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)sublayer.mask : nil;
            if (!shape.path || CGRectGetWidth(CGPathGetBoundingBox(shape.path)) < NSWidth(container.bounds) * 0.9) continue;
            CGPathRef assigned = (__bridge CGPathRef)objc_getAssociatedObject(shape, &DPAssignedPathKey);
            if (!assigned || !CGPathEqualToPath(assigned, shape.path))
                objc_setAssociatedObject(shape, &DPOriginalPathKey, CFBridgingRelease(CGPathCreateCopy(shape.path)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            CGPathRef path = DPReshapeCorners((__bridge CGPathRef)objc_getAssociatedObject(shape, &DPOriginalPathKey), base * 1.6, grow, grow * (1 - square));
            if (!CGPathEqualToPath(path, shape.path)) shape.path = path;
            objc_setAssociatedObject(shape, &DPAssignedPathKey, (__bridge id)shape.path, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    [CATransaction commit];
}

static Class DPContainerClass(void) {
    static Class cls;
    return cls = cls ?: NSClassFromString(@"_TtC6Window20ContentContainerView");
}

static void DPRestyleContainer(NSView *container) {
    DPApplySquareCorners(container);
    CALayer *card = DPChatCard(container).layer;
    if (!card) return;
    if (card.cornerCurve != kCACornerCurveContinuous) card.cornerCurve = kCACornerCurveContinuous;
    NSValue *requested = objc_getAssociatedObject(container, &DPRequestedFrameKey);
    if (requested && !NSEqualRects(container.frame, requested.rectValue)) container.frame = requested.rectValue;
}

// Dia restyles its layers after its own layout pass.
static void DPContainer_layoutOrUpdateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(void (*)(id, SEL), self, _cmd);
    DPRestyleContainer(self);
    dispatch_async(dispatch_get_main_queue(), ^{ DPRestyleContainer(self); });
}

// Opening or closing Chat reshapes the content without resizing the container.
static void DPShadow_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(void (*)(id, SEL), self, _cmd);
    NSView *container = self;
    while (container && ![container isKindOfClass:DPContainerClass()]) container = container.superview;
    if (!container) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL chat = DPChatCard(container) != nil;
        if ([objc_getAssociatedObject(container, &DPChatKey) boolValue] != chat) {
            objc_setAssociatedObject(container, &DPChatKey, @(chat), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSValue *requested = objc_getAssociatedObject(container, &DPRequestedFrameKey);
            if (requested) container.frame = requested.rectValue;
        }
        DPRestyleContainer(container);
    });
}

#pragma mark - Toolbar

static NSRect DPLaidOutFrame(NSView *view) {
    NSValue *assigned = objc_getAssociatedObject(view, &DPAssignedFrameKey);
    if (assigned && NSEqualRects(assigned.rectValue, view.frame))
        return [objc_getAssociatedObject(view, &DPRequestedFrameKey) rectValue];
    return view.frame;
}

static void DPAssignFrame(NSView *view, NSRect laidOut, NSRect frame) {
    objc_setAssociatedObject(view, &DPRequestedFrameKey, [NSValue valueWithRect:laidOut], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &DPAssignedFrameKey, [NSValue valueWithRect:frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.frame = frame;
}

static Class DPToolbarClass(void) {
    static Class cls;
    return cls = cls ?: NSClassFromString(@"_TtC13NavigationBar17NavigationBarView");
}

#pragma mark - Extensions button

static NSMenu *DPExtensionsMenu(void) {
    for (NSMenuItem *item in NSApp.mainMenu.itemArray)
        if ([item.title isEqualToString:@"Extensions"]) return item.submenu;
    return nil;
}

@interface DPExtensionsMenuButton : NSButton
@end

@implementation DPExtensionsMenuButton

- (instancetype)init {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.bordered = NO;
    self.imagePosition = NSImageOnly;
    self.image = [NSImage imageWithSystemSymbolName:@"puzzlepiece.extension" accessibilityDescription:@"Extensions"];
    self.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium];
    self.contentTintColor = NSColor.secondaryLabelColor;
    self.toolTip = @"Extensions";
    self.target = self;
    self.action = @selector(showExtensions:);
    self.wantsLayer = YES;
    self.layer.cornerRadius = 7;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                       options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
                                                         owner:self
                                                      userInfo:nil]];
    return self;
}

- (void)setHovered:(BOOL)hovered {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = hovered ? [NSColor.labelColor colorWithAlphaComponent:0.08].CGColor : nil;
    }];
}

- (void)mouseEntered:(NSEvent *)event { [self setHovered:YES]; }
- (void)mouseExited:(NSEvent *)event { [self setHovered:NO]; }

// Like Dia's own menus, open on mouse down.
- (void)mouseDown:(NSEvent *)event { [self showExtensions:self]; }

- (void)showExtensions:(id)sender {
    NSMenu *menu = DPExtensionsMenu();
    if (!menu) return NSBeep();
    [self setHovered:YES];
    NSPoint below = NSMakePoint(NSMinX(self.bounds), self.isFlipped ? NSMaxY(self.bounds) + 4 : NSMinY(self.bounds) - 4);
    [menu popUpMenuPositioningItem:nil atLocation:below inView:self];
    [self setHovered:NO];
}

@end

static Class DPPinnedExtensionsClass(void) {
    static Class cls;
    return cls = cls ?: NSClassFromString(@"_TtC16PinnedExtensions20PinnedExtensionsView");
}

static Class DPAddressBarClass(void) {
    static Class cls;
    return cls = cls ?: NSClassFromString(@"_TtC13NavigationBar16AssistantBarView");
}

static Class DPTranslateButtonClass(void) {
    static Class cls;
    return cls = cls ?: NSClassFromString(@"_TtC15TranslateButton19TranslateButtonView");
}

static BOOL DPExtensionsButtonShown(NSView *view) {
    while (view && ![view isKindOfClass:DPToolbarClass()]) view = view.superview;
    NSView *button = view ? objc_getAssociatedObject(view, &DPExtensionsKey) : nil;
    return button && !button.hidden;
}

// Dia sizes the address bar and places the translate button outside the toolbar's layout pass.
static void DPMakeRoom_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    NSRect adjusted = frame;
    if (DPExtensionsButtonShown(self)) {
        if ([self isKindOfClass:DPAddressBarClass()]) adjusted.size.width -= DPToolbarSlot;
        else adjusted.origin.x -= DPToolbarSlot;
    }
    objc_setAssociatedObject(self, &DPRequestedFrameKey, [NSValue valueWithRect:frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &DPAssignedFrameKey, [NSValue valueWithRect:adjusted], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DPCallOriginal(void (*)(id, SEL, NSRect), self, _cmd, adjusted);
}

// The button takes the translate button's slot beside the pinned extensions; the address bar gives up the room,
// and the translate button, which Dia shows only on some pages, moves one slot left.
static void DPApplyExtensionsButton(NSView *bar) {
    if (![bar isKindOfClass:DPToolbarClass()]) return;  // DPBar_layout also runs for the sidebar's header and footer
    NSView *pinned = DPFindView(bar, ^BOOL(NSView *v) { return [v isKindOfClass:DPPinnedExtensionsClass()]; });
    NSView *address = DPFindView(bar, ^BOOL(NSView *v) { return [v isKindOfClass:DPAddressBarClass()]; });
    NSView *translate = DPFindView(bar, ^BOOL(NSView *v) { return [v isKindOfClass:DPTranslateButtonClass()]; });
    DPExtensionsMenuButton *button = objc_getAssociatedObject(bar, &DPExtensionsKey);
    BOOL on = DPOn[DPShowExtensionsButton] && pinned && !pinned.hidden && address;  // Dia hides extensions on its own pages
    if (on && !button) {
        button = [DPExtensionsMenuButton new];
        objc_setAssociatedObject(bar, &DPExtensionsKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [bar addSubview:button];
    }
    button.hidden = !on;
    // Reapplied through DPMakeRoom_setFrame.
    if (address) address.frame = DPLaidOutFrame(address);
    if (translate) translate.frame = DPLaidOutFrame(translate);
    if (!on) return;
    NSRect anchor = [bar convertRect:pinned.frame fromView:pinned.superview];
    button.frame = NSMakeRect(NSMinX(anchor) - DPToolbarSlot, round(NSMidY(bar.bounds) - DPToolbarButtonSize / 2),
                              DPToolbarButtonSize, DPToolbarButtonSize);
}

// A hidden toolbar shown on hover floats over the page instead of pushing it down.
static BOOL DPRevealed(NSView *bar) { return [objc_getAssociatedObject(bar, &DPRevealedKey) boolValue]; }

// The bar stays in Dia's layout: hiding it makes Dia reflow in ways it won't undo.
static NSView *DPToolbar_hitTest(NSView *self, SEL _cmd, NSPoint point) {
    return DPOn[DPHideToolbar] && !DPRevealed(self) ? nil : DPCallOriginal(NSView *(*)(id, SEL, NSPoint), self, _cmd, point);
}

static NSView *DPPaneBar(NSView *pane) {
    for (NSView *sub in pane.subviews) if ([sub isKindOfClass:DPToolbarClass()]) return sub;
    return nil;
}

static void DPApplyToolbar(NSView *pane) {
    NSView *bar = DPPaneBar(pane);
    if (!bar) return;

    CGFloat progress = DPProgress[DPHideToolbar];
    BOOL revealed = DPRevealed(bar), below = progress > 0 && !revealed;
    bar.alphaValue = revealed ? 1 : 1 - progress;
    NSView *lowest = pane.subviews.firstObject;
    if (below != (lowest == bar)) {
        // Reordering removes the bar for a moment, which would take focus from the address bar.
        NSWindow *window = pane.window;
        NSResponder *focus = window.firstResponder;
        if (below) [pane addSubview:bar positioned:NSWindowBelow relativeTo:lowest];
        else [pane addSubview:bar positioned:NSWindowAbove relativeTo:nil];
        if (window.firstResponder != focus) [window makeFirstResponder:focus];
    }

    BOOL flipped = pane.isFlipped;
    CGFloat (^top)(NSRect) = ^CGFloat(NSRect r) { return flipped ? NSMinY(r) : NSHeight(pane.bounds) - NSMaxY(r); };
    CGFloat (^bottom)(NSRect) = ^CGFloat(NSRect r) { return flipped ? NSMaxY(r) : NSHeight(pane.bounds) - NSMinY(r); };
    CGFloat shift = NSHeight(bar.frame) * progress, edge = bottom(bar.frame);
    NSMutableArray<NSView *> *stack = [NSMutableArray new];
    for (NSView *sub in pane.subviews) if (sub != bar) [stack addObject:sub];
    [stack sortUsingComparator:^NSComparisonResult(NSView *a, NSView *b) {
        return [@(top(DPLaidOutFrame(a))) compare:@(top(DPLaidOutFrame(b)))];
    }];
    for (NSView *view in stack) {
        NSRect laidOut = DPLaidOutFrame(view);
        if (fabs(top(laidOut) - edge) > 0.5) continue;
        BOOL reachesBottom = fabs(bottom(laidOut) - NSHeight(pane.bounds)) < 0.5;
        if (!reachesBottom) edge = bottom(laidOut);
        NSRect frame = laidOut;
        if (reachesBottom) frame.size.height += shift;
        if (flipped) frame.origin.y -= shift;
        else if (!reachesBottom) frame.origin.y += shift;
        DPAssignFrame(view, laidOut, frame);
        // Dia sizes the web view once instead of autoresizing it.
        for (NSView *child in view.subviews) {
            if (!objc_getAssociatedObject(child, &DPFillsKey)) {
                if (!NSEqualRects(child.frame, (NSRect){NSZeroPoint, laidOut.size})) continue;
                objc_setAssociatedObject(child, &DPFillsKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            child.frame = view.bounds;
        }
    }
}

static void DPPane_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(void (*)(id, SEL), self, _cmd);
    [DPPanes addObject:self];
    DPApplyToolbar(self);
}

#pragma mark - Toolbar on hover

static void DPSetRevealed(NSView *pane, NSView *bar, BOOL revealed) {
    objc_setAssociatedObject(bar, &DPPendingRevealKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (DPRevealed(bar) == revealed) return;
    CGFloat from = bar.alphaValue;
    objc_setAssociatedObject(bar, &DPRevealedKey, @(revealed), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DPApplyToolbar(pane);
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @(from);
    fade.duration = 0.15;
    [bar.layer addAnimation:fade forKey:@"DPReveal"];
}

// Shown while the pointer is at the top edge or over the bar, and while the address bar has focus.
static BOOL DPWantsReveal(NSView *pane, NSView *bar) {
    NSWindow *window = pane.window;
    NSResponder *focus = window.firstResponder;
    if ([focus isKindOfClass:NSView.class] && [(NSView *)focus isDescendantOf:bar]) return YES;
    NSPoint point = [pane convertPoint:window.mouseLocationOutsideOfEventStream fromView:nil];
    if (point.x < 0 || point.x > NSWidth(pane.bounds)) return NO;
    CGFloat depth = pane.isFlipped ? point.y : NSHeight(pane.bounds) - point.y;
    CGFloat barBottom = pane.isFlipped ? NSMaxY(bar.frame) : NSHeight(pane.bounds) - NSMinY(bar.frame);
    return depth > -2 * DPRevealEdge && depth <= (DPRevealed(bar) ? barBottom + 4 : DPRevealEdge);
}

static void DPScheduleReveal(NSView *pane, NSView *bar, BOOL wanted) {
    NSNumber *pending = objc_getAssociatedObject(bar, &DPPendingRevealKey);
    if (DPRevealed(bar) == wanted) {
        objc_setAssociatedObject(bar, &DPPendingRevealKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (pending && pending.boolValue == wanted) return;
    pending = @(wanted);
    objc_setAssociatedObject(bar, &DPPendingRevealKey, pending, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSTimeInterval delay = wanted ? DPRevealDelay : DPConcealDelay;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (objc_getAssociatedObject(bar, &DPPendingRevealKey) == pending) DPSetRevealed(pane, bar, wanted);
    });
}

static void DPUpdateReveal(NSWindow *window) {
    if (!DPOn[DPHideToolbar] || !DPOn[DPRevealToolbarOnHover]) return;
    for (NSView *pane in DPPanes) {
        NSView *bar = DPPaneBar(pane);
        if (bar) DPScheduleReveal(pane, bar, pane.window == window && DPWantsReveal(pane, bar));
    }
}

static void DPConcealAll(void) {
    for (NSView *pane in DPPanes) {
        NSView *bar = DPPaneBar(pane);
        if (bar) DPSetRevealed(pane, bar, NO);
    }
}

#pragma mark - Liquid Glass

// Variant 17 is the system sidebar's glass; the default reads too clear at this size. The window has to stop being opaque for it to pick up what's behind.
static void DPApplyGlass(NSView *frame) {
    NSWindow *window = frame.window;
    NSView *content = window.contentView, *background = nil, *tint = nil;
    for (NSView *sub in content.subviews) {
        NSString *name = NSStringFromClass(sub.class);
        if ([name containsString:@"WindowFrameBackgroundView"]) background = sub;
        if ([name containsString:@"WindowBackgroundOverlayTintView"]) tint = sub;
    }
    Class glassClass = NSClassFromString(@"NSGlassEffectView");
    if (!background || !glassClass) return;
    BOOL on = DPOn[DPLiquidGlassBackground];
    NSView *glass = objc_getAssociatedObject(window, &DPGlassKey);
    if (!on && !glass) return;
    if (on && !glass) {
        glass = [[glassClass alloc] initWithFrame:content.bounds];
        glass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [glass setValue:@17 forKey:@"_variant"];
        [content addSubview:glass positioned:NSWindowBelow relativeTo:background];
        objc_setAssociatedObject(window, &DPGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(window, &DPWindowColorKey, window.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!on) {
        [glass removeFromSuperview];
        objc_setAssociatedObject(window, &DPGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    background.hidden = tint.hidden = on;
    for (NSView *sub in frame.subviews) if ([sub isKindOfClass:NSVisualEffectView.class]) sub.hidden = on;
    if (window.opaque == on) {
        window.opaque = !on;
        window.backgroundColor = on ? NSColor.clearColor : objc_getAssociatedObject(window, &DPWindowColorKey);
    }
}

static void DPRelayout(void);

static void DPApplyCorners(NSWindow *window) {
    SEL getter = NSSelectorFromString(@"_cornerRadius"), setter = NSSelectorFromString(@"_setCornerRadius:");
    if (![window respondsToSelector:getter] || ![window respondsToSelector:setter]) return;
    CGFloat radius = ((CGFloat (*)(id, SEL))objc_msgSend)(window, getter);
    NSNumber *original = objc_getAssociatedObject(window, &DPCornerRadiusKey);
    CGFloat target = radius;
    if (DPOn[DPLargerWindowCorners]) {
        if (!original) objc_setAssociatedObject(window, &DPCornerRadiusKey, @(radius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        target = DPLargerCornerRadius;
    } else if (original) {
        objc_setAssociatedObject(window, &DPCornerRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        target = original.doubleValue;
    }
    if (radius == target) return;
    ((void (*)(id, SEL, CGFloat))objc_msgSend)(window, setter, target);
    ((void (*)(id, SEL))objc_msgSend)(window, NSSelectorFromString(@"_updateWindowCornerMask"));
    [window invalidateShadow];
    dispatch_async(dispatch_get_main_queue(), ^{ DPRelayout(); });
}

static void DPWindowFrame_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(void (*)(id, SEL), self, _cmd);
    [DPBars addObject:self];
    DPApplyGlass(self);
    DPApplyCorners(self.window);
}

#pragma mark - Animation

static void DPRelayout(void) {
    for (NSView *container in DPContainers) {
        NSValue *requested = objc_getAssociatedObject(container, &DPRequestedFrameKey);
        if (requested) container.frame = requested.rectValue;
        container.needsLayout = container.needsDisplay = YES;
        DPRestyleContainer(container);
    }
    for (NSView *pane in DPPanes) {
        pane.needsLayout = YES;
        [pane layoutSubtreeIfNeeded];
    }
}

static void DPAnimate(void) {
    static NSTimer *timer;
    static CFTimeInterval start;
    static CGFloat from[DPAnimatedCount];
    start = CACurrentMediaTime();
    for (int i = 0; i < DPAnimatedCount; i++) from[i] = DPProgress[i];
    if (timer) return;
    timer = [NSTimer timerWithTimeInterval:1.0 / 120 repeats:YES block:^(NSTimer *t) {
        CGFloat elapsed = CACurrentMediaTime() - start, omega = 22;
        BOOL done = elapsed >= DPAnimationDuration * 2;
        CGFloat eased = done ? 1 : 1 - (1 + omega * elapsed) * exp(-omega * elapsed);
        for (int i = 0; i < DPAnimatedCount; i++) DPProgress[i] = from[i] + (DPOn[i] - from[i]) * eased;
        DPRelayout();
        if (done) {
            [t invalidate];
            timer = nil;
        }
    }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
}

static void DPSetTweak(DPTweak tweak, BOOL on) {
    if (DPOn[tweak] == on) return;
    DPOn[tweak] = on;
    [DPDefaults setBool:on forKey:DPKeys[tweak]];
    if (tweak < DPAnimatedCount) DPAnimate();
    else if (tweak == DPRevealToolbarOnHover) {
        if (!on) DPConcealAll();
    } else {
        if (on) for (NSView *bar in DPBars.allObjects) DPEnforceButtons(bar);
        else DPRestoreButtons(tweak);
        DPRelayoutBars();
    }
}

#pragma mark - Updates

static NSString *DPStagedPath(void) {
    return [DPCLI().stringByDeletingLastPathComponent.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"staged/Dia.app"];
}

static void DPCheckForUpdates(void (^completion)(NSDictionary *status)) {
    DPRunCLI(@[@"update"], ^(NSString *_) {
        DPRunCLI(@[@"status", @"--json"], ^(NSString *output) {
            id status = output ? [NSJSONSerialization JSONObjectWithData:[output dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
            completion([status isKindOfClass:NSDictionary.class] ? status : nil);
        });
    });
}

@interface DPUpdateMenuTarget : NSObject
@end

@implementation DPUpdateMenuTarget
- (void)checkForUpdates:(id)sender {
    DPCheckForUpdates(^(NSDictionary *status) {
        NSAlert *alert = [NSAlert new];
        id staged = status[@"staged"];
        if ([staged isKindOfClass:NSString.class]) {
            alert.messageText = [NSString stringWithFormat:@"Dia %@ is ready", staged];
            alert.informativeText = @"It will be installed with your patches when you quit Dia.";
            [alert addButtonWithTitle:@"Relaunch Now"];
            [alert addButtonWithTitle:@"Later"];
            if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@"apply");
        } else {
            alert.messageText = status ? @"Dia is up to date" : @"Couldn’t check for updates";
            [alert runModal];
        }
    });
}
@end

static void DPInstallUpdateMenuItem(void) {
    static DPUpdateMenuTarget *target;
    target = target ?: [DPUpdateMenuTarget new];
    for (NSMenuItem *item in NSApp.mainMenu.itemArray.firstObject.submenu.itemArray) {
        if (![item.title hasPrefix:@"Check for Updates"]) continue;
        item.target = target;
        item.action = @selector(checkForUpdates:);
    }
}

static void DPApplyStagedOnQuit(void) {
    if (![NSFileManager.defaultManager fileExistsAtPath:DPStagedPath()]) return;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:DPCLI()];
    task.arguments = @[@"apply", @"--wait", @(getpid()).stringValue];
    [task launchAndReturnError:nil];
}

#pragma mark - Settings pane

@interface DPSolidLabel : NSTextField
@end
@implementation DPSolidLabel
- (BOOL)allowsVibrancy { return NO; }
@end

@interface DPSolidImageView : NSImageView
@end
@implementation DPSolidImageView
- (BOOL)allowsVibrancy { return NO; }
@end

static NSView *DPGroup(NSArray<NSView *> *rows) {
    NSStackView *stack = [NSStackView new];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 0;
    [rows enumerateObjectsUsingBlock:^(NSView *row, NSUInteger i, BOOL *_) {
        if (i > 0) {
            NSBox *line = [NSBox new];
            line.boxType = NSBoxSeparator;
            [stack addArrangedSubview:line];
            [line.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24].active = YES;
        }
        [stack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }];
    NSBox *box = [NSBox new];
    box.boxType = NSBoxCustom;
    box.borderWidth = 0;
    box.cornerRadius = 10;
    box.fillColor = [NSColor.labelColor colorWithAlphaComponent:0.04];
    box.contentViewMargins = NSZeroSize;
    box.contentView = stack;
    return box;
}

static NSView *DPRow(NSView *leading, NSView *trailing) {
    NSView *row = [NSView new];
    for (NSView *v in @[leading, trailing]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:v];
    }
    [trailing setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        [leading.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
        [leading.topAnchor constraintEqualToAnchor:row.topAnchor constant:10],
        [leading.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-10],
        [trailing.leadingAnchor constraintGreaterThanOrEqualToAnchor:leading.trailingAnchor constant:12],
        [trailing.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [trailing.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    return row;
}

static NSTextField *DPLabel(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    return label;
}

static NSView *DPIconTile(NSString *symbol, NSColor *color) {
    NSView *tile = [NSView new];
    tile.wantsLayer = YES;
    tile.layer.backgroundColor = color.CGColor;
    tile.layer.cornerRadius = 5;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    NSImageView *glyph = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]];
    glyph.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightSemibold];
    glyph.contentTintColor = NSColor.whiteColor;
    glyph.translatesAutoresizingMaskIntoConstraints = NO;
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    [tile addSubview:glyph];
    [NSLayoutConstraint activateConstraints:@[
        [tile.widthAnchor constraintEqualToConstant:20],
        [tile.heightAnchor constraintEqualToConstant:20],
        [glyph.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [glyph.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
    ]];
    return tile;
}

@interface DPFlippedDocument : NSView
@end
@implementation DPFlippedDocument
- (BOOL)isFlipped { return YES; }
@end

static const CGFloat DPPaneTitleHeight = 52;

@interface DPPaneView : NSView
@property (nonatomic, strong) NSArray<NSSwitch *> *toggles;
@property (nonatomic, strong) NSArray<NSString *> *searchTexts;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSTextField *noResults;
@property (nonatomic, strong) NSView *tweakGroup;
@property (nonatomic, strong) NSArray<NSView *> *hiddenWhenSearching, *tweakSection;
@property (nonatomic, strong) NSTextField *status;
@property (nonatomic, strong) NSButton *checkButton;
@property (nonatomic, strong) NSButton *relaunchButton;
@end

@implementation DPPaneView

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    static const struct { DPTweak tweak; __unsafe_unretained NSString *symbol, *title, *detail; } rows[] = {
        {DPEdgeToEdge, @"squareshape.squareshape.dotted", @"Edge-to-edge web content", @"Remove the padding between web pages and the window edge."},
        {DPSquareSidebarCorners, @"square", @"Square corners by the sidebar", @"Let web pages meet the sidebar with straight edges."},
        {DPHideToolbar, @"menubar.rectangle", @"Hide toolbar", @"Remove the bar with the address, navigation buttons and extensions. Experimental."},
        {DPRevealToolbarOnHover, @"cursorarrow.motionlines", @"Show toolbar on hover", @"Bring the toolbar back over the page while the pointer is at its top edge."},
        {DPHideSidebarButton, @"sidebar.left", @"Hide sidebar button", @"Hide the sidebar toggle at the top left of the toolbar."},
        {DPHideChatButton, @"bubble.fill", @"Hide Chat button", @"Hide the Chat button at the top right of the toolbar."},
        {DPHideChatsButton, @"doc.text", @"Hide Chats button", @"Hide the Chats button from the tab bar and sidebar."},
        {DPHideDownloadsButton, @"arrow.down.circle", @"Hide downloads button", @"Hide the downloads button from the tab bar and sidebar."},
        {DPHideRecentTabsButton, @"chevron.down", @"Hide recent tabs button", @"Hide the recent tabs button from the tab bar and sidebar."},
        {DPHidePinnedTabsBackground, @"rectangle.dashed", @"Hide pinned tabs background", @"Remove the background behind the pinned tabs in the tab bar."},
        {DPHideWindowControls, @"macwindow", @"Hide window controls", @"Hide the close, minimize, and maximize buttons."},
        {DPHidePinnedTabBorder, @"square.dashed", @"Hide pinned tab border", @"Remove the border around the selected pinned tab."},
        {DPLiquidGlassBackground, @"sparkles", @"Liquid Glass background", @"Use Liquid Glass behind the tab bar and sidebar instead of the theme color."},
        {DPLargerWindowCorners, @"app", @"Larger window corners", @"Round the corners of browser windows to 26 points."},
        {DPShowExtensionsButton, @"puzzlepiece.extension", @"Extensions button", @"Open the Extensions menu from a button beside your pinned extensions."},
    };
    NSArray<NSColor *> *tints = @[NSColor.systemBlueColor, NSColor.systemIndigoColor, NSColor.systemGrayColor, NSColor.systemGrayColor, NSColor.systemOrangeColor, NSColor.systemPurpleColor, NSColor.systemTealColor, NSColor.systemGreenColor, NSColor.systemPinkColor, NSColor.systemBrownColor, NSColor.systemRedColor, NSColor.systemYellowColor, NSColor.systemCyanColor, NSColor.systemMintColor, NSColor.systemGreenColor];
    NSMutableArray<NSView *> *tweakRows = [NSMutableArray new];
    NSMutableArray<NSSwitch *> *toggles = [NSMutableArray new];
    NSMutableArray<NSString *> *searchTexts = [NSMutableArray new];
    for (size_t i = 0; i < sizeof rows / sizeof *rows; i++) {
        if (rows[i].tweak == DPLiquidGlassBackground && !NSClassFromString(@"NSGlassEffectView")) continue;
        NSStackView *text = [NSStackView stackViewWithViews:@[
            DPLabel(rows[i].title, 13, NSFontWeightRegular, NSColor.labelColor),
            DPLabel(rows[i].detail, 11, NSFontWeightRegular, NSColor.secondaryLabelColor),
        ]];
        text.orientation = NSUserInterfaceLayoutOrientationVertical;
        text.alignment = NSLayoutAttributeLeading;
        text.spacing = 2;
        NSStackView *leading = [NSStackView stackViewWithViews:@[DPIconTile(rows[i].symbol, tints[i]), text]];
        leading.spacing = 10;
        leading.alignment = NSLayoutAttributeCenterY;
        NSSwitch *toggle = [NSSwitch new];
        toggle.controlSize = NSControlSizeSmall;
        toggle.state = DPOn[rows[i].tweak];
        toggle.tag = rows[i].tweak;
        toggle.target = self;
        toggle.action = @selector(toggle:);
        [toggles addObject:toggle];
        [tweakRows addObject:DPRow(leading, toggle)];
        [searchTexts addObject:[NSString stringWithFormat:@"%@ %@%@", rows[i].title, rows[i].detail, rows[i].tweak == DPHideWindowControls ? @" traffic lights" : @""]];
    }
    _toggles = toggles;
    _searchTexts = searchTexts;
    _searchField = [NSSearchField new];
    _searchField.target = self;
    _searchField.action = @selector(search:);
    _noResults = DPLabel(@"No Results", 13, NSFontWeightRegular, NSColor.secondaryLabelColor);
    _noResults.hidden = YES;
    NSTextField *interface = DPLabel(@"Interface", 12, NSFontWeightSemibold, NSColor.secondaryLabelColor);
    _tweakGroup = DPGroup(tweakRows);
    _tweakSection = @[interface, _tweakGroup];
    [self updateToggles];

    _status = DPLabel(@"", 12, NSFontWeightRegular, NSColor.secondaryLabelColor);
    _checkButton = [NSButton buttonWithTitle:@"Check for Updates" target:self action:@selector(checkForUpdates:)];
    _relaunchButton = [NSButton buttonWithTitle:@"Relaunch to Update" target:self action:@selector(relaunchToUpdate:)];
    _relaunchButton.bezelColor = NSColor.controlAccentColor;
    _relaunchButton.hidden = YES;
    NSStackView *buttons = [NSStackView stackViewWithViews:@[_relaunchButton, _checkButton]];
    NSButton *restore = [NSButton buttonWithTitle:@"Restore…" target:self action:@selector(restore:)];
    NSTextField *updates = DPLabel(@"Updates", 12, NSFontWeightSemibold, NSColor.secondaryLabelColor);
    NSView *updatesGroup = DPGroup(@[
        DPRow(_status, buttons),
        DPRow(DPLabel(@"Restore the original Dia without patches.", 13, NSFontWeightRegular, NSColor.labelColor), restore),
    ]);
    NSTextField *notice = DPLabel(@"DiaPatches is unofficial and not affiliated with The Browser Company.", 11, NSFontWeightRegular, NSColor.tertiaryLabelColor);
    _hiddenWhenSearching = @[updates, updatesGroup, notice];

    NSStackView *content = [NSStackView stackViewWithViews:@[_searchField, interface, _tweakGroup, _noResults, updates, updatesGroup, notice]];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.alignment = NSLayoutAttributeLeading;
    content.spacing = 8;
    for (NSView *v in content.arrangedSubviews) [v.widthAnchor constraintEqualToAnchor:content.widthAnchor].active = YES;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    // Dia's settings window has a fixed height, so the pane scrolls below the title.
    DPFlippedDocument *document = [DPFlippedDocument new];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:content];
    NSScrollView *scroll = [NSScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.automaticallyAdjustsContentInsets = NO;
    scroll.documentView = document;
    [self addSubview:scroll];
    NSLayoutConstraint *fill = [content.widthAnchor constraintEqualToAnchor:document.widthAnchor constant:-48];
    fill.priority = NSLayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.topAnchor constant:DPPaneTitleHeight],
        [scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [document.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [content.topAnchor constraintEqualToAnchor:document.topAnchor constant:72 - DPPaneTitleHeight],
        [content.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-20],
        [content.centerXAnchor constraintEqualToAnchor:document.centerXAnchor],
        [content.widthAnchor constraintLessThanOrEqualToConstant:560],
        fill,
    ]];
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer { self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor; }

// Unhandled events would reach Dia's pane underneath via the responder chain.
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseDragged:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event {}
- (void)rightMouseDown:(NSEvent *)event {}
- (void)rightMouseUp:(NSEvent *)event {}
- (void)otherMouseDown:(NSEvent *)event {}
- (void)otherMouseUp:(NSEvent *)event {}
- (void)scrollWheel:(NSEvent *)event {}
- (NSMenu *)menuForEvent:(NSEvent *)event { return nil; }

- (void)updateToggles {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.allowsImplicitAnimation = YES;
        for (NSSwitch *toggle in self.toggles) {
            if (toggle.tag == DPHideSidebarButton || toggle.tag == DPHideChatButton || toggle.tag == DPShowExtensionsButton)
                toggle.enabled = !DPOn[DPHideToolbar] || DPOn[DPRevealToolbarOnHover];
        }
        [self updateVisibleRows];
        [self layoutSubtreeIfNeeded];
    }];
}

- (void)updateVisibleRows {
    NSString *query = [self.searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSStringCompareOptions options = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    __block BOOL any = NO;
    [self.toggles enumerateObjectsUsingBlock:^(NSSwitch *toggle, NSUInteger i, BOOL *_) {
        NSView *row = toggle.superview;
        BOOL visible = (!query.length || [self.searchTexts[i] rangeOfString:query options:options].location != NSNotFound)
            && (toggle.tag != DPSquareSidebarCorners || DPOn[DPEdgeToEdge]) && (toggle.tag != DPRevealToolbarOnHover || DPOn[DPHideToolbar]);
        row.hidden = !visible;
        if (i > 0) {
            NSArray *siblings = row.superview.subviews;
            NSView *separator = siblings[[siblings indexOfObject:row] - 1];
            separator.hidden = !visible || !any;
        }
        any |= visible;
    }];
    for (NSView *view in self.tweakSection) view.hidden = !any;
    for (NSView *view in self.hiddenWhenSearching) view.hidden = query.length > 0;
    self.noResults.hidden = any;
}

- (void)search:(NSSearchField *)sender {
    [self updateVisibleRows];
}

- (void)toggle:(NSSwitch *)sender {
    DPSetTweak(sender.tag, sender.state == NSControlStateValueOn);
    [self updateToggles];
}

- (void)showStatus:(NSDictionary *)status {
    NSString *running = [NSString stringWithFormat:@"Dia %@ (%@)",
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]];
    id staged = status[@"staged"];
    BOOL ready = [staged isKindOfClass:NSString.class];
    self.status.stringValue = !status ? [running stringByAppendingString:@" · couldn’t check for updates"]
                            : ready   ? [NSString stringWithFormat:@"Dia %@ installs when you quit", staged]
                                      : [running stringByAppendingString:@" · up to date"];
    self.relaunchButton.hidden = !ready;
    self.checkButton.enabled = YES;
}

- (void)checkForUpdates:(NSButton *)sender {
    sender.enabled = NO;
    self.status.stringValue = @"Checking for updates…";
    __weak DPPaneView *weakSelf = self;
    DPCheckForUpdates(^(NSDictionary *status) { [weakSelf showStatus:status]; });
}

- (void)refresh {
    __weak DPPaneView *weakSelf = self;
    DPRunCLI(@[@"status", @"--json"], ^(NSString *output) {
        id status = output ? [NSJSONSerialization JSONObjectWithData:[output dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
        [weakSelf showStatus:[status isKindOfClass:NSDictionary.class] ? status : nil];
    });
}

- (void)relaunchToUpdate:(id)sender {
    DPHandOffAndQuit(@"apply");
}

- (void)restore:(id)sender {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Restore the original Dia?";
    alert.informativeText = @"Dia will relaunch without patches, and its own updater takes over again. Run the installer to patch it again later.";
    [alert addButtonWithTitle:@"Restore and Relaunch"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) DPHandOffAndQuit(@"uninstall");
    }];
}
@end

@interface DPSidebarRow : NSControl
@property (nonatomic) BOOL selected;
@property (nonatomic) BOOL hovered;
@property (nonatomic, strong) NSImageView *icon;
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic) NSRect iconFrame, labelFrame, pillFrame;
@property (nonatomic, strong) NSFont *labelFont;
@property (nonatomic) CGFloat pillRadius;
@end

@implementation DPSidebarRow {
    NSTrackingArea *_tracking;
    NSView *_hover;
    NSVisualEffectView *_selection;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _hover = [NSView new];
    _hover.wantsLayer = YES;
    _selection = [NSVisualEffectView new];
    _selection.material = NSVisualEffectMaterialSelection;
    _selection.state = NSVisualEffectStateFollowsWindowActiveState;
    _selection.wantsLayer = YES;
    _selection.hidden = YES;
    _icon = [DPSolidImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"wand.and.stars" accessibilityDescription:nil]];
    _label = [DPSolidLabel labelWithString:@"Patches"];
    for (NSView *v in @[_hover, _selection, _icon, _label]) [self addSubview:v];
    self.accessibilityRole = NSAccessibilityButtonRole;
    self.accessibilityLabel = @"Patches";
    return self;
}

- (BOOL)allowsVibrancy { return NO; }
- (BOOL)isFlipped { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification]) {
        [center removeObserver:self name:name object:nil];
        if (self.window) [center addObserver:self selector:@selector(redraw) name:name object:self.window];
    }
}

- (void)redraw { self.needsDisplay = YES; }

- (void)layout {
    [super layout];
    for (NSView *v in @[_hover, _selection]) {
        v.frame = self.pillFrame;
        v.layer.cornerRadius = self.pillRadius;
        v.layer.masksToBounds = YES;
    }
    self.icon.frame = self.iconFrame;
    [self.label sizeToFit];
    NSRect labelFrame = self.labelFrame;
    labelFrame.size.width = MAX(labelFrame.size.width, NSWidth(self.label.frame));
    self.label.frame = labelFrame;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)mouseEntered:(NSEvent *)event { self.hovered = YES; }
- (void)mouseExited:(NSEvent *)event { self.hovered = NO; }
- (void)setHovered:(BOOL)hovered { _hovered = hovered; [self redraw]; }
- (void)setSelected:(BOOL)selected { _selected = selected; [self redraw]; }

- (void)updateLayer {
    BOOL key = self.window.isKeyWindow, emphasized = self.selected && key;
    _selection.hidden = !self.selected;
    _selection.emphasized = emphasized;
    _hover.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:self.hovered && !self.selected ? 0.05 : 0].CGColor;
    self.label.textColor = emphasized ? NSColor.alternateSelectedControlTextColor : key || self.selected ? NSColor.labelColor : NSColor.secondaryLabelColor;
    NSFont *font = self.labelFont ?: self.label.font;
    NSFont *face = self.selected ? [NSFont systemFontOfSize:font.pointSize weight:NSFontWeightSemibold] : font;
    if (![self.label.font isEqual:face]) {
        self.label.font = face;
        self.needsLayout = YES;
    }
    self.icon.contentTintColor = emphasized ? NSColor.alternateSelectedControlTextColor : key ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor;
}
@end

static NSString *const DPSettingsControllerClass = @"_TtC11Preferences38SidebarPreferencesWindowViewController";

@interface DPSettings : NSObject
@property (nonatomic, weak) NSWindow *window;
@property (nonatomic, weak) NSView *sidebar, *detail;
@property (nonatomic, weak) NSTableView *table;
@property (nonatomic, weak) NSTextField *title;
@property (nonatomic) NSInteger deselectedIndex;
@property (nonatomic, copy) NSString *originalTitle;
@property (nonatomic, strong) DPSidebarRow *row;
@property (nonatomic, strong) DPPaneView *pane;
@property (nonatomic, strong) id monitor;
@end

@implementation DPSettings

+ (void)attachTo:(NSWindow *)window {
    static NSMapTable<NSWindow *, DPSettings *> *attached;
    attached = attached ?: [NSMapTable weakToStrongObjectsMapTable];
    DPSettings *settings = [attached objectForKey:window];
    if (settings) return [settings reposition];
    settings = [DPSettings new];
    if ([settings attachTo:window]) [attached setObject:settings forKey:window];
}

- (BOOL)attachTo:(NSWindow *)window {
    NSSplitViewController *split = (NSSplitViewController *)window.contentViewController;
    if (split.splitViewItems.count < 2) return NO;
    NSView *sidebar = split.splitViewItems.firstObject.viewController.view;
    NSTableView *table = (NSTableView *)DPFindView(sidebar, ^BOOL(NSView *v) { return [v isKindOfClass:NSTableView.class]; });
    if (table.numberOfRows == 0) return NO;

    self.window = window;
    self.sidebar = sidebar;
    self.detail = split.splitViewItems.lastObject.viewController.view;
    self.table = table;
    self.row = [DPSidebarRow new];
    [sidebar addSubview:self.row];
    [self reposition];
    for (NSView *v in @[table, sidebar]) {
        v.postsFrameChangedNotifications = YES;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reposition) name:NSViewFrameDidChangeNotification object:v];
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(diaSelectionChanged) name:NSTableViewSelectionDidChangeNotification object:table];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keepDiaRowDeselected) name:NSWindowDidBecomeKeyNotification object:window];

    // Dia's sidebar handles clicks above the table view, so the row's clicks are consumed before it selects a row.
    __weak DPSettings *weakSelf = self;
    NSEventMask mask = NSEventMaskLeftMouseDown | NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp;
    self.monitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent *(NSEvent *event) {
        DPSettings *me = weakSelf;
        if (!me || event.window != me.window) return event;
        NSView *hit = [me.window.contentView.superview hitTest:event.locationInWindow];
        if ([hit isDescendantOf:me.row]) {
            if (event.type == NSEventTypeLeftMouseDown) {
                [NSApp activate];
                [me.window makeKeyAndOrderFront:nil];
                [me showPane];
            }
            return nil;
        }
        if (!me.pane.superview || [hit isDescendantOf:me.pane]) return event;
        NSPoint inDetail = [me.detail convertPoint:event.locationInWindow fromView:nil];
        if (NSPointInRect(inDetail, me.detail.bounds)) return nil;
        BOOL onDiaRow = [me.table rowAtPoint:[me.table convertPoint:event.locationInWindow fromView:nil]] >= 0;
        if (event.type == NSEventTypeLeftMouseDown && onDiaRow) [me hidePane];
        return event;
    }];
    return YES;
}

- (void)dealloc {
    [NSEvent removeMonitor:_monitor];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)reposition {
    NSTableView *table = self.table;
    NSInteger count = table.numberOfRows;
    if (count < 2 || !self.sidebar) return;
    NSRect last = [self.sidebar convertRect:[table rectOfRow:count - 1] fromView:table];
    NSRect previous = [self.sidebar convertRect:[table rectOfRow:count - 2] fromView:table];
    self.row.frame = NSOffsetRect(last, 0, NSMinY(last) - NSMinY(previous));

    NSTableRowView *rowView = [table rowViewAtRow:count - 1 makeIfNecessary:NO];
    NSTableCellView *cell = [table viewAtColumn:0 row:count - 1 makeIfNecessary:NO];
    if (!rowView || !cell) return;
    NSRect (^inRow)(NSView *) = ^NSRect(NSView *v) {
        NSRect r = [rowView convertRect:v.bounds fromView:v];
        if (!rowView.isFlipped) r.origin.y = NSHeight(rowView.bounds) - NSMaxY(r);
        return r;
    };
    self.row.iconFrame = inRow(cell.imageView);
    self.row.labelFrame = inRow(cell.textField);
    NSInteger plain = table.selectedRow == count - 1 ? 0 : count - 1;
    self.row.labelFont = [[table viewAtColumn:0 row:plain makeIfNecessary:NO] textField].font ?: self.row.labelFont;
    self.row.icon.symbolConfiguration = cell.imageView.image.symbolConfiguration;

    NSTableRowView *selected = table.selectedRow >= 0 ? [table rowViewAtRow:table.selectedRow makeIfNecessary:NO] : nil;
    NSVisualEffectView *pill = (NSVisualEffectView *)DPFindView(selected, ^BOOL(NSView *v) { return [v isKindOfClass:NSVisualEffectView.class]; });
    if (selected && pill.superview == selected) {
        NSRect r = pill.frame;
        if (!selected.isFlipped) r.origin.y = NSHeight(selected.bounds) - NSMaxY(r);
        self.row.pillFrame = r;
        self.row.pillRadius = pill.maskImage.capInsets.top ?: pill.layer.cornerRadius;
    } else if (NSIsEmptyRect(self.row.pillFrame)) {
        self.row.pillFrame = NSInsetRect(rowView.bounds, 10, 0);
    }
    if (self.row.pillRadius <= 0) self.row.pillRadius = 6;
    self.row.needsLayout = YES;
}

- (void)showPane {
    if (self.pane.superview || !self.detail) return;
    self.pane = self.pane ?: [[DPPaneView alloc] initWithFrame:self.detail.bounds];
    self.pane.frame = self.detail.bounds;
    self.pane.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.detail addSubview:self.pane positioned:NSWindowAbove relativeTo:nil];
    [self.pane refresh];

    NSInteger selected = self.table.selectedRow;
    if (selected < 0) return;
    NSString *name = [[self.table viewAtColumn:0 row:selected makeIfNecessary:NO] textField].stringValue;
    NSView *content = self.window.contentView;
    self.title = (NSTextField *)DPFindView(content.superview, ^BOOL(NSView *v) {
        return [v isKindOfClass:NSTextField.class] && !v.hiddenOrHasHiddenAncestor && ![v isDescendantOf:content]
            && [((NSTextField *)v).stringValue isEqualToString:name];
    });
    self.originalTitle = self.title.stringValue;
    self.title.stringValue = @"Patches";
    self.deselectedIndex = selected;
    [self.table rowViewAtRow:selected makeIfNecessary:NO].selected = NO;
    self.row.selected = YES;
}

- (void)keepDiaRowDeselected {
    if (!self.pane.superview) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.pane.superview) return;
        [self.detail addSubview:self.pane positioned:NSWindowAbove relativeTo:nil];
        [self.table rowViewAtRow:self.deselectedIndex makeIfNecessary:NO].selected = NO;
        self.row.selected = YES;
    });
}

- (void)diaSelectionChanged {
    NSInteger selected = self.table.selectedRow;
    if (self.pane.superview && selected >= 0 && selected != self.deselectedIndex) [self hidePane];
    else [self keepDiaRowDeselected];
}

- (void)hidePane {
    [self.pane removeFromSuperview];
    if ([self.title.stringValue isEqualToString:@"Patches"]) self.title.stringValue = self.originalTitle;
    if (self.table.selectedRow == self.deselectedIndex) [self.table rowViewAtRow:self.deselectedIndex makeIfNecessary:NO].selected = YES;
    self.row.selected = NO;
}
@end

static void DPSettings_viewDidAppear(NSViewController *self, SEL _cmd) {
    DPCallOriginal(void (*)(id, SEL), self, _cmd);
    NSWindow *window = self.view.window;
    dispatch_async(dispatch_get_main_queue(), ^{ if (window) [DPSettings attachTo:window]; });
}

#pragma mark - Bootstrap

__attribute__((constructor)) static void DPInit(void) {
    DPDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    for (int i = 0; i < DPTweakCount; i++) {
        id value = [DPDefaults objectForKey:DPKeys[i]];
        DPOn[i] = value ? [value boolValue] : DPDefaultsOn[i];
    }
    for (int i = 0; i < DPAnimatedCount; i++) DPProgress[i] = DPOn[i];
    DPContainers = [NSHashTable weakObjectsHashTable];
    DPPanes = [NSHashTable weakObjectsHashTable];
    DPBars = [NSHashTable weakObjectsHashTable];
    DPSuppressed = [NSHashTable weakObjectsHashTable];

    DPHook(DPContainerClass(), @selector(setFrame:), (IMP)DPContainer_setFrame);
    for (NSString *selector in @[@"layout", @"updateLayer"])
        DPHook(DPContainerClass(), NSSelectorFromString(selector), (IMP)DPContainer_layoutOrUpdateLayer);
    DPHook(NSClassFromString(@"_TtC5ARCUI10ShadowView"), @selector(layout), (IMP)DPShadow_layout);
    DPHook(NSClassFromString(@"_TtC11ContentPane15ContentPaneView"), @selector(layout), (IMP)DPPane_layout);
    DPHook(DPToolbarClass(), @selector(layout), (IMP)DPBar_layout);
    DPHook(DPToolbarClass(), @selector(hitTest:), (IMP)DPToolbar_hitTest);
    DPHook(DPAddressBarClass(), @selector(setFrame:), (IMP)DPMakeRoom_setFrame);
    DPHook(DPTranslateButtonClass(), @selector(setFrame:), (IMP)DPMakeRoom_setFrame);
    DPHook(NSClassFromString(@"_TtC8TabStrip31TabStripContainerViewController"), @selector(viewWillLayout), (IMP)DPTabStrip_viewWillLayout);
    DPHook(DPPinnedTabsClass(), @selector(layout), (IMP)DPPinnedTabs_layout);
    DPHook(NSClassFromString(@"_TtC6Window24PlatformWindowThemeFrame"), @selector(layout), (IMP)DPWindowFrame_layout);
    DPHook(NSClassFromString(@"_TtC5TabUI15TabDockItemView"), @selector(layout), (IMP)DPPinnedTab_layout);
    DPHook(NSClassFromString(@"_TtC10TabSidebar30SidebarContainerViewController"), @selector(viewWillLayout), (IMP)DPSidebar_viewWillLayout);
    DPHook(DPSidebarFooterClass(), @selector(layout), (IMP)DPBar_layout);
    DPHook(NSClassFromString(@"_TtC10TabSidebar17SidebarHeaderView"), @selector(layout), (IMP)DPBar_layout);
    DPHook(NSClassFromString(DPSettingsControllerClass), @selector(viewDidAppear), (IMP)DPSettings_viewDidAppear);

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification *_) {
        DPInstallUpdateMenuItem();
        DPRunCLI(@[@"update"], nil);
    }];
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskMouseMoved | NSEventMaskKeyDown | NSEventMaskLeftMouseUp
                                          handler:^NSEvent *(NSEvent *event) {
        NSWindow *window = event.window ?: NSApp.keyWindow;
        dispatch_async(dispatch_get_main_queue(), ^{ DPUpdateReveal(window); });  // after the event moves focus
        return event;
    }];
    [center addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(NSNotification *_) {
        DPApplyStagedOnQuit();
    }];
}
