#import <Availability.h>
#import <Flutter/Flutter.h>
#import <TargetConditionals.h>
#import <UIKit/UIKit.h>

@interface AsterDuoGeometryStream : NSObject <FlutterStreamHandler>
@property(nonatomic, copy, nullable) FlutterEventSink sink;
@property(nonatomic, copy, nullable) NSDictionary<NSString *, NSNumber *> *geometry;
@end

@implementation AsterDuoGeometryStream

- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
  self.sink = events;
  events(self.geometry);
  return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
  self.sink = nil;
  return nil;
}

- (void)setGeometry:(NSDictionary<NSString *, NSNumber *> *)geometry {
  if (_geometry == geometry || [_geometry isEqualToDictionary:geometry]) {
    return;
  }
  _geometry = [geometry copy];
  if (self.sink) {
    self.sink(_geometry);
  }
}

@end

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100 && !TARGET_OS_MACCATALYST

// UIKit reruns updateConstraints when a reserved region queried there changes.
// Keep this observer in the Flutter view's coordinate space and out of input.
API_AVAILABLE(ios(27.1))
@interface AsterDuoGeometryView : UIView
@property(nonatomic, weak) AsterDuoGeometryStream *stream;
@end

@implementation AsterDuoGeometryView {
  UIHingeStatus _hingeStatus;
}

- (instancetype)initWithStream:(AsterDuoGeometryStream *)stream {
  self = [super initWithFrame:CGRectZero];
  if (self) {
    self.stream = stream;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    __weak AsterDuoGeometryView *weakSelf = self;
    UIHingeInteraction *hinge = [[UIHingeInteraction alloc]
        initWithUpdateHandler:^(__unused UIHingeInteraction *interaction,
                                UIHingeInteractionUpdate *update) {
          AsterDuoGeometryView *view = weakSelf;
          UIHingeStatus status = update.hinge.status;
          if (view && view->_hingeStatus != status) {
            view->_hingeStatus = status;
            [view setNeedsUpdateConstraints];
            [view reportGeometry];
          }
        }];
    [self addInteraction:hinge];
    [self registerForTraitChanges:UITraitCollection.systemTraitsAffectingVerticalBarEdge
                      withHandler:^(id<UITraitEnvironment> environment,
                                    __unused UITraitCollection *previousTraits) {
      AsterDuoGeometryView *view = (AsterDuoGeometryView *)environment;
      [view setNeedsUpdateConstraints];
      [view reportGeometry];
    }];
  }
  return self;
}

- (void)didMoveToWindow {
  [super didMoveToWindow];
  [self setNeedsUpdateConstraints];
  [self reportGeometry];
}

- (void)safeAreaInsetsDidChange {
  [super safeAreaInsetsDidChange];
  [self reportGeometry];
}

- (void)layoutSubviews {
  [super layoutSubviews];
  [self reportGeometry];
}

- (void)updateConstraints {
  [self reportGeometry];
  [super updateConstraints];
}

- (void)reportGeometry {
  UIWindowScene *scene = self.window.windowScene;
  CGRect viewport = self.bounds;
  if (_hingeStatus == UIHingeStatusUnknown || !scene || CGRectIsEmpty(viewport)) {
    self.stream.geometry = nil;
    return;
  }

  BOOL isInner = _hingeStatus == UIHingeStatusFullyOpen || _hingeStatus == UIHingeStatusPartiallyOpen;
  if (!isInner && _hingeStatus != UIHingeStatusClosed) {
    self.stream.geometry = nil;
    return;
  }

  // Report the display even when system controls leave no room for tabs.
  NSMutableDictionary<NSString *, NSNumber *> *geometry = [@{
    @"width": @(CGRectGetWidth(viewport)),
    @"height": @(CGRectGetHeight(viewport)),
  } mutableCopy];
  if (isInner) {
    geometry[@"inner"] = @YES;
    if (CGRectGetWidth(viewport) <= CGRectGetHeight(viewport)) {
      self.stream.geometry = geometry;
      return;
    }
  }

  UIVerticalBarEdge edge = self.traitCollection.verticalBarEdge;
  if (!isInner && edge == UIVerticalBarEdgeUnspecified) {
    self.stream.geometry = geometry;
    return;
  }

  UIEdgeInsets insets = self.safeAreaInsets;
  BOOL rightToLeft = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
  BOOL onRight = edge == UIVerticalBarEdgeUnspecified
      ? insets.right >= insets.left
      : (edge == UIVerticalBarEdgeTrailing) != rightToLeft;
  CGFloat width = onRight ? insets.right : insets.left;
  CGFloat left = onRight ? CGRectGetMaxX(viewport) - width : CGRectGetMinX(viewport);
  CGFloat top = CGRectGetMinY(viewport) + insets.top;
  CGFloat bottom = CGRectGetMaxY(viewport) - insets.bottom;
  if (width <= 0 || top >= bottom) {
    self.stream.geometry = geometry;
    return;
  }
  CGRect strip = CGRectMake(left, top, width, bottom - top);

  // The bar belongs below the system UI. Reserved-region frames already
  // include their interaction margins.
  for (UIViewReservedRegion *region in [self reservedRegionsOfKind:UIViewReservedRegionKind.occlusionRegionKind]) {
    if (CGRectIntersectsRect(strip, region.frame)) {
      top = MAX(top, CGRectGetMaxY(region.frame));
    }
  }
  CGRect statusFrame = scene.statusBarManager.statusBarFrame;
  if (!CGRectIsEmpty(statusFrame)) {
    CGRect localStatus = [scene.effectiveGeometry.coordinateSpace convertRect:statusFrame
                                                              toCoordinateSpace:self];
    if (CGRectIntersectsRect(strip, localStatus)) {
      top = MAX(top, CGRectGetMaxY(localStatus));
    }
  }

  if (top < bottom) {
    geometry[@"left"] = @(left - CGRectGetMinX(viewport));
    geometry[@"top"] = @(top - CGRectGetMinY(viewport));
    geometry[@"right"] = @(left + width - CGRectGetMinX(viewport));
    geometry[@"bottom"] = @(bottom - CGRectGetMinY(viewport));
  }
  self.stream.geometry = geometry;
}

@end

#endif

@interface AsterViewController : FlutterViewController
@end

@implementation AsterViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  AsterDuoGeometryStream *stream = [[AsterDuoGeometryStream alloc] init];
  FlutterEventChannel *channel = [FlutterEventChannel
      eventChannelWithName:@"com.aster.wallet/cover_navigation"
           binaryMessenger:self.binaryMessenger];
  [channel setStreamHandler:stream];

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100 && !TARGET_OS_MACCATALYST
  if (@available(iOS 27.1, *)) {
    UIView *observer = [[AsterDuoGeometryView alloc] initWithStream:stream];
    observer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:observer];
    [NSLayoutConstraint activateConstraints:@[
      [observer.leftAnchor constraintEqualToAnchor:self.view.leftAnchor],
      [observer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
      [observer.rightAnchor constraintEqualToAnchor:self.view.rightAnchor],
      [observer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
  }
#endif
}

@end
