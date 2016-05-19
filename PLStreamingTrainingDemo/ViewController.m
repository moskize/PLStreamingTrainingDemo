//
//  ViewController.m
//  PLStreamingTrainingDemo
//
//  Created by TaoZeyu on 16/5/19.
//  Copyright © 2016年 taozeyu. All rights reserved.
//

#import "ViewController.h"
#import <PLStreamingKit/PLStreamingKit.h>
#import <GPUImage/GPUImage.h>

#define kStreamCloudURL @"http://pili-demo.qiniu.com/api/stream"

@interface ViewController () <PLStreamingSessionDelegate>
@property (nonatomic, strong) PLStreamingSession *session;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSDictionary *streamJSON = [self _createStreamObjectFromServer];
    NSLog(@"Stream Json %@", streamJSON);
    
    PLVideoStreamingConfiguration *videoConfiguration = [PLVideoStreamingConfiguration configurationWithVideoSize:CGSizeMake(320, 576) videoQuality:kPLVideoStreamingQualityLow2];
    PLAudioStreamingConfiguration *audioConfiguration = [PLAudioStreamingConfiguration defaultConfiguration];
    PLStream *stream = [PLStream streamWithJSON:streamJSON];
    
    self.session = [[PLStreamingSession alloc] initWithVideoConfiguration:videoConfiguration
                                                       audioConfiguration:audioConfiguration stream:stream];
    self.session.delegate = self;
    
    
    
    
    // 使用 GPUImageVideoCamera 获取摄像头数据
    GPUImageVideoCamera *videoCamera = [[GPUImageVideoCamera alloc] initWithSessionPreset:AVCaptureSessionPreset640x480 cameraPosition:AVCaptureDevicePositionBack];
    videoCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
    
    // 创建一个 filter
    GPUImageSketchFilter *filter = [[GPUImageSketchFilter alloc] init];
    
    CGRect bounds = [UIScreen mainScreen].bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = width * 640.0 / 480.0;
    GPUImageView *filteredVideoView = [[GPUImageView alloc] initWithFrame:(CGRect){0, 64, width, height}];
    
    filteredVideoView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin |
                                         UIViewAutoresizingFlexibleBottomMargin |
                                         UIViewAutoresizingFlexibleLeftMargin |
                                         UIViewAutoresizingFlexibleRightMargin;
    filteredVideoView.backgroundColor = [UIColor redColor];
    
    // Add the view somewhere so it's visible
    [self.view addSubview:filteredVideoView];
    
    [videoCamera addTarget:filter];
    [filter addTarget:filteredVideoView];
    
    // 创建一个 GPUImageRawDataOutput 作为 filter 的 Target
    GPUImageRawDataOutput *rawDataOutput = [[GPUImageRawDataOutput alloc] initWithImageSize:CGSizeMake(480, 640) resultsInBGRAFormat:YES];
    [filter addTarget:rawDataOutput];
    __weak GPUImageRawDataOutput *weakOutput = rawDataOutput;
    __weak typeof(self) wself = self;
    [rawDataOutput setNewFrameAvailableBlock:^{
        NSLog(@"----start----");
        __strong GPUImageRawDataOutput *strongOutput = weakOutput;
        __strong typeof(wself) strongSelf = wself;
        [strongOutput lockFramebufferForReading];
        
        //从 GPUImageRawDataOutput 中获取 CVPixelBufferRef
        GLubyte *outputBytes = [strongOutput rawBytesForImage];
        NSInteger bytesPerRow = [strongOutput bytesPerRowInOutput];
        CVPixelBufferRef pixelBuffer = NULL;
        CVPixelBufferCreateWithBytes(kCFAllocatorDefault, 480, 640, kCVPixelFormatType_32BGRA, outputBytes, bytesPerRow, nil, nil, nil, &pixelBuffer);
        [strongOutput unlockFramebufferAfterReading];
        if(pixelBuffer == NULL) {
            return ;
        }
        
        // 发送视频数据
        [strongSelf.session pushPixelBuffer:pixelBuffer completion:^{
            NSLog(@"----send complete----");
            CVPixelBufferRelease(pixelBuffer);
        }];
    }];
    
    [videoCamera startCameraCapture];
    
    [self.session startWithCompleted:^(BOOL success) {
        // 这里的代码在主线程运行，所以可以放心对 UI 控件做操作
        if (success) {
            NSLog(@"success!");
        } else {
            NSLog(@"fail!");
        }
    }];
}

- (NSDictionary *)_createStreamObjectFromServer
{
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:kStreamCloudURL]];
    request.HTTPMethod = @"POST";
    
    NSHTTPURLResponse *response = nil;
    NSError* err = nil;
    NSData* data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&err];
    
    
    if (err != nil || response == nil || data == nil) {
        NSLog(@"get play json faild, %@, %@, %@", err, response, data);
        return nil;
    }
    
    NSDictionary *streamJSON = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableLeaves error:&err];
    if (err != nil || streamJSON == nil) {
        NSLog(@"json decode error %@", err);
        return nil;
    }
    
    return streamJSON;
}

@end
