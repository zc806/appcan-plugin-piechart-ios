//
//  BTSPieView.m
//
//  Copyright (c) 2011 Brian Coyner. All rights reserved.
//

#import "BTSPieView.h"
#import <QuartzCore/QuartzCore.h>

#import "BTSPieViewValues.h"
#import "BTSPieLayer.h"
#import "BTSSliceLayer.h"
#import "EUtility.h"
#define K_EPSINON        (1e-127)
#define IS_ZERO_FLOAT(X) (X < K_EPSINON && X > -K_EPSINON)

#define K_FRICTION              20.0f   // 摩擦系数
#define K_MAX_SPEED             0.0f
#define K_POINTER_ANGLE         (M_PI / 2)
#define degreesToRadians(x) (M_PI * (x) / 180.0)

static float const kBTSPieViewSelectionOffset = 20.0f;

// Used as a CAAnimationDelegate when animating existing slices
@interface BTSSliceLayerExistingLayerDelegate : NSObject
@property(nonatomic, assign) id animationDelegate;
@end

@interface BTSSliceLayerAddAtBeginningLayerDelegate : NSObject
@property(nonatomic, assign) id animationDelegate;
@end

@interface BTSSliceLayerAddInMiddleLayerDelegate : NSObject
@property(nonatomic, assign) id animationDelegate;
@property(nonatomic) CGFloat initialSliceAngle;
@end

@interface BTSPieView () {

    NSInteger _selectedSliceIndex;

    CADisplayLink *_displayLink;

    NSMutableArray *_animations;
    NSMutableArray *_layersToRemove;
    NSMutableArray *_deletionStack;

    BTSSliceLayerExistingLayerDelegate *_existingLayerDelegate;
    BTSSliceLayerAddAtBeginningLayerDelegate *_addAtBeginningLayerDelegate;
    BTSSliceLayerAddInMiddleLayerDelegate *_addInMiddleLayerDelegate;

    NSNumberFormatter *_labelFormatter;

    CGPoint _center;
    CGFloat _radius;
}
//旋转
- (void)tapStopped;

// C-helper functions
CGPathRef CGPathCreateArc(CGPoint center, CGFloat radius, CGFloat startAngle, CGFloat endAngle);

CGPathRef CGPathCreateArcLineForAngle(CGPoint center, CGFloat radius, CGFloat angle);

void BTSUpdateLabelPosition(CALayer *labelLayer, CGPoint center, CGFloat radius, CGFloat startAngle, CGFloat endAngle);

void BTSUpdateAllLayers(BTSPieLayer *pieLayer, NSUInteger layerIndex, CGPoint center, CGFloat radius, CGFloat startAngle, CGFloat endAngle);

void BTSUpdateLayers(NSArray *sliceLayers, NSArray *labelLayers, NSArray *lineLayers, NSUInteger layerIndex, CGPoint center, CGFloat radius, CGFloat startAngle, CGFloat endAngle);

CGFloat BTSLookupPreviousLayerAngle(NSArray *pieLayers, NSUInteger currentPieLayerIndex, CGFloat defaultAngle);

@end

@implementation BTSPieView

@synthesize dataSource = _dataSource;
@synthesize delegate = _delegate;
@synthesize animationDuration = _animationDuration;
@synthesize highlightSelection = _highlightSelection;
@synthesize stringId;
@synthesize mZeroAngle;
@synthesize mThetaArray;
#pragma mark - Custom Layer Initialization

+ (Class)layerClass
{
    return [BTSPieLayer class];
}

#pragma mark - View Initialization

- (void)initView
{
    _animationDuration = 0.2f;
    _highlightSelection = YES;

    if (!_labelFormatter) {
        _labelFormatter = [[NSNumberFormatter alloc] init];
        [_labelFormatter setNumberStyle:NSNumberFormatterPercentStyle];
    }
    _selectedSliceIndex = -1;
    if (!_animations) {
        _animations = [[NSMutableArray alloc] init];
    }
    if (!_layersToRemove) {
        _layersToRemove = [[NSMutableArray alloc] init];
    }
    if (!_deletionStack) {
        _deletionStack = [[NSMutableArray alloc] init];
    }
    if (!_existingLayerDelegate) {
        _existingLayerDelegate = [[BTSSliceLayerExistingLayerDelegate alloc] init];
        [_existingLayerDelegate setAnimationDelegate:self];
    }
    if (!_addAtBeginningLayerDelegate) {
        _addAtBeginningLayerDelegate = [[BTSSliceLayerAddAtBeginningLayerDelegate alloc] init];
        [_addAtBeginningLayerDelegate setAnimationDelegate:self];
    }
    if (!_addInMiddleLayerDelegate) {
        _addInMiddleLayerDelegate = [[BTSSliceLayerAddInMiddleLayerDelegate alloc] init];
        [_addInMiddleLayerDelegate setAnimationDelegate:self];
    }
    if (!self.mThetaArray) {
        self.mThetaArray = [NSMutableArray arrayWithCapacity:2];
    }

}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self initView];
    }

    return self;
}
-(id)initWithFrame:(CGRect)frame{
    if (self = [super initWithFrame:frame]) {
        [self initView];
    }
    return self;
}
- (id)init
{
    self = [super init];
    if (self) {
        [self initView];
    }
    return self;
}

#pragma mark - View Clean Up

- (void)dealloc
{
    if (self.stringId) {
        self.stringId = nil;
    }
    if (self.mThetaArray) {
        self.mThetaArray = nil;
    }
    [super dealloc];
}

#pragma mark - Layout Hack 

- (void)layoutSubviews
{
    // Calculate the center and radius based on the parent layer's bounds. This version
    // of the BTSPieChart assumes the view does not change size.
    CGRect parentLayerBounds = [[self layer] bounds];
    CGFloat centerX = parentLayerBounds.size.width / 2.0f;
    CGFloat centerY = parentLayerBounds.size.height / 2.0f;
    _center = CGPointMake(centerX, centerY);

    // Reduce the radius just a bit so the the pie chart layers do not hug the edge of the view.
    _radius = MIN(centerX-28, centerY-28);//默认的
    [self refreshLayers];
}

- (void)beginCATransaction
{
    [CATransaction begin];
    [CATransaction setAnimationDuration:_animationDuration];
}

#pragma mark - Reload Pie View (No Animation)

- (BTSSliceLayer *)insertSliceLayerAtIndex:(NSUInteger)index color:(UIColor *)color
{
    BTSSliceLayer *sliceLayer = [BTSSliceLayer layerWithColor:color.CGColor];

    BTSPieLayer *pieLayer = (BTSPieLayer *) [self layer];
    [[pieLayer sliceLayers] insertSublayer:sliceLayer atIndex:index];
    return sliceLayer;
}
- (CATextLayer *)insertLabelLayerAtIndex:(NSUInteger)index value:(double)value
{
    CATextLayer *labelLayer = [BTSPieView createLabelLayer];
    [labelLayer setString:[_labelFormatter stringFromNumber:[NSNumber numberWithDouble:value]]];
    if (value<0.05) {
        [labelLayer setHidden:YES];
    }
    BTSPieLayer *pieLayer = (BTSPieLayer *) [self layer];
    CALayer *layer = [pieLayer labelLayers];
    [layer insertSublayer:labelLayer atIndex:index];
    return labelLayer;
}

- (CAShapeLayer *)insertLineLayerAtIndex:(NSUInteger)index color:(UIColor *)color
{
    CAShapeLayer *lineLayer = [CAShapeLayer layer];
    [lineLayer setStrokeColor:color.CGColor];

    BTSPieLayer *pieLayer = (BTSPieLayer *) [self layer];
    [[pieLayer lineLayers] insertSublayer:lineLayer atIndex:index];

    return lineLayer;
}

- (void)reloadData
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    BTSPieLayer *parentLayer = (BTSPieLayer *) [self layer];
    [parentLayer removeAllPieLayers];
    
    if (_dataSource) {
        NSUInteger sliceCount = [_dataSource numberOfSlicesInPieView:self];

        BTSPieViewValues values(sliceCount, ^(NSUInteger index) {
            return [_dataSource pieView:self valueForSliceAtIndex:index];
        });

        CGFloat startAngle = (CGFloat)M_PI_2;//
        CGFloat endAngle = startAngle;

        for (NSUInteger sliceIndex = 0; sliceIndex < sliceCount; sliceIndex++) {

            endAngle += values.angles()[sliceIndex];

            UIColor *color = [_delegate pieView:self colorForSliceAtIndex:sliceIndex sliceCount:sliceCount];
            [self insertSliceLayerAtIndex:sliceIndex color:color];
            [self insertLabelLayerAtIndex:sliceIndex value:values.percentages()[sliceIndex]];
            [self insertLineLayerAtIndex:sliceIndex color:color];            
            BTSUpdateAllLayers(parentLayer, sliceIndex, _center, _radius, startAngle, endAngle);
            if (![self.mThetaArray containsObject:[NSNumber numberWithFloat:endAngle]]) {
                [self.mThetaArray addObject:[NSNumber numberWithFloat:endAngle]];
            }
            startAngle = endAngle;
        }
        CGFloat startAngle_0 = (CGFloat)M_PI_2;//
        CGFloat endAngle_1 = startAngle;
        if (sliceCount>0) {
            endAngle_1 = [[self.mThetaArray objectAtIndex:0] floatValue];
            self.transform = CGAffineTransformMakeRotation(-(endAngle_1-startAngle_0)/2);
        }
    }
    [CATransaction setDisableActions:NO];
    [CATransaction commit];
}

#pragma mark - Insert Slice

- (void)insertSliceAtIndex:(NSUInteger)indexToInsert animate:(BOOL)animate
{
    if (!animate) {
        [self reloadData];
        return;
    }

    if (_dataSource) {

        [self beginCATransaction];

        NSUInteger sliceCount = [_dataSource numberOfSlicesInPieView:self];
        BTSPieViewValues values(sliceCount, ^(NSUInteger sliceIndex) {
            return [_dataSource pieView:self valueForSliceAtIndex:sliceIndex];
        });

        CGFloat startAngle = (CGFloat)M_PI_2;
        CGFloat endAngle = startAngle;
//        int atIndex=0;
        for (NSUInteger currentIndex = 0; currentIndex < sliceCount; currentIndex++) {
            // Make no implicit transactions are creating (e.g. when adding the new slice we don't want a "fade in" effect)
            [CATransaction setDisableActions:YES];
            endAngle += values.angles()[currentIndex];
//            if (M_PI_2-0>startAngle && M_PI_2-0<endAngle) {
//                atIndex = currentIndex;
//                if (_delegate) {
//                    [_delegate moveDelegateAtIndex:atIndex  idString:self.stringId];
//                }
//            }
            BTSSliceLayer *sliceLayer;
            if (indexToInsert == currentIndex) {
                sliceLayer = [self insertSliceAtIndex:currentIndex values:&values startAngle:startAngle endAngle:endAngle];
            } else {
                sliceLayer = [self updateSliceAtIndex:currentIndex values:&values];
            }

            [CATransaction setDisableActions:NO];

            // Remember because "sliceAngle" is a dynamic property this ends up calling the actionForLayer:forKey: method on each layer with a non-nil delegate
            [sliceLayer setSliceAngle:endAngle];
            [sliceLayer setDelegate:nil];
            startAngle = endAngle;
        }
        [CATransaction commit];
    }
}

- (BTSSliceLayer *)insertSliceAtIndex:(NSUInteger)index values:(BTSPieViewValues*)values startAngle:(CGFloat)startAngle endAngle:(CGFloat)endAngle
{
    NSUInteger sliceCount = values->count();
    UIColor *color = [_delegate pieView:self colorForSliceAtIndex:index sliceCount:sliceCount];
    
    BTSSliceLayer *sliceLayer = [self insertSliceLayerAtIndex:index color:color];
    id delegate = [self delegateForSliceAtIndex:index sliceCount:sliceCount];
    [sliceLayer setDelegate:delegate];
    
    CGFloat initialLabelAngle = [self initialLabelAngleForSliceAtIndex:index sliceCount:sliceCount startAngle:startAngle endAngle:endAngle];
    CATextLayer *labelLayer = [self insertLabelLayerAtIndex:index value:values->percentages()[index]];
    BTSUpdateLabelPosition(labelLayer, _center, _radius, initialLabelAngle, initialLabelAngle);

    // Special Case...
    // If the delegate is the "add in middle", then the "initial label angle" is also the delegate's starting angle.
    if (delegate == _addInMiddleLayerDelegate) {
        [_addInMiddleLayerDelegate setInitialSliceAngle:initialLabelAngle];
    }

    [self insertLineLayerAtIndex:index color:color];

    return sliceLayer;
}

- (BTSSliceLayer *)updateSliceAtIndex:(NSUInteger)currentIndex values:(BTSPieViewValues*)values
{
    BTSPieLayer *pieLayer = (BTSPieLayer *)[self layer];
    
    NSArray *sliceLayers = [[pieLayer sliceLayers] sublayers];
    BTSSliceLayer *sliceLayer = (BTSSliceLayer *) [sliceLayers objectAtIndex:currentIndex];
    [sliceLayer setDelegate:_existingLayerDelegate];
    
    NSArray *labelLayers = [[pieLayer labelLayers] sublayers];
    CATextLayer *labelLayer = [labelLayers objectAtIndex:currentIndex];
    double value = values->percentages()[currentIndex];
    NSString *label = [_labelFormatter stringFromNumber:[NSNumber numberWithDouble:value]];
    [labelLayer setString:label];
    return sliceLayer;
}

- (id)delegateForSliceAtIndex:(NSUInteger)currentIndex sliceCount:(NSUInteger)sliceCount
{
    // The inserted layer animates differently depending on where the new layer is inserted.
    id delegate;
    if (currentIndex == 0) {
        delegate = _addAtBeginningLayerDelegate;
    } else if (currentIndex + 1 == sliceCount) {
        delegate = nil;
    } else {
        delegate = _addInMiddleLayerDelegate;
    }
    return delegate;
}

- (CGFloat)initialLabelAngleForSliceAtIndex:(NSUInteger)currentIndex sliceCount:(NSUInteger)sliceCount startAngle:(CGFloat)startAngle endAngle:(CGFloat)endAngle
{
    // The inserted layer animates differently depending on where the new layer is inserted.
    CGFloat initialLabelAngle;
    
    if (currentIndex == 0) {
        initialLabelAngle = startAngle;
    } else if (currentIndex + 1 == sliceCount) {
        initialLabelAngle = endAngle;
    } else {
        BTSPieLayer *pieLayer = (BTSPieLayer *) [self layer];
        NSArray *pieLayers = [[pieLayer sliceLayers] sublayers];        
        initialLabelAngle = BTSLookupPreviousLayerAngle(pieLayers, currentIndex, (CGFloat)-M_PI_2);
    }
    return initialLabelAngle;
}

#pragma mark - Remove Slice

- (void)removeSliceAtIndex:(NSUInteger)indexToRemove animate:(BOOL)animate
{
    if (!animate) {
        [self reloadData];
        return;
    }

    if (_delegate) {

        BTSPieLayer *parentLayer = (BTSPieLayer *) [self layer];
        NSArray *sliceLayers = [[parentLayer sliceLayers] sublayers];
        NSArray *labelLayers = [[parentLayer labelLayers] sublayers];
        NSArray *lineLayers = [[parentLayer lineLayers] sublayers];

        CAShapeLayer *sliceLayerToRemove = [sliceLayers objectAtIndex:indexToRemove];
        CATextLayer *labelLayerToRemove = [labelLayers objectAtIndex:indexToRemove];
        CALayer *lineLayerToRemove = [lineLayers objectAtIndex:indexToRemove];

        [_layersToRemove addObjectsFromArray:[NSArray arrayWithObjects:lineLayerToRemove, sliceLayerToRemove, labelLayerToRemove, nil]];

        [self beginCATransaction];

        NSUInteger current = [_layersToRemove count];
        [CATransaction setCompletionBlock:^{
            if (current == [_layersToRemove count]) {
                [_layersToRemove enumerateObjectsUsingBlock:^(id obj, NSUInteger index, BOOL *stop) {
                    [obj removeFromSuperlayer];
                }];
                [_layersToRemove removeAllObjects];
            }
        }];

        NSUInteger sliceCount = [_dataSource numberOfSlicesInPieView:self];

        if (sliceCount > 0) {

            [CATransaction setDisableActions:YES];
            [labelLayerToRemove setHidden:YES];
            [CATransaction setDisableActions:NO];

            BTSPieViewValues values(sliceCount, ^(NSUInteger index) {
                return [_dataSource pieView:self valueForSliceAtIndex:index];
            });

            CGFloat startAngle = (CGFloat) -M_PI_2;
            CGFloat endAngle = startAngle;
            for (NSUInteger sliceIndex = 0; sliceIndex < [sliceLayers count]; sliceIndex++) {

                BTSSliceLayer *sliceLayer = (BTSSliceLayer *) [sliceLayers objectAtIndex:sliceIndex];
                [sliceLayer setDelegate:_existingLayerDelegate];

                NSUInteger modelIndex = sliceIndex <= indexToRemove ? sliceIndex : sliceIndex - 1;

                CGFloat currentEndAngle;
                if (sliceIndex == indexToRemove) {
                    currentEndAngle = endAngle;
                } else {
                    double value = values.percentages()[modelIndex];
                    NSString *label = [_labelFormatter stringFromNumber:[NSNumber numberWithDouble:value]];
                    CATextLayer *labelLayer = [labelLayers objectAtIndex:sliceIndex];
                    [labelLayer setString:label];

                    endAngle += values.angles()[modelIndex];
                    currentEndAngle = endAngle;
                    
                }

                [sliceLayer setSliceAngle:currentEndAngle];
            }
        }

        [CATransaction commit];

        [self maybeNotifyDelegateOfSelectionChangeFrom:_selectedSliceIndex to:-1];
    }
}

#pragma mark - Reload Slice Value

- (void)reloadSliceAtIndex:(NSUInteger)index animate:(BOOL)animate
{
    if (!animate) {
        [self reloadData];
        return;
    }

    if (_dataSource) {

        [self beginCATransaction];

        BTSPieLayer *parentLayer = (BTSPieLayer *) [self layer];
        NSArray *sliceLayers = [[parentLayer sliceLayers] sublayers];
        NSArray *labelLayers = [[parentLayer labelLayers] sublayers];

        NSUInteger sliceCount = [_dataSource numberOfSlicesInPieView:self];

        BTSPieViewValues values(sliceCount, ^(NSUInteger sliceIndex) {
            return [_dataSource pieView:self valueForSliceAtIndex:sliceIndex];
        });

        // For simplicity, the start angle is always zero... no reason it can't be any valid angle in radians.
        CGFloat endAngle = (CGFloat) -M_PI_2;

        // We are updating existing layer values (viz. not adding, or removing). We simply iterate each slice layer and 
        // adjust the start and end angles.
        for (NSUInteger sliceIndex = 0; sliceIndex < sliceCount; sliceIndex++) {

            BTSSliceLayer *sliceLayer = (BTSSliceLayer *) [sliceLayers objectAtIndex:sliceIndex];
            [sliceLayer setDelegate:_existingLayerDelegate];

            endAngle += values.angles()[sliceIndex];
            [sliceLayer setSliceAngle:endAngle];

            CATextLayer *labelLayer = (CATextLayer *) [labelLayers objectAtIndex:sliceIndex];
            double value = values.percentages()[sliceIndex];
            NSNumber *valueAsNumber = [NSNumber numberWithDouble:value];
            NSString *label = [_labelFormatter stringFromNumber:valueAsNumber];
            [labelLayer setString:label];
        }
        [CATransaction commit];
    }
}

- (void)refreshLayers
{
    BTSPieLayer *pieLayer = (BTSPieLayer *) [self layer];
    NSArray *sliceLayers = [[pieLayer sliceLayers] sublayers];
    NSArray *labelLayers = [[pieLayer labelLayers] sublayers];
    NSArray *lineLayers = [[pieLayer lineLayers] sublayers];

    [sliceLayers enumerateObjectsUsingBlock:^(id obj, NSUInteger index, BOOL *stop) {
        CGFloat startAngle = BTSLookupPreviousLayerAngle(sliceLayers, index, (CGFloat) -M_PI_2);
        CGFloat endAngle = (CGFloat) [[obj valueForKey:kBTSSliceLayerAngle] doubleValue];
        BTSUpdateLayers(sliceLayers, labelLayers, lineLayers, index, _center, _radius, startAngle, endAngle);
    }];
}

#pragma mark - Animation Delegate + CADisplayLink Callback

- (void)updateTimerFired:(CADisplayLink *)displayLink
{
    BTSPieLayer *parentLayer = (BTSPieLayer *) [self layer];
    NSArray *pieLayers = [[parentLayer sliceLayers] sublayers];
    NSArray *labelLayers = [[parentLayer labelLayers] sublayers];
    NSArray *lineLayers = [[parentLayer lineLayers] sublayers];

    CGPoint center = _center;
    CGFloat radius = _radius;

    [CATransaction setDisableActions:YES];

    NSUInteger index = 0;
    for (BTSSliceLayer *currentPieLayer in pieLayers) {
        CGFloat interpolatedStartAngle = BTSLookupPreviousLayerAngle(pieLayers, index, (CGFloat) -M_PI_2);
        BTSSliceLayer *presentationLayer = (BTSSliceLayer *) [currentPieLayer presentationLayer];
        CGFloat interpolatedEndAngle = [presentationLayer sliceAngle];

        BTSUpdateLayers(pieLayers, labelLayers, lineLayers, index, center, radius, interpolatedStartAngle, interpolatedEndAngle);
        ++index;
    }
    [CATransaction setDisableActions:NO];
}

- (void)animationDidStart:(CAAnimation *)anim
{
    [_animations addObject:anim];
}

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)animationCompleted
{
    [_animations removeObject:anim];
}
-(void)function{
    //旋转Label
    BTSPieLayer *pieLayer = (BTSPieLayer *) [self layer];
    NSArray *labelLayers = [[pieLayer labelLayers] sublayers];
    for (CALayer *subLayer in labelLayers) {
        if (subLayer!=nil&&[subLayer isKindOfClass:[CATextLayer class]]) {
            CGAffineTransform rotation = CGAffineTransformMakeRotation(deltaAngle-M_PI_2);
            [subLayer setAffineTransform:rotation];
        }
    }
    //计算返回的数值
    if (self.mThetaArray){
        for (int i=0; i<[self.mThetaArray count]; i++) {
            float startAngle,endAngle;
            if (i==0) {
                startAngle=M_PI_2 -M_PI_2;
            }else{
                startAngle=[[self.mThetaArray objectAtIndex:i-1] floatValue] - M_PI_2;
            }
            
            if (i==[self.mThetaArray count]-1) {
                endAngle=M_PI*2;
            }else{
                endAngle=[[self.mThetaArray objectAtIndex:i] floatValue] - M_PI_2;
            }
            
            if (deltaAngle>M_PI_2 && deltaAngle<=M_PI) {
                if (deltaAngle-M_PI_2>startAngle && deltaAngle-M_PI_2<endAngle) {
                    atIndex=i;
                    if (_delegate) {
                        [_delegate moveDelegateAtIndex:atIndex  idString:self.stringId];
                    }
                    break;
                }
            }else{
                if ((M_PI+deltaAngle+M_PI_2)>startAngle && (M_PI+deltaAngle+M_PI_2)<endAngle) {
                    atIndex=i;
                    if (_delegate) {
                        [_delegate moveDelegateAtIndex:atIndex  idString:self.stringId];
                    }
                    break;
                }
            }
        }
    }
}
#pragma mark - Touch Handing (Selection Notification)

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch   = [touches anyObject];
    mAbsoluteTheta   = [self thetaForTouch:touch onView:self.superview];
    mRelativeTheta   = [self thetaForTouch:touch onView:self];
    mDragBeforeTheta = 0.0f;
}
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    
    // 取得当前触点的theta值
    mAbsoluteTheta = [self thetaForTouch:touch onView:self.superview];
//     NSString *mInfo = [NSString stringWithFormat:
//      @"relative theta   = %.2f\nabsolute theta   = %.2f\nrotation theta   = %.2f\nspeed = %f",
//      mRelativeTheta, mAbsoluteTheta, [self rotationThetaForNewTheta:mAbsoluteTheta], mDragSpeed];
//    NSLog(@"mInfo:----->%@",mInfo);
    self.transform = CGAffineTransformMakeRotation([self rotationThetaForNewTheta:mAbsoluteTheta]);
    deltaAngle=atan2f(self.transform.a, self.transform.b);
//    NSLog(@"deltaAngle:----->%f",deltaAngle);
    
    mDragBeforeTheta = mAbsoluteTheta;
    [self performSelectorOnMainThread:@selector(function) withObject:nil waitUntilDone:YES];
}
-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event{
    deltaAngle=atan2f(self.transform.a, self.transform.b);
//    if (self.mThetaArray) {
//        float startAngle,endAngle;
//        if (atIndex==0) {
//            startAngle=M_PI_2-M_PI_2;
//        }else{
//            startAngle=[[self.mThetaArray objectAtIndex:atIndex-1] floatValue]-M_PI_2;
//        }
//        
//        if (atIndex==[self.mThetaArray count]-1) {
//            endAngle=M_PI*2;
//        }else{
//            endAngle=[[self.mThetaArray objectAtIndex:atIndex] floatValue]-M_PI_2;
//        }
//        NSLog(@"(deltaAngle -M_PI_2):--->%f",(deltaAngle -M_PI_2));
//        NSLog(@"(endAngle -startAngle)/2:--->%f",(endAngle -startAngle)/2);
//        [UIView animateWithDuration:0.2f animations:^{
//        self.transform = CGAffineTransformMakeRotation((deltaAngle-M_PI_2)-startAngle-(endAngle -startAngle)/2);
//        }];
//    }
    if (_delegate) {
        [_delegate moveEndDelegateAtIndex:atIndex  idString:self.stringId];
    }
}

#pragma mark - Selection Notification

- (void)maybeNotifyDelegateOfSelectionChangeFrom:(NSInteger)previousSelection to:(NSInteger)newSelection
{
    if (previousSelection != newSelection) {

        if (previousSelection != -1) {
            [_delegate pieView:self willDeselectSliceAtIndex:previousSelection];
        }

        _selectedSliceIndex = newSelection;

        if (newSelection != -1) {
            [_delegate pieView:self willSelectSliceAtIndex:newSelection];

            if (previousSelection != -1) {
                [_delegate pieView:self didDeselectSliceAtIndex:previousSelection];
            }

            [_delegate pieView:self didSelectSliceAtIndex:newSelection];
        } else {
            if (previousSelection != -1) {
                [_delegate pieView:self didDeselectSliceAtIndex:previousSelection];
            }
        }
    }
}

#pragma mark - Pie Layer Creation Method

+ (CATextLayer *)createLabelLayer
{
    CATextLayer *textLayer = [CATextLayer layer];
    [textLayer setContentsScale:[[UIScreen mainScreen] scale]];
    CGFontRef font = CGFontCreateWithFontName(( CFStringRef) [[UIFont boldSystemFontOfSize:17.0] fontName]);
    [textLayer setFont:font];
    CFRelease(font);
    [textLayer setFontSize:17.0];
    [textLayer setAnchorPoint:CGPointMake(0.5, 0.5)];
    [textLayer setZPosition:100.0];
    [textLayer setAlignmentMode:kCAAlignmentCenter];
    [textLayer setBackgroundColor:[UIColor clearColor].CGColor];
    CGSize size = [@"100.00%" sizeWithFont:[UIFont boldSystemFontOfSize:17.0]];
    [textLayer setBounds:CGRectMake(0.0, 0.0, size.width, size.height)];
    return textLayer;
}

#pragma mark - Function Helpers

// Helper method to create an arc path for a layer
CGPathRef CGPathCreateArc(CGPoint center, CGFloat radius, CGFloat startAngle, CGFloat endAngle) {
    CGMutablePathRef path = CGPathCreateMutable();

    CGPathMoveToPoint(path, NULL, center.x, center.y);
    CGPathAddArc(path, NULL, center.x, center.y, radius, startAngle, endAngle, 0);
    CGPathCloseSubpath(path);
    return path;
}

CGPathRef CGPathCreateArcLineForAngle(CGPoint center, CGFloat radius, CGFloat angle) {
    CGMutablePathRef linePath = CGPathCreateMutable();
    CGPathMoveToPoint(linePath, NULL, center.x, center.y);
    CGPathAddLineToPoint(linePath, NULL, (CGFloat) (center.x + (radius) * cos(angle)), (CGFloat) (center.y + (radius) * sin(angle)));
    return linePath;
}

void BTSUpdateLabelPosition(CALayer *labelLayer, CGPoint center, CGFloat radius, CGFloat startAngle, CGFloat endAngle) {
    CGFloat midAngle = (startAngle + endAngle) / 2.0f;
    CGFloat halfRadius = radius / 2.0f;
    [labelLayer setPosition:CGPointMake((CGFloat) (center.x + (halfRadius * cos(midAngle))), (CGFloat) (center.y + (halfRadius * sin(midAngle))))];
}

void BTSUpdateLayers(NSArray *sliceLayers, NSArray *labelLayers, NSArray *lineLayers, NSUInteger layerIndex, CGPoint center, CGFloat radius, CGFloat startAngle, CGFloat endAngle) {
    {
        CAShapeLayer *lineLayer = [lineLayers objectAtIndex:layerIndex];

        CGPathRef linePath = CGPathCreateArcLineForAngle(center, radius, endAngle);
        [lineLayer setPath:linePath];
        CFRelease(linePath);
    }

    {
        CAShapeLayer *sliceLayer = [sliceLayers objectAtIndex:layerIndex];
        CGPathRef path = CGPathCreateArc(center, radius, startAngle, endAngle);
        [sliceLayer setPath:path];
        CFRelease(path);
    }

    {
        CALayer *labelLayer = [labelLayers objectAtIndex:layerIndex];
        BTSUpdateLabelPosition(labelLayer, center, radius, startAngle, endAngle);
    }
}

void BTSUpdateAllLayers(BTSPieLayer *pieLayer, NSUInteger layerIndex, CGPoint center, CGFloat radius, CGFloat startAngle, CGFloat endAngle) {
    BTSUpdateLayers([[pieLayer sliceLayers] sublayers], [[pieLayer labelLayers] sublayers], [[pieLayer lineLayers] sublayers], layerIndex, center, radius, startAngle, endAngle);
}

CGFloat BTSLookupPreviousLayerAngle(NSArray *pieLayers, NSUInteger currentPieLayerIndex, CGFloat defaultAngle) {
    BTSSliceLayer *sliceLayer;
    if (currentPieLayerIndex == 0) {
        sliceLayer = nil;
    } else {
        sliceLayer = [pieLayers objectAtIndex:currentPieLayerIndex - 1];
    }
    return (sliceLayer == nil) ? defaultAngle : [[sliceLayer presentationLayer] sliceAngle];
}
#pragma mark -
#pragma mark handle rotation angle
- (float)thetaForX:(float)x andY:(float)y {
    if (IS_ZERO_FLOAT(y)) {
        if (x < 0) {
            return M_PI;
        } else {
            return 0;
        }
    }
    
    float theta = atan(y / x);
    if (x < 0 && y > 0) {
        theta = M_PI + theta;
    } else if (x < 0 && y < 0) {
        theta = M_PI + theta;
    } else if (x > 0 && y < 0) {
        theta = 2 * M_PI + theta;
    }
    return theta;
}

/* 计算将当前以相对角度为单位的触摸点旋转到绝对角度为newTheta的位置所需要旋转到的角度(*_*!真尼玛拗口) */
- (float)rotationThetaForNewTheta:(float)newTheta {
    float rotationTheta;
    if (mRelativeTheta > (3 * M_PI / 2) && (newTheta < M_PI / 2)) {
        rotationTheta = newTheta + (2 * M_PI - mRelativeTheta);
    } else {
        rotationTheta = newTheta - mRelativeTheta;
    }
    return rotationTheta;
}
- (float)thetaForTouch:(UITouch *)touch onView:view {
    CGPoint location = [touch locationInView:view];
    float xOffset    = self.bounds.size.width / 2;
    float yOffset    = self.bounds.size.height / 2;
    float centeredX  = location.x - xOffset;
    float centeredY  = location.y - yOffset;
    
    return [self thetaForX:centeredX andY:centeredY];
}

#pragma mark -
#pragma mark Private & handle rotation

- (void)animationDidStop:(NSString*)str finished:(NSNumber*)flag context:(void*)context {
}

- (void)tapStopped {
    int tapAreaIndex;
    
    for (tapAreaIndex = 0; tapAreaIndex < [mThetaArray count]; tapAreaIndex++) {
        if (mRelativeTheta < [[mThetaArray objectAtIndex:tapAreaIndex] floatValue]) {
            break;
        }
    }
    
    if (tapAreaIndex == 0) {
        mRelativeTheta = [[mThetaArray objectAtIndex:0] floatValue] / 2;
    } else {
        mRelativeTheta = [[mThetaArray objectAtIndex:tapAreaIndex] floatValue]
        - (([[mThetaArray objectAtIndex:tapAreaIndex] floatValue]
            - [[mThetaArray objectAtIndex:tapAreaIndex - 1] floatValue]) / 2);
    }
    
    [UIView beginAnimations:@"tap stopped" context:nil];
    [UIView setAnimationDuration:1];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDidStopSelector:@selector(animationDidStop:finished:context:)];
    self.transform = CGAffineTransformMakeRotation([self rotationThetaForNewTheta:K_POINTER_ANGLE]);
    [UIView commitAnimations];
    
    return;
}
@end

#pragma mark - Existing Layer Animation Delegate

@implementation BTSSliceLayerExistingLayerDelegate

@synthesize animationDelegate = _animationDelegate;

- (id <CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event
{
    if ([kBTSSliceLayerAngle isEqual:event]) {

        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:event];
        NSNumber *currentAngle = [[layer presentationLayer] valueForKey:event];
        [animation setFromValue:currentAngle];
        [animation setDelegate:_animationDelegate];
        [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault]];

        return animation;
    } else {
        return nil;
    }
}

@end

#pragma mark - New Layer Animation Delegate

@implementation BTSSliceLayerAddAtBeginningLayerDelegate

@synthesize animationDelegate = _animationDelegate;

- (id <CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event
{
    if ([kBTSSliceLayerAngle isEqualToString:event]) {
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:kBTSSliceLayerAngle];

        [animation setFromValue:[NSNumber numberWithDouble:-M_PI_2]];
        [animation setDelegate:_animationDelegate];
        [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault]];

        return animation;
    } else {
        return nil;
    }
}

@end

#pragma mark - Add Layer In Middle Animation Delegate

@implementation BTSSliceLayerAddInMiddleLayerDelegate

@synthesize animationDelegate = _animationDelegate;
@synthesize initialSliceAngle = _initialSliceAngle;

- (id <CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event
{
    if ([kBTSSliceLayerAngle isEqualToString:event]) {
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:kBTSSliceLayerAngle];

        [animation setFromValue:[NSNumber numberWithDouble:_initialSliceAngle]];
        [animation setDelegate:_animationDelegate];
        [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault]];

        return animation;
    } else {
        return nil;
    }
}
@end

