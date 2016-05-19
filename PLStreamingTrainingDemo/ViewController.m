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

@interface ViewController () <PLStreamingSessionDelegate, PLStreamingSendingBufferDelegate>
@property (nonatomic, strong) PLStreamingSession *session;
@property (nonatomic, strong) AVCaptureSession  *cameraCaptureSession;
@property (nonatomic, strong) AVCaptureDevice *cameraCaptureDevice;
@property (nonatomic, strong) AVCaptureOutput   *cameraCaptureOutput;
@property (nonatomic, strong) AVCaptureOutput   *microphoneCaptureOutput;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSTimeInterval statusUpdateInterval = 3;
    
    [self initCameraSource];
    
    
    dispatch_queue_t sessionQueue = dispatch_queue_create("session.queue", NULL);
    dispatch_async(sessionQueue, ^{
        
        NSDictionary *streamJSON = [self _createStreamObjectFromServer];
        NSLog(@"Stream Json %@", streamJSON);
        
        PLStream *stream = [PLStream streamWithJSON:streamJSON];
        PLVideoStreamingConfiguration *videoConfiguration = [PLVideoStreamingConfiguration defaultConfiguration];
        PLAudioStreamingConfiguration *audioConfiguration = [PLAudioStreamingConfiguration defaultConfiguration];
        
        self.session = [[PLStreamingSession alloc] initWithVideoConfiguration:videoConfiguration audioConfiguration:audioConfiguration stream:stream];
        self.session.delegate = self;
        self.session.bufferDelegate = self;
        self.session.statusUpdateInterval = statusUpdateInterval;
        
        [self.session startWithCompleted:^(BOOL success) {
            // 这里的代码在主线程运行，所以可以放心对 UI 控件做操作
            if (success) {
                NSLog(@"success!");
            } else {
                NSLog(@"fail!");
            }
        }];
    });
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

- (void)initCameraSource {
    
    CGFloat expectedSourceVideoFrameRate = 20;
    
    __weak typeof(self) wself = self;
    void (^permissionGranted)(void) = ^{
        __strong typeof(wself) strongSelf = wself;
        
        NSArray *devices = [AVCaptureDevice devices];
        for (AVCaptureDevice *device in devices) {
            if ([device hasMediaType:AVMediaTypeVideo] && AVCaptureDevicePositionBack == device.position) {
                strongSelf.cameraCaptureDevice = device;
                break;
            }
        }
        
        if (!strongSelf.cameraCaptureDevice) {
            NSString *log = @"No back camera found.";
            NSLog(@"%@", log);
            return ;
        }
        
        AVCaptureSession *captureSession = [[AVCaptureSession alloc] init];
        AVCaptureDeviceInput *input = nil;
        AVCaptureVideoDataOutput *output = nil;
        
        input = [[AVCaptureDeviceInput alloc] initWithDevice:strongSelf.cameraCaptureDevice error:nil];
        output = [[AVCaptureVideoDataOutput alloc] init];
        
        strongSelf.cameraCaptureOutput = output;
        
        [captureSession beginConfiguration];
        captureSession.sessionPreset = AVCaptureSessionPreset640x480;
        
        // setup output
        output.videoSettings = @{(NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)};
        
        dispatch_queue_t cameraQueue = dispatch_queue_create("com.pili.camera", 0);
        [output setSampleBufferDelegate:strongSelf queue:cameraQueue];
        
        // add input && output
        if ([captureSession canAddInput:input]) {
            [captureSession addInput:input];
        }
        
        if ([captureSession canAddOutput:output]) {
            [captureSession addOutput:output];
        }
        
        NSLog(@"%@", [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio]);
        
        // audio capture device
        AVCaptureDevice *microphone = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:microphone error:nil];
        AVCaptureAudioDataOutput *audioOutput = nil;
        
        if ([captureSession canAddInput:audioInput]) {
            [captureSession addInput:audioInput];
        }
        audioOutput = [[AVCaptureAudioDataOutput alloc] init];
        
        self.microphoneCaptureOutput = audioOutput;
        
        if ([captureSession canAddOutput:audioOutput]) {
            [captureSession addOutput:audioOutput];
        } else {
            NSLog(@"Couldn't add audio output");
        }
        
        dispatch_queue_t audioProcessingQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0);
        [audioOutput setSampleBufferDelegate:strongSelf queue:audioProcessingQueue];
        
        [captureSession commitConfiguration];
        
        NSError *error;
        [strongSelf.cameraCaptureDevice lockForConfiguration:&error];
        strongSelf.cameraCaptureDevice.activeVideoMinFrameDuration = CMTimeMake(1.0, expectedSourceVideoFrameRate);
        strongSelf.cameraCaptureDevice.activeVideoMaxFrameDuration = CMTimeMake(1.0, expectedSourceVideoFrameRate);
        [strongSelf.cameraCaptureDevice unlockForConfiguration];
        
        strongSelf.cameraCaptureSession = captureSession;
        
        [strongSelf reorientCamera:AVCaptureVideoOrientationPortrait];
        
        AVCaptureVideoPreviewLayer* previewLayer;
        previewLayer =  [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
        previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        __weak typeof(strongSelf) wself1 = strongSelf;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself1) strongSelf1 = wself1;
            previewLayer.frame = strongSelf1.view.layer.bounds;
            [strongSelf1.view.layer insertSublayer:previewLayer atIndex:0];
        });
        
        [strongSelf.cameraCaptureSession startRunning];
    };
    
    void (^noPermission)(void) = ^{
        NSString *log = @"No camera permission.";
        NSLog(@"%@", log);
    };
    
    void (^requestPermission)(void) = ^{
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            if (granted) {
                permissionGranted();
            } else {
                noPermission();
            }
        }];
    };
    
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    switch (status) {
        case AVAuthorizationStatusAuthorized:
            permissionGranted();
            break;
        case AVAuthorizationStatusNotDetermined:
            requestPermission();
            break;
        case AVAuthorizationStatusDenied:
        case AVAuthorizationStatusRestricted:
        default:
            noPermission();
            break;
    }
}

- (void)reorientCamera:(AVCaptureVideoOrientation)orientation {
    if (!self.cameraCaptureSession) {
        return;
    }
    
    AVCaptureSession* session = (AVCaptureSession *)self.cameraCaptureSession;
    
    for (AVCaptureVideoDataOutput* output in session.outputs) {
        for (AVCaptureConnection * av in output.connections) {
            if (av.isVideoOrientationSupported) {
                av.videoOrientation = orientation;
            }
        }
    }
}

@end
