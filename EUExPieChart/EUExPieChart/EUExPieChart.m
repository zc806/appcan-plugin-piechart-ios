//
//  EUExPieChart.m
//  AppCan
//
//  Created by AppCan on 13-3-7.
//
//

#import "EUExPieChart.h"
#import "EUtility.h"
#import "JSON.h"
@interface BTSSliceData : NSObject
@property (nonatomic) int value;
@property (nonatomic, retain) UIColor *color;

+ (id)sliceDataWithValue:(int)value color:(UIColor *)color;
@end
@implementation EUExPieChart
@synthesize pieChartArray;
@synthesize _slices;
@synthesize dataArray;
-(id)initWithBrwView:(EBrowserView *)eInBrwView{
    if (self=[super initWithBrwView:eInBrwView]) {
    }
    return self;
}
-(void)open:(NSMutableArray *)array{
    // Do any additional setup after loading the view.
    if ([array count]>0) {
        NSString *x=[array objectAtIndex:1];
        NSString *y=[array objectAtIndex:2];
        NSString *width=[array objectAtIndex:3];
        NSString *height=[array objectAtIndex:4];
        NSString *stringId=[NSString stringWithFormat:@"%@", [array objectAtIndex:0]];
        
        UIView *containerView = [[UIView alloc] initWithFrame:CGRectMake([x floatValue], [y floatValue], [width floatValue], [height floatValue])];
        BTSPieView *pieView = [[BTSPieView alloc] init];
        [pieView setFrame:CGRectMake(0, 0, [width floatValue], [height floatValue])];
        [pieView setAnimationDuration:0.5];//动画持续时间
        [pieView setDelegate:self];
        [pieView setDataSource:self];
        [pieView setBackgroundColor:[UIColor grayColor]];
//另一种方法,没有数字
//        PieChartView* pieView = [[PieChartView alloc] initWithFrame:CGRectMake([x floatValue], [y floatValue], [width floatValue],[height floatValue])];
//        [container addSubview:pieView];
//        pieView.mValueArray = [NSMutableArray arrayWithArray:valueArray];
//        pieView.mColorArray = [NSMutableArray arrayWithArray:colorArray];
//        pieView.mInfoTextView = [[UITextView alloc] initWithFrame:CGRectMake(20, 350, 300, 80)];
//        pieView.mInfoTextView.backgroundColor = [UIColor clearColor];
//        pieView.mInfoTextView.editable = NO;
//        pieView.mInfoTextView.userInteractionEnabled = NO;
        [pieView setBackgroundColor:[UIColor clearColor]];
        pieView.stringId = stringId;
        if (!self.pieChartArray) {
            self.pieChartArray = [NSMutableArray arrayWithCapacity:1];
        }
        if (!self._slices) {
            self._slices = [NSMutableArray arrayWithCapacity:1];
        }
        if (pieView) {
            if (![self.pieChartArray containsObject:pieView]) {
                [self.pieChartArray addObject:pieView];
            }
        }
        //背景
        NSString *str = [[NSBundle mainBundle] pathForResource:@"uexPieChart/bingtu-mask" ofType:@"png"];
        NSData *imageData = [NSData dataWithContentsOfFile:str];
        UIImage *image = [UIImage imageWithData:imageData];
        int centerX = [width floatValue] / 2.0-28;
        int centerY = [height floatValue] / 2.0-28;
        float diameter  = (centerX < centerY ? centerX : centerY)*2;
        float scale = 0.0;
        if (diameter>491.0) {//491是内圆直径
            scale = 491.0/diameter;
        }else if (diameter<=491.0){
            scale = diameter/491.0;
        }
        CGSize size = CGSizeMake(image.size.width*scale,image.size.height*scale);
        UIGraphicsBeginImageContext(size);
        CGRect thumbnailRect = CGRectMake(0, 0, size.width, size.height);
        [image drawInRect:thumbnailRect];
        UIImage *fwImage = UIGraphicsGetImageFromCurrentImageContext();
        float x_ = ([width floatValue] - size.width)/2;
        float y_ = ([height floatValue] - size.width)/2;
        UIImageView *bgImageView = [[UIImageView alloc] initWithFrame:CGRectMake(x_, y_, size.width, size.height)];
        [bgImageView setImage:fwImage];
        [containerView addSubview:bgImageView];
        CGPoint point = CGPointMake(pieView.center.x, pieView.center.y+1);
        bgImageView.center = point;
        [containerView addSubview:pieView];
        [containerView bringSubviewToFront:bgImageView];
        [containerView setBackgroundColor:[UIColor clearColor]];
        [EUtility brwView:meBrwView addSubview:containerView];
        [bgImageView release];
        [pieView release];
        [containerView release];
        NSString *jsstr = [NSString stringWithFormat:@"if(uexPieChart.loadData!=null){uexPieChart.loadData('%@')}",stringId];
        NSString *jsstrCB = [NSString stringWithFormat:@"if(uexPieChart.cbOpen!=null){uexPieChart.cbOpen('%@')}",stringId];
        [EUtility brwView:meBrwView evaluateScript:jsstr];
        [EUtility brwView:meBrwView evaluateScript:jsstrCB];
    }else{
        
    }
}
//16进制颜色(html颜色值)字符串转为UIColor
-(UIColor *)hexStringToColor:(NSString *)stringToConvert
{
    NSString *cString = [[stringToConvert stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    // String should be 6 or 8 characters
    
    if ([cString length] < 6) return [UIColor blackColor];
    // strip 0X if it appears
    if ([cString hasPrefix:@"0X"]) cString = [cString substringFromIndex:2];
    if ([cString hasPrefix:@"#"]) cString = [cString substringFromIndex:1];
    if ([cString length] != 6) return [UIColor blackColor];
    // Separate into r, g, b substrings
    NSRange range;
    range.location = 0;
    range.length = 2;
    NSString *rString = [cString substringWithRange:range];
    range.location = 2;
    NSString *gString = [cString substringWithRange:range];
    range.location = 4;
    NSString *bString = [cString substringWithRange:range];
    // Scan values
    unsigned int r, g, b;
    [[NSScanner scannerWithString:rString] scanHexInt:&r];
    [[NSScanner scannerWithString:gString] scanHexInt:&g];
    [[NSScanner scannerWithString:bString] scanHexInt:&b];
    return [UIColor colorWithRed:((float) r / 255.0f)
                           green:((float) g / 255.0f)
                            blue:((float) b / 255.0f)
                           alpha:1.0f];
}
-(void)setJsonData:(NSMutableArray *)array{
    if ([array count]==0) {
        return;
    }
    NSString *string = [array objectAtIndex:0];
    NSDictionary *jsonDict = [string JSONValue];
    if (!jsonDict) {
        return;
    }

    NSString *strId = [NSString stringWithFormat:@"%@",[jsonDict objectForKey:@"id"]];
    BTSPieView *pieChart = nil;
    if (self.pieChartArray) {
        for (BTSPieView *pieChart_ in self.pieChartArray) {
            if (pieChart_!=nil&&[pieChart_ isKindOfClass:[BTSPieView class]]) {
                if ([strId isEqualToString:pieChart_.stringId]) {
                    pieChart = pieChart_;
                }
            }
        }
    }
    if (pieChart&&[pieChart.stringId isEqualToString:strId]) {
        NSMutableArray *dataArray_ = [NSMutableArray arrayWithArray:[jsonDict objectForKey:@"data"]];
        if (!self.dataArray) {
            self.dataArray = [NSMutableArray arrayWithArray:dataArray_];
        }
        if ([self.dataArray count]>0) {
            [self.dataArray removeAllObjects];
        }
        [self.dataArray setArray:dataArray_];
        if ([self._slices count]>0) {
            [self._slices removeAllObjects];//否则添加第二个旋转饼状图崩溃
        }
        for (int i=0; i<[dataArray_ count]&&self._slices; i++)
        {
            NSDictionary *item = [dataArray_ objectAtIndex:i];
            BTSSliceData *sliceData = [BTSSliceData sliceDataWithValue:[[item objectForKey:@"value"] integerValue] color:[self hexStringToColor:[item objectForKey:@"color"]]];
            if (![self._slices containsObject:sliceData]) {
                [self._slices addObject:sliceData];
            }
            [pieChart insertSliceAtIndex:i animate:YES];
        }
        [pieChart reloadData];
    }else{
        NSString *jsstr = [NSString stringWithFormat:@"setJsonData  pieChart:%@  init  faild!",strId];
        [super jsSuccessWithName:@"uexWidgetOne.cbError" opId:0 dataType:0 strData:jsstr];
    }
}
-(void)close:(NSMutableArray *)array{
    if ([array count]>0) {
        NSString *IdStr = [array objectAtIndex:0];
        NSArray *IdArray = [IdStr componentsSeparatedByString:@","];
        if (self.pieChartArray) {
            NSMutableArray *tempArray = [[NSMutableArray alloc] initWithCapacity:1];
            for (NSString *stringId in IdArray) {
                for (UIView *subView in self.pieChartArray) {
                    BTSPieView *subViewPieChart = (BTSPieView *)subView;
                    if (subView!=nil&&[subView isKindOfClass:[BTSPieView class]]&&[subViewPieChart.stringId isEqualToString:stringId]) {
                        [tempArray addObject:subViewPieChart];
                        if (subViewPieChart.superview) {
                            [subViewPieChart.superview removeFromSuperview];
                        }
                    }
                }
            }
            for (BTSPieView *btsPieView in tempArray) {
                [self.pieChartArray removeObject:btsPieView];
            }
            [tempArray release];
        }
    }else{
        //全部移除
        if (self.pieChartArray) {
                for (UIView *subView in self.pieChartArray) {
                    BTSPieView *subViewPieChart = (BTSPieView *)subView;
                    if (subView!=nil&&[subView isKindOfClass:[BTSPieView class]]) {
                        if (subViewPieChart.superview) {
                            [subViewPieChart.superview removeFromSuperview];
                        }
                    }
                }
        [self.pieChartArray removeAllObjects];
        self.pieChartArray = nil;
    }
    }
    if(self._slices){
        self._slices = nil;
    }
    if(self.dataArray){
        self.dataArray = nil;
    }
}
-(void)clean{
    if (self.pieChartArray) {
        self.pieChartArray = nil;
    }
    if (self._slices) {
        self._slices = nil;
    }
    if (self.dataArray) {
        self.dataArray = nil;
    }
    [super clean];
}
-(void)dealloc{
    if (self.pieChartArray) {
        self.pieChartArray = nil;
    }
    if (self._slices) {
        self._slices = nil;
    }
    if (self.dataArray) {
        self.dataArray = nil;
    }
    [super dealloc];
}
#pragma mark - BTSPieView Data Source

- (NSUInteger)numberOfSlicesInPieView:(BTSPieView *)pieView
{
    return [_slices count];
}

- (CGFloat)pieView:(BTSPieView *)pieView valueForSliceAtIndex:(NSUInteger)index
{
    return [(BTSSliceData *)[_slices objectAtIndex:index] value];
}

- (UIColor *)pieView:(BTSPieView *)pieView colorForSliceAtIndex:(NSUInteger)index sliceCount:(NSUInteger)sliceCount
{
    return [(BTSSliceData *)[_slices objectAtIndex:index] color];
}

#pragma mark - BTSPieView Delegate

- (void)pieView:(BTSPieView *)pieView willSelectSliceAtIndex:(NSInteger)index
{
}

- (void)pieView:(BTSPieView *)pieView didSelectSliceAtIndex:(NSInteger)index
{
    // save the index the user selected.
//    _selectedSliceIndex = index;
    
    // update the selected slice UI components with the model values
    //    BTSSliceData *sliceData = [_slices objectAtIndex:(NSUInteger)_selectedSliceIndex];
    //    [_selectedSliceValueLabel setText:[NSString stringWithFormat:@"%d", [sliceData value]]];
    //    [_selectedSliceValueLabel setAlpha:1.0];
    //
    //    [_selectedSliceValueSlider setValue:[sliceData value]];
    //    [_selectedSliceValueSlider setEnabled:YES];
    //    [_selectedSliceValueSlider setMinimumTrackTintColor:[sliceData color]];
    //    [_selectedSliceValueSlider setMaximumTrackTintColor:[sliceData color]];
}

- (void)pieView:(BTSPieView *)pieView willDeselectSliceAtIndex:(NSInteger)index
{
}

- (void)pieView:(BTSPieView *)pieView didDeselectSliceAtIndex:(NSInteger)index
{
    //    [_selectedSliceValueSlider setMinimumTrackTintColor:nil];
    //    [_selectedSliceValueSlider setMaximumTrackTintColor:nil];
    //
    //    // nothing is selected... so turn off the "selected value" controls
    //    _selectedSliceIndex = -1;
    //    [_selectedSliceValueSlider setEnabled:NO];
    //    [_selectedSliceValueSlider setValue:0.0];
    //    [_selectedSliceValueLabel setAlpha:0.0];
    
    //    [self updateSelectedSliceValue:_selectedSliceValueSlider];
}
-(void)moveDelegateAtIndex:(NSInteger)index idString:(NSString *)idStr{
    if (self.dataArray) {
        NSString *string = [self.dataArray objectAtIndex:index];
        NSString *jsonStr = [string JSONRepresentation];
        NSString *jsstr = [NSString stringWithFormat:@"if(uexPieChart.callBackData!=null){uexPieChart.callBackData('%@','%@','%@')}",idStr,@"1",jsonStr];
        NSString *jsstrOn = [NSString stringWithFormat:@"if(uexPieChart.onData!=null){uexPieChart.onData('%@','%@','%@')}",idStr,@"1",jsonStr];
        [EUtility brwView:meBrwView evaluateScript:jsstrOn];
        [EUtility brwView:meBrwView evaluateScript:jsstr];
    }else{
        
    }
}
-(void)moveEndDelegateAtIndex:(NSInteger)index idString:(NSString *)idStr{
    if (self.dataArray) {
        NSString *string = [self.dataArray objectAtIndex:index];
        NSString *jsonStr = [string JSONRepresentation];
        NSString *jsstr = [NSString stringWithFormat:@"if(uexPieChart.pieChartStop!=null){uexPieChart.pieChartStop('%@','%@','%@')}",idStr,@"1",jsonStr];
        NSString *jsstrOn = [NSString stringWithFormat:@"if(uexPieChart.onTouchUp!=null){uexPieChart.onTouchUp('%@','%@','%@')}",idStr,@"1",jsonStr];
        [EUtility brwView:meBrwView evaluateScript:jsstrOn];
        [EUtility brwView:meBrwView evaluateScript:jsstr];
    }else{
        
    }
}
@end
@implementation BTSSliceData

@synthesize value = _value;
@synthesize color = _color;

+ (id)sliceDataWithValue:(int)value color:(UIColor *)color
{
    BTSSliceData *data = [[[BTSSliceData alloc] init] autorelease];
    [data setValue:value];
    [data setColor:color];
    return data;
}

@end