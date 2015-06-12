//
//  TrainViewController.m
//  AVDeepTrain
//
//  Created by Muhammad Hilal on 3/14/15.
//
//    The MIT License (MIT)
//
//    Copyright (c) 2015 ID Labs L.L.C.
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.
//

#import "TrainViewController.h"

#import <CoreImage/CoreImage.h>

#import <DeepBelief/DeepBelief.h>
#include <sys/time.h>
#import <Dropbox/Dropbox.h>
#import "YunConnect.h"

#include "svmutils.h"

static CGFloat DegreesToRadians(CGFloat degrees) {return degrees * M_PI / 180;};

@interface TrainViewController() <AVCaptureVideoDataOutputSampleBufferDelegate, UIPopoverPresentationControllerDelegate, YunConnectDelegate>
{
    __weak IBOutlet UIButton *learnButton;
    
    __weak IBOutlet UIProgressView *refProgressView;
    __weak IBOutlet UILabel *refLabel;

    __weak IBOutlet UIView *bar;
    __weak IBOutlet UIImageView *logoView;
    
    __weak IBOutlet UIView *statView;
    __weak IBOutlet UILabel *cnnTime;
    __weak IBOutlet UILabel *svmTime;
    __weak IBOutlet UILabel *faceTime;
    __weak IBOutlet UILabel *warpTime;
    
    __weak IBOutlet UILabel *numCNNLabel;
    __weak IBOutlet UILabel *numSVMLabel;
    
    __weak IBOutlet UITextView *Announcer;
    
    __weak IBOutlet UIProgressView *LearningProgressView;
    
    __weak IBOutlet UIButton *dropboxButton;
    __weak IBOutlet UIImageView *thumbPreview;
    
    __weak IBOutlet UIButton *faceButton;
    
    __weak IBOutlet UIButton *playPauseButton;
    
    __weak IBOutlet UILabel *learningStatusLabel;
    
    __weak IBOutlet UIButton *yunButton;
    
    __weak IBOutlet UIButton *quickButton;
    
    //video capture
    AVCaptureSession *session;
    AVCaptureVideoPreviewLayer *previewLayer;
    AVCaptureVideoDataOutput *videoDataOutput;
    
    dispatch_queue_t videoDataOutputQueue;
    
    //concurrency
    dispatch_group_t groupAlg;
    bool lockAlg;
    
    //sound
    AVSpeechSynthesizer* synth;
    AVAudioPlayer* pingPlayer;
    AVSpeechSynthesisVoice* manVoice;
    AVSpeechSynthesisVoice* womanVoice;
    
    //neural network
    void* network;

    //svm
    int positivePredictionsCount;
    int negativePredictionsCount;
    int kPositivePredictionTotal;
    int kNegativePredictionTotal;
    int predictionState;
    
    enum EPredictionState {
        eWaiting,
        ePositiveLearning,
        eNegativeWaiting,
        eNegativeLearning,
        ePredicting,
    };

    void* trainer;
    
    NSPointerArray* predictors;
    NSMutableArray* predictorNames;
    NSMutableArray* progressViews;
    NSMutableArray* progressLabels;
    NSPointerArray* clearedPredictors;
    NSString* trainingName;
    

    dispatch_queue_t announcerQueue;
    dispatch_queue_t jobQueue;

    NSMutableDictionary* recogNames;
    
    int maxSmiles;
    int maxNoSmiles;
    
    //Face Detection
    bool detectFaces;
    bool restoreDetectFaces;
    UIImage *square;
    CIDetector *faceDetector;
    
    float cnnDuration;
    float svmDuration;
    float warpDuration;
    float faceDuration;

    UIImage* previewImage;

    OSType sourcePixelFormat;
    CGRect clap;
    
    bool lockShow;
    
    //selection
    NSMutableDictionary* fRects;
    UIImage* square2;
    bool windowFlag;
    bool selectFlag;
    bool selectFlag2;
    CGRect selectRect;
    
    
    bool soundFlag;
    bool restoreSoundFlag;
    
    bool firstInteraction;
    
    UIActivityIndicatorView* activity;
    
    //popover pause
    bool paused;
    bool lastDetectFaces;
    int lastPredictionState;
    
    //memory warning
    int warningCount;
    
    //Yun
    NSMutableArray* yunConnections;
    NSMutableDictionary* yunTasks;
    
    
    NSMutableDictionary* objectForDevDict;//1 dev -> 1 obj, 1 obj -> many devices
    NSMutableDictionary* objectForTaskDict; //1 task -> 1 obj, 1 obj -> many tasks
    NSMutableDictionary* deviceForTaskDict;//1 task -> 1 dev, 1 dev -> many tasks
    
    UIView* anchorView;
}

//Prediction Labels view
@property (retain, nonatomic) CATextLayer *predictionTextLayer;

@property (retain, nonatomic) CATextLayer *infoForeground;

@property (readwrite) CFURLRef soundFileURLRef;
@property (readonly)  SystemSoundID soundFileObject;

@end


@implementation TrainViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    announcerQueue = dispatch_queue_create("announcerQueue", DISPATCH_QUEUE_SERIAL);
    jobQueue = dispatch_queue_create("jobQueue", DISPATCH_QUEUE_SERIAL);
    
    NSString* networkPath = [[NSBundle mainBundle] pathForResource:@"jetpac" ofType:@"ntwk"];
    if (networkPath == NULL) {
        fprintf(stderr, "Couldn't find the neural network parameters file - did you add it as a resource to your application?\n");
        assert(false);
    }
    
    network = jpcnn_create_network([networkPath UTF8String]);
    assert(network != NULL);
    
    [self checkDropboxIcon];
    
    activity = [[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    activity.backgroundColor = [UIColor grayColor];
    [activity layer].cornerRadius = 8.0;
    [activity layer].masksToBounds = YES;

    [self.view addSubview:activity];

    //hidden - for reference only
    refProgressView.hidden = YES;
    refLabel.hidden = YES;
    
    [self showHideStats:nil];
    
    learningStatusLabel.hidden = YES;
    LearningProgressView.hidden = YES;
    
    recogNames = [NSMutableDictionary dictionary];
    fRects = [NSMutableDictionary dictionary];
    
    //Learning Progress
    [self setupLearning];
    
    [self setupSound];
    
    [self setupAVCapture];
    
    [self setupInfoDisplay];
    
    //face detection
    square = [UIImage imageNamed:@"squarePNG"];
    NSDictionary *detectorOptions = [[NSDictionary alloc] initWithObjectsAndKeys:CIDetectorAccuracyLow, CIDetectorAccuracy, nil];
    faceDetector = [CIDetector detectorOfType:CIDetectorTypeFace context:nil options:detectorOptions];

    //selection
    square2 = [UIImage imageNamed:@"squarePNG2"];
    
    //concurrency
    groupAlg = dispatch_group_create();
    
    
    soundFlag = true;
    
    kPositivePredictionTotal = 50;
    kNegativePredictionTotal = 50;
    
    //Yun
    yunConnections = [NSMutableArray array];
    yunTasks = [NSMutableDictionary dictionary];
    
    objectForDevDict = [NSMutableDictionary dictionary];
    objectForTaskDict = [NSMutableDictionary dictionary];
    deviceForTaskDict = [NSMutableDictionary dictionary];
    
}

/*
-(void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator{
    
    [previewLayer setFrame:CGRectMake(0, 0, size.width, size.height)];

    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {

        [previewLayer.connection setVideoOrientation:[self videoOrientationFor:self.interfaceOrientation]];
        
    } completion:nil];
    
    //don't rotate video data output
 
    // for (AVCaptureConnection* connect in videoDataOutput.connections) {
     
    //if([connect isVideoOrientationSupported]){
    //[connect setVideoOrientation:[self videoOrientationFor:self.interfaceOrientation]];}}
    
    
}*/

-(BOOL)shouldAutorotate{
    return false;
}

-(NSUInteger)supportedInterfaceOrientations{
    
    return UIInterfaceOrientationLandscapeRight;
}


- (IBAction)showHideStats:(id)sender {
    
    if (!lockShow) {
        
        lockShow = YES;
        
        bool hide = !statView.hidden;
        
        statView.hidden = hide;
        
        thumbPreview.hidden = hide;
        
        Announcer.hidden = hide;
        
        playPauseButton.hidden = hide;
        
        if (predictionState == ePredicting) {
            
            for (UIView* v in progressLabels) {
                
                v.hidden = hide;
            }
            
            for (UIView* v in progressViews) {
                
                v.hidden = hide;
            }
            
        }

        [self removeLayersNamed:@"FaceLayer" fromLayer:previewLayer];
        
        for ( CALayer *layer in previewLayer.sublayers ) {
            if ( [[layer name] isEqualToString:@"SelectLayer"] )
                [layer setHidden:hide];
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            
            lockShow = NO;
        });
    }
    
}

- (IBAction)soundAction:(id)sender {
    
    UIButton* b = (UIButton*)sender;

    if (soundFlag) {
        
        [b setImage:[UIImage imageNamed:@"soundOff"] forState:UIControlStateNormal];
        
        [self speak:@"Sound off" withVoice:manVoice];
        
        soundFlag = NO;
        
    }else {
        
        [b setImage:[UIImage imageNamed:@"soundOn"] forState:UIControlStateNormal];

        soundFlag = YES;
        
        [self speak:@"Sound On" withVoice:womanVoice];
        
    }
    
}

- (IBAction)playPauseAction:(id)sender {
    
    if (paused) {
        [self resumeFrameProcessing];
        
    } else {
        
        [self pauseFrameProcessing];
        
    }
}

-(void)willEnterForeground{
    
    
    [self checkDropboxIcon];
    [self resumeFrameProcessing];
    
    if (restoreSoundFlag) {
        
        soundFlag = YES;
        restoreSoundFlag = NO;
        
    }
    
}

-(void)willResignActive{

    if (soundFlag) {
        
        soundFlag = NO;
        
        restoreSoundFlag = YES;
    }
    
    [self pauseFrameProcessing];
    
    [self disconnectAllYun];

}

#pragma mark - AVCapture

- (void)setupAVCapture
{
    NSError *error = nil;
    
    session = [AVCaptureSession new];
    //if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
        [session setSessionPreset:AVCaptureSessionPresetMedium];
    //else
        //[session setSessionPreset:AVCaptureSessionPresetPhoto];

    // Select a video device, make an input
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    
    if (error) {
        
        NSLog(@"%@", error);
        
        return;
    }
    
    
    if ( [session canAddInput:deviceInput] )
        [session addInput:deviceInput];
    
    // Make a video data output
    videoDataOutput = [AVCaptureVideoDataOutput new];
    
    // we want BGRA, both CoreGraphics and OpenGL work well with 'BGRA'
    NSDictionary *rgbOutputSettings = [NSDictionary dictionaryWithObject:
                                       [NSNumber numberWithInt:kCMPixelFormat_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];

    [videoDataOutput setVideoSettings:rgbOutputSettings];

    
    [videoDataOutput setAlwaysDiscardsLateVideoFrames:YES]; // discard if the data output queue is blocked (as we process the still image)
    
    
    // create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured
    // a serial dispatch queue must be used to guarantee that video frames will be delivered in order
    // see the header doc for setSampleBufferDelegate:queue: for more information
    videoDataOutputQueue = dispatch_queue_create("videoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
    [videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];

    
    if ( [session canAddOutput:videoDataOutput] )
        [session addOutput:videoDataOutput];

    
    AVCaptureConnection *objectVideoConnection= NULL;
    
    objectVideoConnection= [videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    [objectVideoConnection setEnabled:YES];

    //Don't rotate video data output! keep at LandscapeRight for Portrait preview, and at PortraitUpsideDown for LandscapeRight preview
    [objectVideoConnection setVideoOrientation:AVCaptureVideoOrientationPortraitUpsideDown];
    
    previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
    
    [previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
    [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    
    
    CALayer *rootLayer = [self.view layer];
    [rootLayer setMasksToBounds:YES];
    [previewLayer setFrame:[self.view bounds]];
    //[rootLayer addSublayer:previewLayer];
    [rootLayer insertSublayer:previewLayer atIndex:0];
    
    [previewLayer.connection setVideoOrientation:AVCaptureVideoOrientationLandscapeRight];
    
    [session startRunning];
    
    
}

// clean up capture setup
- (void)teardownAVCapture
{
    [previewLayer removeFromSuperlayer];
    
    //all releases omitted for ARC
    
}

-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    
    CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
    CIImage *frameImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer  options:(__bridge NSDictionary *)(attachments)];
    if (attachments)
        CFRelease(attachments);
    
        if (predictionState==ePositiveLearning || predictionState==eNegativeLearning || (predictionState== ePredicting && predictors.count>0)) {
            
            if (!lockAlg){
                
                lockAlg = YES;
            
                dispatch_group_async(groupAlg, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    
                    [self runAlgorithmsOnFrame:frameImage];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        
                        warpTime.text = [NSString stringWithFormat:@"%f",warpDuration];
                        
                        cnnTime.text = [NSString stringWithFormat:@"%f",cnnDuration];
                        
                        if (predictors.count<1) {
                            
                            svmTime.text = @"0";
                        } else {
                            
                            svmTime.text = [NSString stringWithFormat:@"%f",svmDuration];
                        }
                        
                        numSVMLabel.text = [NSString stringWithFormat:@"%d",(int) predictors.count];
                        
                        numCNNLabel.text = @"1";
                        
                    });
                    
                });
                
                dispatch_group_notify(groupAlg, dispatch_get_main_queue(), ^{
                    
                    lockAlg = NO;
                });
            
            }
            
            
        } else {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                numCNNLabel.text = @"0";
                cnnTime.text = @"0";
                svmTime.text = @"0";
                warpTime.text= @"0";
                
                thumbPreview.image = nil;
                
            });
        }
    
    if (predictionState == ePositiveLearning) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [LearningProgressView setProgress: (positivePredictionsCount / (float)kPositivePredictionTotal)];
        });

        
    }else if (predictionState == eNegativeLearning) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [LearningProgressView setProgress: (negativePredictionsCount / (float)kNegativePredictionTotal)];
        });

    }
    
    if (detectFaces) {
        
        // get the clean aperture
        // the clean aperture is a rectangle that defines the portion of the encoded pixel dimensions
        // that represents image data valid for display.
        CMFormatDescriptionRef fdesc = CMSampleBufferGetFormatDescription(sampleBuffer);
        clap = CMVideoFormatDescriptionGetCleanAperture(fdesc, false /*originIsTopLeft == false*/);
        
        dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{

            [self runFaceDetectionOnFrame :frameImage];
            
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                
                faceTime.text = [NSString stringWithFormat:@"%f",faceDuration];
                
            });
            
            
        });
        
    } else {
        
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            
            faceTime.text = @"0";
            
        });

        
    }
    
    //announcer
    
    [self removeZeroRecog];
    [self announceRecogNames];
    
}


#pragma mark - CNN


- (void)runAlgorithmsOnFrame: (CIImage*) frameImage
{
    
    NSDate* lastWarpTime = [NSDate date];
    
    float w = frameImage.extent.size.width;
    float h = frameImage.extent.size.height;
    
    CIContext* context = [CIContext contextWithOptions:nil];

    CGRect mask;
    if (windowFlag){
        
        if (selectFlag) {
            //we captured a frame while trying to select
            selectFlag2 = YES;
        }
        
        //scale the selection rect to the video frame dimensions (take care h and w are swapped for video orientation is rotated)
        float wScale = h/self.view.bounds.size.width;
        float hScale = w/self.view.bounds.size.height;
        
        mask = CGRectMake(selectRect.origin.y *wScale, selectRect.origin.x *hScale, selectRect.size.height*wScale, selectRect.size.width*hScale);
        
    }else {
        //all image
        mask = [frameImage extent];
    }
    
    //apply selection rect mask
    CGImageRef maskedCG = [context createCGImage:frameImage fromRect:mask];

    frameImage = [CIImage imageWithCGImage:maskedCG];
    
    CGImageRelease(maskedCG);

    //warp filter
    NSNumber* ratio = [NSNumber numberWithFloat: h/w];
    
    NSNumber* scaleRatio;
    
    if ([ratio floatValue]>1) {
        
        scaleRatio =[NSNumber numberWithFloat:230/w];
        
    }else {
        
        scaleRatio =[NSNumber numberWithFloat:230/h];
    }
    
    CIFilter* warp = [CIFilter filterWithName:@"CILanczosScaleTransform"];
    [warp setValue:frameImage forKey:@"inputImage"];
    [warp setValue:scaleRatio forKey:@"inputScale"];
    [warp setValue:ratio forKey:@"inputAspectRatio"];
    
    frameImage = warp.outputImage;
    
    //rotation filter
    CIFilter* rotate = [CIFilter filterWithName:@"CIStraightenFilter"];
    [rotate setValue:frameImage forKey:@"inputImage"];
    [rotate setValue:[NSNumber numberWithFloat:DegreesToRadians(-90.)] forKey:@"inputAngle"];
    
    frameImage = rotate.outputImage;

    //show thumb preview with a ping
    CGImageRef squareCG = [context createCGImage:frameImage fromRect:[frameImage extent]];
    previewImage = [UIImage imageWithCGImage:squareCG scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(squareCG);
    
    if (soundFlag && !quickButton.selected) {[pingPlayer play];}
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        thumbPreview.image = previewImage;

    });

    //create new buffer with same pixel format type as pixelBuffer and render finalImage to it
    CVPixelBufferRef buffer = NULL;
    
    CVPixelBufferCreate(kCFAllocatorDefault, frameImage.extent.size.width, frameImage.extent.size.height, sourcePixelFormat, (__bridge CFDictionaryRef) @{(__bridge NSString *) kCVPixelBufferIOSurfacePropertiesKey: @{}}, &buffer);


    [context render:frameImage toCVPixelBuffer:buffer];
    
    //making sure the image in buffer is correct by displaying it
    //CIImage *testImage = [[CIImage alloc] initWithCVPixelBuffer:buffer];


    warpDuration = -[lastWarpTime timeIntervalSinceNow];
    
    int doReverseChannels;
    if ( kCVPixelFormatType_32ARGB == sourcePixelFormat ) {
        doReverseChannels = 1;
    } else if ( kCVPixelFormatType_32BGRA == sourcePixelFormat ) {
        doReverseChannels = 0;
    } else {
        assert(false); // Unknown source format
    }
    
    const int sourceRowBytes = (int)CVPixelBufferGetBytesPerRow( buffer );
    const int width = (int)CVPixelBufferGetWidth( buffer );
    const int fullHeight = (int)CVPixelBufferGetHeight( buffer );
    CVPixelBufferLockBaseAddress( buffer, 0 );
    unsigned char* sourceBaseAddr = CVPixelBufferGetBaseAddress( buffer );
    int height;
    unsigned char* sourceStartAddr;
    if (fullHeight <= width) {
        height = fullHeight;
        sourceStartAddr = sourceBaseAddr;
    } else {
        height = width;
        const int marginY = ((fullHeight - width) / 2);
        sourceStartAddr = (sourceBaseAddr + (marginY * sourceRowBytes));
    }
    void* cnnInput = jpcnn_create_image_buffer_from_uint8_data(sourceStartAddr, width, height, 4, sourceRowBytes, doReverseChannels, 1);
    float* predictions;
    int predictionsLength;
    char** predictionsLabels;
    int predictionsLabelsLength;
    
    
    NSDate* lastCNNTime = [NSDate date];
    
    jpcnn_classify_image(network, cnnInput, JPCNN_RANDOM_SAMPLE, -2, &predictions, &predictionsLength, &predictionsLabels, &predictionsLabelsLength);
    
    cnnDuration = -[lastCNNTime timeIntervalSinceNow];
    
    jpcnn_destroy_image_buffer(cnnInput);
    
    CVPixelBufferRelease(buffer);
    
    //handle network predictions
    
    switch (predictionState) {
        case eWaiting: {
            // Do nothing
        } break;
            
        case ePositiveLearning: {
            jpcnn_train(trainer, 1.0f, predictions, predictionsLength);
            positivePredictionsCount += 1;
            if (positivePredictionsCount >= kPositivePredictionTotal) {

                [self startNegativeWaiting];
                
            }
        } break;
            
        case eNegativeWaiting: {
            // Do nothing
        } break;
            
        case eNegativeLearning: {
            jpcnn_train(trainer, 0.0f, predictions, predictionsLength);
            negativePredictionsCount += 1;
            if (negativePredictionsCount >= kNegativePredictionTotal) {

                [self startPredicting];
            }
        } break;
            
        case ePredicting: {
            
            NSDate* lastSVMTime = [NSDate date];
            
            [self derecogAll];
            
            NSMutableDictionary* selected = [NSMutableDictionary dictionary];
            
            for (int i=0; i<predictors.count; i++) {
                
                void* predictor = [predictors pointerAtIndex:i];
                
                const float predictionValue = jpcnn_predict(predictor, predictions, predictionsLength);
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    [self setProgress:predictionValue forPredictor:i];
                });
                
                //threshold condition for selection from filtered recogNames
                if (selectFlag2 && predictionValue > 0.7) {//Flag2 to make sure the frame being processed was captured with the select window
                    
                    if (quickButton.selected) {//quick mode
                        
                        [selected setObject:[NSNumber numberWithFloat:predictionValue] forKey:predictorNames[i]];

                        
                    } else {//default voting
                      
                        NSArray* filtered = [self filterRecogNames];
                        for (NSString* name in filtered) {
                            
                            if ([predictorNames[i] isEqualToString:name]) {
                                
                                [selected setObject:[NSNumber numberWithFloat:predictionValue] forKey:name];
                                
                                break;
                            }
                            
                        }
                    }

                }
                
                //logic to handle prediction values
                
                //push name condition done first - for new names to enter recogNames
                if (predictionValue > 0.6) {
                    
                    [self pushName:predictorNames[i]];
                    
                }
                
                //star for existing recogNames
                if (predictionValue >0.8) {
                    
                    [self starName:predictorNames[i]];
                    
                }
                
                //demote existing recogNames
                if (predictionValue < 0.2) {
                    
                    [self demoteName:predictorNames[i]];
                }

            }
            
            svmDuration = -[lastSVMTime timeIntervalSinceNow];
            
            
            //compare selected and popover for highest prediction
            if (selected.count>0) {
                
                //pick the highest prediction value selected name
                [self popoverForObject:
                 [[selected keysSortedByValueUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                    
                    return [obj2 compare:obj1];
                
                }]firstObject] atPoint:activity.center];
                
                dispatch_async(dispatch_get_main_queue(), ^{

                    //deselect
                    windowFlag = NO;
                    selectFlag = NO;
                    selectFlag2 = NO;
                    
                    [activity stopAnimating];
                    
                    // remove layer
                    [self removeLayersNamed:@"SelectLayer" fromLayer:previewLayer];
                    
                    
                });
                
            }
            
            /*
             for (NSString* key in recogNames.allKeys) {
             
             NSLog([key stringByAppendingString:[NSString stringWithFormat:@" %d",[[recogNames valueForKey:key]intValue]]]);
             }
             */
            
        } break;
            
        default: {
            assert(FALSE); // Should never get here
        } break;
    }
    
    dispatch_async(jobQueue, ^{
        
        if (clearedPredictors.count) {
            
            for (int i=0; i<clearedPredictors.count; i++) {
                
                jpcnn_destroy_predictor([clearedPredictors pointerAtIndex:i]);
                
            }
            
            clearedPredictors = [NSPointerArray pointerArrayWithOptions:NSPointerFunctionsOpaqueMemory];
            
        }
        
    });
    
    
}


- (IBAction)quickAction:(id)sender {
    
    quickButton.selected = !quickButton.selected;
}


#pragma mark - Recognition

-(void) derecogAll {
    
    dispatch_async(announcerQueue, ^{
    
        NSMutableDictionary* temp = [NSMutableDictionary dictionary];
        
        for (NSString* key in recogNames.allKeys) {
            
            int i = [[recogNames valueForKey:key] intValue]-1;
            
            if (i<0) i = 0;
            
            [temp setObject:[NSNumber numberWithInt:i] forKey:key];
            
        }
        
        [recogNames setDictionary:temp];
 
    });
    
    
}

-(void) starName: (NSString*) name {
    
    dispatch_async(announcerQueue, ^{
    
        for (NSString* key in recogNames.allKeys) {
            
            if ([name isEqualToString:key]) {
                
                int i = [[recogNames valueForKey:key] intValue];
                
                if (i<7) {
                    i = i + 3;
                }else {
                    i =9;
                }
                
                [recogNames setObject:[NSNumber numberWithInteger:i] forKey:name];
                
                break;
            }
        }

    });
}

-(void) pushName: (NSString*) name {
    
     dispatch_async(announcerQueue, ^{
        
         int i = 1;
         
         for (NSString* key in recogNames.allKeys) {
             
             if ([name isEqualToString:key]) {
                 
                 i = [[recogNames valueForKey:key] intValue]+ 1;
                 
                 break;
             }
         }
         
         [recogNames setObject:[NSNumber numberWithInteger:i] forKey:name];
         
     });
}

-(void) demoteName: (NSString*) name {
    
    dispatch_async(announcerQueue, ^{
        
        
        for (NSString* key in recogNames.allKeys) {
            
            if ([name isEqualToString:key]) {
                
                int i = [[recogNames valueForKey:key] intValue];
                
                if (i>4) {
                    i = i - 2;
                }
                
                [recogNames setObject:[NSNumber numberWithInteger:i] forKey:name];
                
                break;
            }
        }
    });
    
    
}


-(NSArray*) filterRecogNames {
    
    NSMutableArray* result = [NSMutableArray array];
    
    dispatch_sync(announcerQueue, ^{
        
        for (NSString* key in recogNames.allKeys) {
            
            int i = [[recogNames valueForKey:key] intValue];
            
            if (i>5) {
                
                [result addObject:key];
                
            }
        }
        
    });
    
    return [NSArray arrayWithArray:result];
    
}


-(void) announceRecogNames {
    
    
    NSString* st = [NSString string];
    
    NSArray* filtered = [self filterRecogNames];
    
    for (NSString* name in filtered) {
        
        st = [st stringByAppendingString:[name stringByAppendingString:@"\n"]];
        
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        Announcer.text = st;
        
    });
    
    
}


-(void) removeZeroRecog {
    
    dispatch_async(announcerQueue, ^{
        
        NSMutableDictionary* temp = [NSMutableDictionary dictionary];
        
        if (!detectFaces) {
            
            for (NSString* key in [recogNames allKeys]) {
                
                if(key.length>5 && [[key substringToIndex:5] isEqualToString:@"Face_"]){
                    
                    [recogNames setObject:@0 forKey:key];
                }
            }
            
        }
        
        for (NSString* key in recogNames.allKeys) {
            
            int i = [[recogNames valueForKey:key] intValue];
            
            if (i>0) {
                
                [temp setObject:[NSNumber numberWithInt:i] forKey:key];
            }
            
        }
        
        [recogNames setDictionary:temp];
        
        
    });
}



#pragma mark - Learning

- (void) setupLearning {
    
    negativePredictionsCount = 0;
    
    trainer = NULL;

    predictionState = eWaiting;
    
    predictors = [NSPointerArray pointerArrayWithOptions:NSPointerFunctionsOpaqueMemory];
    clearedPredictors = [NSPointerArray pointerArrayWithOptions:NSPointerFunctionsOpaqueMemory];
    predictorNames = [NSMutableArray array];
    progressViews = [NSMutableArray array];
    progressLabels = [NSMutableArray array];
    
    
}

-(void) cancelLearning {

    dispatch_async(dispatch_get_main_queue(), ^{
        
        if (restoreDetectFaces) {
            [self toggleFaceDetection];
            restoreDetectFaces = NO;
        }
        
        faceButton.enabled = YES;
        
        learningStatusLabel.hidden = YES;
        LearningProgressView.hidden = YES;
    
        [self removeLayersNamed:@"WindowLayer" fromLayer:previewLayer];
        
        windowFlag = NO;

        [learnButton setTitle: @"Learn" forState:UIControlStateNormal];
        [self showProgress];
        
        if (predictors.count>0) {
            
            predictionState = ePredicting;
            
        } else {
            
            predictionState = eWaiting;
        }

    });

    if (trainer != NULL) {
        jpcnn_destroy_trainer(trainer);
        
        trainer = NULL;
    }


    

}

- (void) startPositiveLearning {
    
    if (trainer != NULL) {
        jpcnn_destroy_trainer(trainer);
    }
    trainer = jpcnn_create_trainer();
    
    [recogNames removeAllObjects];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        if (detectFaces) {
            
            [self toggleFaceDetection];
            restoreDetectFaces = YES;
            
        }
        
        faceButton.enabled = NO;
        
        //deselect
        windowFlag = NO;
        selectFlag = NO;
        selectFlag2 = NO;
        
        [activity stopAnimating];
        
        // remove layer
        [self removeLayersNamed:@"SelectLayer" fromLayer:previewLayer];
        [self removeLayersNamed:@"WindowLayer" fromLayer:previewLayer];
        

        [LearningProgressView setProgress: 0.0f];
        LearningProgressView.hidden = NO;
        
        learningStatusLabel.hidden = NO;
        
        Announcer.text = @"";
        
        thumbPreview.hidden = statView.hidden;
        [self hideProgress];
        
        [learnButton setTitle: @"Cancel" forState:UIControlStateNormal];
        
    });
    
    positivePredictionsCount = 0;
    predictionState = ePositiveLearning;
    
    [self speak: @"Move around the thing you want to recognize, keeping the camera pointed at it, to capture different angles." withVoice:manVoice];
    
    
}

- (void) startNegativeWaiting {
    
    predictionState = eNegativeWaiting;
    
    [self speak: @"Now I need to see examples of things that are not the object you're looking for. Press the button when you're ready." withVoice:manVoice];

    dispatch_async(dispatch_get_main_queue(), ^{
        
        LearningProgressView.hidden = YES;
        
        thumbPreview.hidden = YES;
        [self hideProgress];
        
        [learnButton setTitle: @"Continue" forState:UIControlStateNormal];


    });
    
}

- (void) startNegativeLearning {
    
    negativePredictionsCount = 0;
    predictionState = eNegativeLearning;
    
    dispatch_async(dispatch_get_main_queue(), ^{

        [LearningProgressView setProgress: 0.0f];
        LearningProgressView.hidden = NO;
        
        thumbPreview.hidden = statView.hidden;
        [self hideProgress];
        
        [learnButton setTitle: @"Cancel" forState:UIControlStateNormal];

    });
    
    
    [self speak: @"Now move around the room pointing your camera at lots of things, that are not the object you want to recognize." withVoice:manVoice];


}


#pragma mark -predictors

- (void) startPredicting {
    
    void * predictor = jpcnn_create_predictor_from_trainer(trainer);

    if (predictor!=NULL) {
        
        [predictorNames addObject:trainingName];
        [predictors addPointer:predictor];
            
        [self addProgressBarWithTitle:trainingName];
        [self showProgress];

        //check if dropbox account linked
        DBAccount* account = [[DBAccountManager sharedManager] linkedAccount];
        if (account) {
            
            dispatch_async(jobQueue, ^{
                
                NSString* filepath = [self savePredictor:predictor toFileNamed:trainingName];
                
                if (filepath) {
                    
                    [self createDropboxFileSystemForAccount:account];
                    
                    DBPath *newPath = [[DBPath root] childPath:[trainingName stringByAppendingString:@".txt"]];
                    DBFile *file = [[DBFilesystem sharedFilesystem] createFile:newPath error:nil];
                    [file writeContentsOfFile:filepath shouldSteal:YES error:nil];
                    
                    
                }});
            
        }
        
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        if (restoreDetectFaces) {
            
            [self toggleFaceDetection];
            restoreDetectFaces = NO;
            
        }
        
        faceButton.enabled = YES;
        
        learningStatusLabel.hidden = YES;
        LearningProgressView.hidden = YES;
        
        
        if (predictors.count>0) {
            
            [self showProgress];
            thumbPreview.hidden = statView.hidden;
        } else {
            
            [self hideProgress];
            thumbPreview.hidden = YES;
        }
        
        
        [learnButton setTitle: @"Learn" forState:UIControlStateNormal];

        //deselect
        windowFlag = NO;
        selectFlag = NO;
        selectFlag2 = NO;
        
        [activity stopAnimating];
        
        // remove layer
        [self removeLayersNamed:@"SelectLayer" fromLayer:previewLayer];
        [self removeLayersNamed:@"WindowLayer" fromLayer:previewLayer];
        
    });

    predictionState = ePredicting;
    
    [self speak: @"You can scan around using the camera, to detect the objects' presence." withVoice:manVoice];
    
}


-(NSString*) savePredictor:(void*)predictorHandle toFileNamed:(NSString*)filename {
    
    typedef struct SPredictorInfoStruct {
        struct svm_model* model;
        SLibSvmProblem* problem;
    } SPredictorInfo;
    
    SPredictorInfo* predictorInfo = (SPredictorInfo*)(predictorHandle);
    struct svm_model* model = predictorInfo->model;

    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    NSString *path = [documentsDirectory stringByAppendingPathComponent:filename];
    const char *filePath = [path cStringUsingEncoding:NSASCIIStringEncoding];
    
    FILE *fp = fopen(filePath, "w");

    if(fp!=NULL){
        const int saveResult = svm_save_model_to_file_handle(fp, model);
    
        if (saveResult != 0) {
            fprintf(stderr, "Couldn't save libsvm model file to '%s'\n", [filename UTF8String]);
        }
    
        return path;
    }
    
    return nil;
    
}

-(void) loadPredictorFromFileInfo:(DBFileInfo*)info {
    
    bool new = true;
    //make sure it's not a duplicate
    for (NSString* name in predictorNames) {
        
        if ([name isEqualToString:[info.path.name stringByDeletingPathExtension]]) {
            
            new = false;
        }
        
    }
    
    if (new) {
        
        DBAccount* account = [[DBAccountManager sharedManager] linkedAccount];
        if (account) {

            [self createDropboxFileSystemForAccount:account];
            DBFile *file = [[DBFilesystem sharedFilesystem] openFile:info.path error:nil];
            NSData *data = [file readData:nil];
            
            //write data to a local file
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *documentsDirectory = [paths objectAtIndex:0];
            NSString *filepath = [documentsDirectory stringByAppendingPathComponent:info.path.name];
            [data writeToFile:filepath atomically:YES];
            
            //load local file into a predictor
            void* predictor = jpcnn_load_predictor([filepath UTF8String]);
            
            if (predictor!=NULL) {
                
                trainingName = [info.path.name stringByDeletingPathExtension];
                [predictorNames addObject:trainingName];
                [predictors addPointer:predictor];

                [self speak: [trainingName stringByAppendingString:@" predictor loaded."] withVoice:manVoice];
                [self addProgressBarWithTitle:trainingName];
                [self showProgress];
                
            }

        }
    } else {
        
        [self speak: @"Predictor already loaded." withVoice:manVoice];
    }

    
}

-(void) loadPredictorsMenu{

    NSArray* filesInfo;
    
    DBAccount* account = [[DBAccountManager sharedManager] linkedAccount];
    if (account) {
    
        [self createDropboxFileSystemForAccount:account];
        
        //list all files in the App folder
        filesInfo = [[DBFilesystem sharedFilesystem] listFolder:[DBPath root] error:nil];

    }

    if (filesInfo.count>0) {

        NSMutableArray* pNames = [NSMutableArray array];
        
        //get names
        for (DBFileInfo* info in filesInfo) {
        
            [pNames addObject: [info.path.name stringByDeletingPathExtension]];

        }
        
        //show popover menu with predictors
        [self actionSheetWithTitle:@"Files on Dropbox" andItemNames:pNames andAction:^(int i, NSString *name) {
            
            dispatch_async(jobQueue, ^{
                
                DBFileInfo* info;
                for (DBFileInfo* f in filesInfo) {
                    
                    if([name isEqualToString:[f.path.name stringByDeletingPathExtension]])
                        
                        info = f;
                }
                
                [self loadPredictorFromFileInfo:info];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    predictionState = ePredicting;
                    
                    [self showProgress];
                    thumbPreview.hidden = statView.hidden;
                    
                    //deselect
                    windowFlag = NO;
                    selectFlag = NO;
                    selectFlag2 = NO;
                    
                    [activity stopAnimating];
                    
                    // remove layer
                    [self removeLayersNamed:@"SelectLayer" fromLayer:previewLayer];
                    [self removeLayersNamed:@"WindowLayer" fromLayer:previewLayer];
                    
                    [learnButton setTitle: @"Learn" forState:UIControlStateNormal];
                    
                });
                
                
            });

        } fromSourceView:dropboxButton lastRed:NO];
        
    } else {
        
        
        [self actionSheetWithTitle:@"Files on Dropbox" andItemNames:[NSArray arrayWithObject:@"No Predictors to Load"] andAction:nil fromSourceView:dropboxButton lastRed:NO];

    }

}


-(void)clearAllPredictors {
    
    dispatch_sync(jobQueue, ^{
        
        clearedPredictors = predictors;
        
    });

    predictors = [NSPointerArray pointerArrayWithOptions:NSPointerFunctionsOpaqueMemory];
    [predictorNames removeAllObjects];
    
    predictionState = eWaiting;
    lastPredictionState = eWaiting;
    
    dispatch_async(dispatch_get_main_queue(), ^{

        for (UIProgressView* pv in progressViews) {
            
            [pv removeFromSuperview];
        }
        [progressViews removeAllObjects];
        
        for (UILabel* lbl in progressLabels) {
            
            [lbl removeFromSuperview];
        }
        [progressLabels removeAllObjects];
        
        [recogNames removeAllObjects];
        Announcer.text = @"";
        
        //deselect
        windowFlag = NO;
        selectFlag = NO;
        selectFlag2 = NO;
        
        [activity stopAnimating];
        
        // remove layer
        [self removeLayersNamed:@"SelectLayer" fromLayer:previewLayer];
        
        thumbPreview.hidden = YES;
        
    });
    
}

-(void) clearPredictor:(NSString*)predictorName {

    int pIndex;
    for (int i =0; i<predictorNames.count; i++) {
        
        if ([predictorNames[i] isEqualToString:predictorName]) {
            
            pIndex = i;
            break;
        }
    }

    dispatch_sync(jobQueue, ^{

        [clearedPredictors addPointer:[predictors pointerAtIndex:pIndex]];
        
    });

    //remove the predictor from the 2 arrays
    [predictorNames removeObjectAtIndex:pIndex];
    [predictors removePointerAtIndex:pIndex];
    
    [recogNames removeObjectForKey:predictorName];
    
    //remove progress bar
    [self removeProgressBarWithTitle:predictorName];

    if (predictorNames.count <1) {//no predictors left
        
        predictionState = eWaiting;
        lastPredictionState = eWaiting;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            //deselect
            windowFlag = NO;
            selectFlag = NO;
            selectFlag2 = NO;
            
            [activity stopAnimating];
            
            // remove layer
            [self removeLayersNamed:@"SelectLayer" fromLayer:previewLayer];
            
            thumbPreview.hidden = YES;
            
        });
        
    }
    
    
}

#pragma mark - Learn Button Action

- (IBAction)learnAction:(id)sender {
    
    firstInteraction = YES;
    
    switch (predictionState) {
        case eWaiting: {
            
            [self newPredictorAlert];

        } break;
            
        case ePositiveLearning: {

            [self cancelLearning];
            
        } break;
            
        case eNegativeWaiting: {

            [self startNegativeLearning];
        } break;
            
        case eNegativeLearning: {
            
            [self cancelLearning];
            
        } break;
            
        case ePredicting: {
          
            [self newPredictorAlert];

        } break;
            
        default: {
            assert(FALSE); // Should never get here
        } break;
    }
    
}

-(void) newPredictorAlert {
    
    [self dataEntryAlertWithTitle:@"New Predictor" andMessage:@"Enter object name, and number of positive and negative samples" andTextFieldsPlaceholders:[NSArray arrayWithObjects:@"<random object>",[NSString stringWithFormat:@"%d <5-200>",kPositivePredictionTotal],[NSString stringWithFormat:@"%d <5-200>",kNegativePredictionTotal], nil] andAction:^(NSArray *entries) {
        
        UITextField* f = [entries objectAtIndex:0];
        
        NSString* name;
        
        if(f.text.length>0) {
            
            name = f.text;
            
        } else {
            
            name = [NSString stringWithFormat:@"Object_%d",arc4random()%1000];
            
        }
        
        bool new = true;
        //make sure it's not a duplicate
        for (NSString* p in predictorNames) {
            
            if ([p isEqualToString:name]) {
                
                new = false;
            }
            
        }
        
        //check on dropbox too
        NSArray* filesInfo;
        
        DBAccount* account = [[DBAccountManager sharedManager] linkedAccount];
        if (account) {
            
            [self createDropboxFileSystemForAccount:account];
            
            //list all files in the App folder
            filesInfo = [[DBFilesystem sharedFilesystem] listFolder:[DBPath root] error:nil];
            
        }
        
        
        for (DBFileInfo* info in filesInfo) {
            
            NSString* predictorName = [info.path.name stringByDeletingPathExtension];
            
            if ([name isEqualToString:predictorName]) {
                new = false;
            }
        }
        
        if (new) {
            
            trainingName = name;
            
            f = [entries objectAtIndex:1];
            int p = [f.text intValue];
            if (p>=5 && p<=200) {
                
                kPositivePredictionTotal = p;
            }
            
            f = [entries objectAtIndex:2];
            int n = [f.text intValue];
            if (n>=5 && n<=200) {
                
                kNegativePredictionTotal = n;
            }
            
            learningStatusLabel.text = [[NSString stringWithFormat:@"Learning  %d / %d  ", kPositivePredictionTotal, kNegativePredictionTotal] stringByAppendingString:name];
            
            [self startPositiveLearning];
            
            lastPredictionState = ePositiveLearning;//to ensure resumeFrameProcessing gets us to the correct state
            
        }
        
        else {
            
            [self OKAlertWithTitle:@"This name is already used!" andMessage:@"try another one"];
            
        }
        
    } returnKeyName:@"Start"];
    
    
}


#pragma mark - Info Display

-(void) addProgressBarWithTitle:(NSString*)title {
    
    dispatch_async(dispatch_get_main_queue(), ^{
                
        NSUInteger n = progressViews.count;
        
        CGRect ref = refProgressView.frame;
        UIProgressView* p = [[UIProgressView alloc]initWithFrame:CGRectMake(ref.origin.x, ref.origin.y + ( n * 30 ), ref.size.width, ref.size.height)];
        
        [p setProgressViewStyle:UIProgressViewStyleBar];
        
        ref = refLabel.frame;
        UILabel* l = [[UILabel alloc]initWithFrame:CGRectMake(ref.origin.x, ref.origin.y + ( n * 30 ), ref.size.width, ref.size.height)];
        [l setText:title];
        [l setTextColor:refLabel.textColor];
        [l setTextAlignment:refLabel.textAlignment];
        [l setFont:refLabel.font];
        [l setBackgroundColor:refLabel.backgroundColor];

        p.hidden = YES;
        l.hidden = YES;
        
        [progressViews addObject:p];
        [progressLabels addObject:l];

        [self.view addSubview:p];
        [self.view addSubview:l];
    });
        
}

-(void) removeProgressBarWithTitle:(NSString*)title {
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        NSUInteger pIndex=0;
        bool found = NO;
        for (UILabel* label in progressLabels) {
            
            if ([label.text isEqualToString:title]) {
                
                pIndex = [progressLabels indexOfObject:label];
                found = YES;
                break;
            }
        }
        
        if (found) {

            [[progressViews objectAtIndex:pIndex]removeFromSuperview];
            [[progressLabels objectAtIndex:pIndex] removeFromSuperview];
            
            [progressLabels removeObjectAtIndex:pIndex];
            [progressViews removeObjectAtIndex:pIndex];

            //push up any later views
            for (NSUInteger i = pIndex; i<progressLabels.count; i++) {

                UIProgressView* view = [progressViews objectAtIndex:i];
                UILabel* label = [progressLabels objectAtIndex:i];
                
                CGRect ref = refProgressView.frame;
                
                [view setFrame:CGRectMake(ref.origin.x, ref.origin.y + ( i * 30 ), ref.size.width, ref.size.height)];

                ref = refLabel.frame;
                [label setFrame:CGRectMake(ref.origin.x, ref.origin.y + ( i * 30 ), ref.size.width, ref.size.height)];
                
            }
            
        }
        
    });

}

-(void) hideProgress {

    dispatch_async(dispatch_get_main_queue(), ^{
    
        for (UIProgressView* v in progressViews) {
            v.hidden = YES;
        }
        
        for (UILabel* l in progressLabels) {
            l.hidden = YES;
        }
        
    
    
    });
    
}

-(void) showProgress{
    
    dispatch_async(dispatch_get_main_queue(), ^{

        if (!statView.hidden) {
            for (UIProgressView* v in progressViews) {
                v.hidden = NO;
            }
            
            for (UILabel* l in progressLabels) {
                l.hidden = NO;
            }
            
        }
        
        
    });
    
    
}

- (void) setProgress: (float) amount forPredictor:(int) i {

    dispatch_async(dispatch_get_main_queue(), ^{
    
        UIProgressView* v = [progressViews objectAtIndex:i];
        
        [v setProgress:amount];
        
    
    });
    
}

- (void) setupInfoDisplay {
    
    NSString* const font = @"Menlo-Regular";
    const float fontSize = 20.0f;
    
    const float viewWidth = 320.0f;
    
    const float marginSizeX = 5.0f;
    const float marginSizeY = 18.0f;
    //const float marginTopY = 20.0f;
    
    const float progressHeight = 20.0f;
    
    const float infoHeight = 150.0f;
    
    
    const CGRect infoBackgroundBounds = CGRectMake(marginSizeX, (marginSizeY + progressHeight + marginSizeY), (viewWidth - (marginSizeX * 2)), infoHeight);
    
    const CGRect infoForegroundBounds = CGRectInset(infoBackgroundBounds, 5.0f, 5.0f);
    
    self.infoForeground = [CATextLayer layer];
    [self.infoForeground setBackgroundColor: [UIColor clearColor].CGColor];
    [self.infoForeground setForegroundColor: [UIColor whiteColor].CGColor];
    [self.infoForeground setOpacity:1.0f];
    [self.infoForeground setFrame: infoForegroundBounds];
    [self.infoForeground setWrapped: YES];
    [self.infoForeground setFont: (__bridge CFTypeRef)(font)];
    [self.infoForeground setFontSize: fontSize];
    self.infoForeground.contentsScale = [[UIScreen mainScreen] scale];
    
    [self.infoForeground setString: @""];
    
    [[self.view layer] addSublayer: self.infoForeground];
}


#pragma mark - Face Detection
- (IBAction)faceAction:(id)sender {
    
    [self toggleFaceDetection];
    
  }

-(void) toggleFaceDetection {
    
    if (!paused) {
        
        faceButton.selected = ! faceButton.selected;
        
        if (!faceButton.selected) {
            
            detectFaces = NO;
            
            dispatch_sync(jobQueue, ^{
                
                [fRects removeAllObjects];
                
            });
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                // clear out any squares currently displaying.
                [self removeLayersNamed:@"FaceLayer" fromLayer:previewLayer];
                
            });

        } else {
            
            detectFaces = YES;
        }
        
    }


}


-(CGRect) findRectForFaceFeature:(CIFaceFeature*)feature {
    
    //calculate previewBox
    CGSize parentFrameSize = [self.view frame].size;
    NSString *gravity = [previewLayer videoGravity];
    CGRect previewBox = [self videoPreviewBoxForGravity:gravity frameSize:parentFrameSize apertureSize:clap.size];

    // find the correct position for the square layer within the previewLayer
    // the feature box originates in the bottom left of the video frame.
    // (Bottom right if mirroring is turned on)
    CGRect faceRect = [feature bounds];
    
    // flip preview width and height
    CGFloat temp = faceRect.size.width;
    faceRect.size.width = faceRect.size.height;
    faceRect.size.height = temp;
    temp = faceRect.origin.x;
    faceRect.origin.x = faceRect.origin.y;
    faceRect.origin.y = temp;
    // scale coordinates so they fit in the preview box, which may be scaled
    CGFloat widthScaleBy = previewBox.size.width / clap.size.height;
    CGFloat heightScaleBy = previewBox.size.height / clap.size.width;
    faceRect.size.width *= widthScaleBy;
    faceRect.size.height *= heightScaleBy;
    faceRect.origin.x *= widthScaleBy;
    faceRect.origin.y *= heightScaleBy;
    
    //if ( isMirrored )
    //  faceRect = CGRectOffset(faceRect, previewBox.origin.x + previewBox.size.width - faceRect.size.width - (faceRect.origin.x * 2), previewBox.origin.y);
    //else
    // faceRect = CGRectOffset(faceRect, previewBox.origin.x, previewBox.origin.y);
    

    return faceRect;
}

// called asynchronously as the capture output is capturing sample buffers, this method asks the face detector (if on)
// to detect features and for each draw the red square in a layer and set appropriate orientation
- (void)drawFaceBoxesForFeatures:(NSArray *)features
{
    
    NSArray *sublayers = [NSArray arrayWithArray:[previewLayer sublayers]];
    NSInteger sublayersCount = [sublayers count], currentSublayer = 0;
    NSInteger featuresCount = [features count];
    
    
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];


    // hide all the face layers
    for ( CALayer *layer in sublayers ) {
        if ( [[layer name] isEqualToString:@"FaceLayer"] )
            [layer setHidden:YES];
    }	

    
    if ( featuresCount == 0 || !detectFaces ) {
        [CATransaction commit];
        return; // early bail.
    }

    for ( CIFaceFeature *ff in features ) {
              CALayer *featureLayer = nil;
        
        CGRect faceRect = [self findRectForFaceFeature:ff];
        
        // re-use an existing layer if possible
        while ( !featureLayer && (currentSublayer < sublayersCount) ) {
            CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
            if ( [[currentLayer name] isEqualToString:@"FaceLayer"] ) {
                featureLayer = currentLayer;
                [currentLayer setHidden:NO];
            }
        }
        
        // create a new one if necessary
        if ( !featureLayer ) {
            featureLayer = [CALayer new];
            [featureLayer setContents:(id)[square CGImage]];
            [featureLayer setName:@"FaceLayer"];
            [previewLayer addSublayer:featureLayer];

        }
        [featureLayer setFrame:faceRect];

    }
    
    [CATransaction commit];
}

-(void) runFaceDetectionOnFrame:(CIImage*) frame {
    
    
    NSDate* lastFaceDetectTime = [NSDate date];
    
    //Devil in Details: 6 is PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP enum value
    NSArray *features = [faceDetector featuresInImage:frame options:@{ CIDetectorSmile : @YES, CIDetectorImageOrientation : [NSNumber numberWithInt:6] }];
    
    faceDuration = -[lastFaceDetectTime timeIntervalSinceNow];
    
    int smiles = 0;
    int nosmiles = 0;
    
    dispatch_sync(jobQueue, ^{
        
        [fRects removeAllObjects];
        
    });
    
    for(CIFaceFeature *faceFeature in features)
    {
        //write localization code for faces here
        CGRect faceRect = [self findRectForFaceFeature:faceFeature];
        NSString* sm = @"Face_Smiley_";
        NSString* nosm = @"Face_";
        
        if (faceFeature.hasSmile) {
            
            smiles++;
            dispatch_sync(jobQueue, ^{
                
                [fRects setValue:[NSValue valueWithCGRect:faceRect] forKey:[sm stringByAppendingFormat:@"%d",smiles]];
                
            });
            
        } else {
            
            nosmiles++;
            
            dispatch_sync(jobQueue, ^{
                
                [fRects setValue:[NSValue valueWithCGRect:faceRect] forKey:[nosm stringByAppendingFormat:@"%d",nosmiles]];
            });

        }
        
        
    }
    
    if (!statView.hidden) {
        
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            
            [self drawFaceBoxesForFeatures:features];
            
        });
        
    }

    dispatch_async(announcerQueue, ^{
        NSString* sm = @"Face_Smiley_";
        NSString* nosm = @"Face_";
        
        for (int i=1; i<=smiles; i++) {
            
            [recogNames setObject:@10 forKey:[sm stringByAppendingFormat:@"%d",i]];
            
        }
        for (int i=1; i<=nosmiles; i++) {
            
            [recogNames setObject:@10 forKey:[nosm stringByAppendingFormat:@"%d",i]];
        }
        
        
        for (int i=smiles+1; i<=maxSmiles; i++){
            
            [recogNames setObject:@0 forKey:[sm stringByAppendingFormat:@"%d",i]];
            
        }
        
        for (int i=nosmiles+1; i<=maxNoSmiles; i++) {
            
            [recogNames setObject:@0 forKey:[nosm stringByAppendingFormat:@"%d",i]];
        }
        
        maxSmiles = smiles;
        maxNoSmiles = nosmiles;
        
    });
    
}

#pragma mark - Dropbox Menu

- (IBAction)dropboxAction:(id)sender {
    
    firstInteraction = YES;
    
    //check if dropbox account already linked
    
    DBAccount* account = [[DBAccountManager sharedManager] linkedAccount];
    if (account) {
    
       
        [self actionSheetWithTitle:@"Dropbox Tasks" andItemNames:[NSArray arrayWithObjects:@"Load Predictor",@"Clear Predictor",@"Clear All", @"Unlink Account", nil] andAction:^(int i, NSString *name) {
            
            switch (i) {
                case 1://load predictor
                    
                    [self loadPredictorsMenu];
                    
                    break;
                    case 2:
                    
                    if (lastPredictionState == ePredicting) {
                        [self actionSheetWithTitle:@"Loaded Predictors" andItemNames:predictorNames andAction:^(int i, NSString *name) {
                            
                            [self clearPredictor:name];
                            
                            [self speak:[name stringByAppendingString:@" predictor cleared"] withVoice:manVoice];
                            
                        } fromSourceView:dropboxButton lastRed:NO];
                        
                        
                    } else {
                        
                        [self OKAlertWithTitle:@"Not Valid" andMessage:@"Predictors must be active to be cleared"];
                    }
                    
                    break;
                    
                    case 3:

                    if (lastPredictionState == ePredicting && predictors.count) {
                        
                        [self yesNoAlertWithTitle:@"Clear all predictors?" andAction:^{
                            
                            [self clearAllPredictors];
                            
                            [self speak:@"All predictors cleared" withVoice:manVoice];
                        }];
                        
                        
                    } else {
                        
                        [self OKAlertWithTitle:@"Not Valid" andMessage:@"Predictors must be active to be cleared"];
                    }

                    break;
                case 4:
                {
                    [self yesNoAlertWithTitle:@"Unlink Dropbox?" andAction:^{
                        
                        [self unlinkDropbox];
                    }];
                    
                    break;
                }
                    
                default:
                    
                    break;
            }
            
        } fromSourceView:dropboxButton lastRed:YES];
        
        
    } else{
        
            //link account
            [[DBAccountManager sharedManager] linkFromController:self];
        
    }
    
    
}

-(void) unlinkDropbox {
    
    //unlink dropbox
    [[[DBAccountManager sharedManager] linkedAccount] unlink];
    
    [self checkDropboxIcon];
    
}

#pragma mark - Selection

- (IBAction)tapAction:(id)sender {
    
    if (!paused) {
        
        CGPoint tap = [sender locationInView:self.view];
        
        //check if you tapped in the detected rect of a face
        __block CGRect faceRect;
        
        __block NSSet* faces;
        
        dispatch_sync(jobQueue, ^{
            
            faces = [fRects keysOfEntriesPassingTest: ^BOOL(id key, id obj, BOOL *stop) {
                
                faceRect = [obj CGRectValue];
                
                return CGRectContainsPoint(faceRect, tap);
                
            }];
            
        });
        
        
        if (faces.count) {
            
            [self popoverForFaces:faces atPoint:tap];
            
        } else {
            
            if (windowFlag) {
                //deselect
                windowFlag = NO;
                selectFlag = NO;
                selectFlag2 = NO;
                
                [activity stopAnimating];
                
                // remove layer
                [self removeLayersNamed:@"SelectLayer" fromLayer:previewLayer];
                [self removeLayersNamed:@"WindowLayer" fromLayer:previewLayer];
                
                
            } else if (predictionState != eWaiting) {
                
                //object selection
                
                float height = 300;
                float width = 300*1.3333;
                
                CGRect rect = CGRectMake(tap.x-width/2, tap.y-height/2, width, height);
                
                rect = [self keepRect:rect withinBounds:self.view.bounds];
                
                
                if (predictionState == ePredicting && predictors.count>0) {
                    
                    CALayer* selectLayer = [self addLayerNamed:@"SelectLayer" withImage:square2 toLayer:previewLayer];
                    selectLayer.hidden = statView.hidden;
                    [selectLayer setFrame:rect];
                    
                    [activity setFrame:rect];
                    [activity setBounds:CGRectMake(0, 0, 55, 55)];
                    
                    [activity startAnimating];
                    
                    selectFlag = YES;
                    
                } else {
                    
                    //learning
                    CALayer* selectLayer = [self addLayerNamed:@"WindowLayer" withImage:square2 toLayer:previewLayer];
                    [selectLayer setFrame:rect];
                    
                }
                
                selectRect = rect;
                
                windowFlag = YES;
                
            }
            
        }

        
    }
    
}

#pragma mark - Popover delegate

-(void)prepareForPopoverPresentation:(UIPopoverPresentationController *)popoverPresentationController{
    
    [self pauseFrameProcessing];
    
}


-(void)popoverPresentationControllerDidDismissPopover:(UIPopoverPresentationController *)popoverPresentationController{
    
    [self resumeFrameProcessing];
    
}

#pragma mark - Utils

-(void) checkDropboxIcon {
    
    //check if dropbox account already linked
    DBAccount* account = [[DBAccountManager sharedManager] linkedAccount];
    if (account) {
        
        //illuminate Dropbox icon
        [dropboxButton setImage:[UIImage imageNamed:@"Dropbox"] forState:UIControlStateNormal];
        
    } else {
        
        //shade Dropbox icon
        [dropboxButton setImage:[UIImage imageNamed:@"Dropbox_shade"] forState:UIControlStateNormal];
        
    }
    
}

-(void) OKAlertWithTitle:(NSString*) title andMessage:(NSString*) message{
    
    UIAlertController* OKAlert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    
    [OKAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        
        [self resumeFrameProcessing];
    }]];
    
    [self pauseFrameProcessing];
    
    [self presentViewController:OKAlert animated:YES completion:nil];

}

-(void) yesNoAlertWithTitle: (NSString*) title andAction:(void(^)(void))block {
    
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        
        [self resumeFrameProcessing];
        
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        
        if (block) {

            block();
            
        }

        
        [self resumeFrameProcessing];

    }]];
    
    [self presentViewController:alert animated:YES completion:^{
        
            [self pauseFrameProcessing];
        
    }];
    
    
}

-(void) dataEntryAlertWithTitle:(NSString*) title andMessage:(NSString*) message andTextFieldsPlaceholders:(NSArray*)placeholders andAction:(void (^)(NSArray* entries))block returnKeyName:(NSString*)returnName {
    
    UIAlertController* entryAlert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    
    for (NSString* ph in placeholders) {
        
        [entryAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            
            textField.placeholder = ph;
            //if it starts with a number show the Num Pad instead
            if([ph rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"]].location == 0){
                
                textField.keyboardType = UIKeyboardTypeNumberPad;
                
            }else {
                
                textField.keyboardType = UIKeyboardTypeASCIICapable;
            }
            
            textField.keyboardAppearance = UIKeyboardAppearanceAlert;
            
        }];
        
        
    }
    
    [entryAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        
        [self resumeFrameProcessing];
        
    }]];
    
    [entryAlert addAction:[UIAlertAction actionWithTitle:returnName style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        
        if (block) {

            block(entryAlert.textFields);
            
        }

        [self resumeFrameProcessing];
        
    }]];
    
    [self presentViewController:entryAlert animated:YES completion:^{
        
        [self pauseFrameProcessing];
    }];
    
    
}


-(void) actionSheetWithTitle:(NSString*)title andItemNames:(NSArray*)itemNames andAction:(void(^)(int i, NSString* name))block fromSourceView:(UIView*)sView lastRed:(bool)red {
    
    UIAlertController* sheet = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (NSString* name in itemNames) {
        
        if (red && [name isEqualToString:itemNames.lastObject]) {
            
            [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                
                if (block) {
                    
                    block((int)itemNames.count, name);
                }
                
            }]];
            
        } else {
            
            [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                
                int i = 1;
                
                for (NSString* task in itemNames) {
                    
                    if ([task isEqualToString:name]) {
                        if (block) {
                            
                            block(i, name);
                        }
                        
                        break;
                    }
                    
                    i++;
                }
                
            }]];
            
        }
        
    }
    
    [sheet setModalPresentationStyle:UIModalPresentationPopover];
    
    UIPopoverPresentationController *popPresenter = [sheet
                                                     popoverPresentationController];
    popPresenter.sourceView = sView;
    popPresenter.sourceRect = sView.bounds;
    
    popPresenter.delegate = self;
    
    [self presentViewController:sheet animated:YES completion:nil];
    
}

- (void) speak: (NSString*) words withVoice:(AVSpeechSynthesisVoice*)voice{
   
    if (soundFlag) {
        AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString: words];
        utterance.voice = voice;
        utterance.rate = 0.5*AVSpeechUtteranceDefaultSpeechRate;
        utterance.volume = 0.5;
        [synth speakUtterance:utterance];

    }
}

- (AVCaptureVideoOrientation) videoOrientationFor:(UIInterfaceOrientation)orientation {
    
    AVCaptureVideoOrientation vor;
    
    switch (orientation) {
        case UIInterfaceOrientationPortrait:
            vor = AVCaptureVideoOrientationPortrait;
            break;
        case UIInterfaceOrientationLandscapeRight:
            vor = AVCaptureVideoOrientationLandscapeRight;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            vor = AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            vor = AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        default:
            
            break;
    }
    
    return vor;
    
}

// find where the video box is positioned within the preview layer based on the video size and gravity
- (CGRect)videoPreviewBoxForGravity:(NSString *)gravity frameSize:(CGSize)frameSize apertureSize:(CGSize)apertureSize
{
    CGFloat apertureRatio = apertureSize.height / apertureSize.width;
    CGFloat viewRatio = frameSize.width / frameSize.height;
    
    CGSize size = CGSizeZero;
    if ([gravity isEqualToString:AVLayerVideoGravityResizeAspectFill]) {
        if (viewRatio > apertureRatio) {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        } else {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResizeAspect]) {
        if (viewRatio > apertureRatio) {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        } else {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResize]) {
        size.width = frameSize.width;
        size.height = frameSize.height;
    }
    
    CGRect videoBox;
    videoBox.size = size;
    if (size.width < frameSize.width)
        videoBox.origin.x = (frameSize.width - size.width) / 2;
    else
        videoBox.origin.x = (size.width - frameSize.width) / 2;
    
    if ( size.height < frameSize.height )
        videoBox.origin.y = (frameSize.height - size.height) / 2;
    else
        videoBox.origin.y = (size.height - frameSize.height) / 2;
    
    return videoBox;
}

-(void) createDropboxFileSystemForAccount: (DBAccount*) account {
    
    if (![DBFilesystem sharedFilesystem]) {
        
        DBFilesystem *filesystem = [[DBFilesystem alloc] initWithAccount:account];
        [DBFilesystem setSharedFilesystem:filesystem];
        
    }
    
}


-(CALayer*) addLayerNamed: (NSString*)layerName withImage:(UIImage*) image toLayer:(CALayer*)parentLayer{
    
    
    //remove previous layer
    [self removeLayersNamed:layerName fromLayer:parentLayer];
    
    CALayer *layer = nil;
    
    // create a new one
    layer = [CALayer new];
    [layer setContents:(id)[image CGImage]];
    [layer setName:layerName];
    [parentLayer addSublayer:layer];
    
    return layer;
}

-(void) removeLayersNamed: (NSString*)layerName fromLayer:(CALayer*) parentLayer {
    
    NSMutableArray* toBeRemoved = [NSMutableArray array];
    
    for ( CALayer *layer in parentLayer.sublayers ) {
        if ([[layer name] isEqualToString:layerName])
            [toBeRemoved addObject:layer];
    }
    
    for (CALayer* layer in toBeRemoved) {
        [layer removeFromSuperlayer];
    }

    
}

-(CGRect) keepRect:(CGRect)input withinBounds:(CGRect)bounds {
    
    CGRect output = CGRectMake(input.origin.x, input.origin.y, input.size.width, input.size.height);
    
    //keep in the bounds of the screen
    if (input.origin.x > bounds.size.width - input.size.width) {
        
        output.origin.x = bounds.size.width -input.size.width;
    }
    
    if (input.origin.x < 0) {
        output.origin.x = 0;
    }
    
    if (input.origin.y > bounds.size.height - input.size.height) {
        
        output.origin.y = bounds.size.height -input.size.height;
    }
    
    if (input.origin.y < 0) {
        output.origin.y = 0;
    }
    
    return output;
    
}


-(void) popoverForFaces:(NSSet*)faces atPoint:(CGPoint)tap{
    
    
    UIAlertController* selectAlert = [UIAlertController alertControllerWithTitle:@"Face" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (NSString* name in faces) {
        
        [selectAlert addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:nil]];
        
        [self speak:name withVoice:womanVoice];
    };
    
    [selectAlert setModalPresentationStyle:UIModalPresentationPopover];
    
    UIPopoverPresentationController *popPresenter = [selectAlert
                                                     popoverPresentationController];
    popPresenter.sourceView = self.view;
    popPresenter.sourceRect = CGRectMake(tap.x, tap.y, 1, 1);
    
    popPresenter.delegate = self;
    
    [self presentViewController:selectAlert animated:YES completion:nil];

}

-(void) popoverForObject:(NSString*)objectName atPoint:(CGPoint)tap{
    
    [self speak:objectName withVoice:womanVoice];
    
    //all tasks related to this object
    __block NSMutableArray* taskNames = [NSMutableArray array];
    [objectForTaskDict keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
        if ([obj isEqualToString:objectName]) {
            [taskNames addObject:key];
            return YES;
        } return NO;
    }];
    
    //anchor view for the popover
    [anchorView removeFromSuperview];
    anchorView = [[UIView alloc]initWithFrame:CGRectMake(tap.x, tap.y, 1, 1)];
    anchorView.hidden = YES;
    [self.view addSubview:anchorView];

    [taskNames addObject:@"Clear Predictor"];
    
    //action sheet with entry for each task
    [self actionSheetWithTitle:objectName andItemNames:taskNames andAction:^(int i, NSString *name) {
        
        if (i == (int)taskNames.count) {//the last action

            [self clearPredictor:objectName];
            
            return;
        }
        
        NSString* deviceName = [deviceForTaskDict objectForKey:name];
        
        for (YunConnect* yun in yunConnections) {
            
            if ([yun.host isEqualToString:deviceName]) {
                
                [yun sendMessage:[[yunTasks objectForKey:name] stringByAppendingString:@"\n"]];
            }
        }
        
    } fromSourceView:anchorView lastRed:YES];
    
    
}


-(void) pauseFrameProcessing {
    
    if (!paused) {
        
        paused = YES;
        
        [playPauseButton setAlpha:0.2];
        
        lastDetectFaces = detectFaces;
        lastPredictionState = predictionState;
        
        detectFaces = NO;
        predictionState = eWaiting;

    }
    
}

-(void) resumeFrameProcessing {
    
    detectFaces = lastDetectFaces;
    predictionState = lastPredictionState;
    [playPauseButton setAlpha:0.7];
    paused = NO;
    
}


#pragma mark - Audio


- (void) setupSound {
    // Create the URL for the source audio file.
    NSURL *soundUrl   = [[NSBundle mainBundle] URLForResource: @"ping"
                                                withExtension: @"wav"];
    
    /*
     self.soundFileURLRef = (__bridge CFURLRef) soundUrl;
     
     // Create a system sound object representing the sound file.
     AudioServicesCreateSystemSoundID (self.soundFileURLRef, &_soundFileObject);
     */
    
    pingPlayer = [[AVAudioPlayer alloc]initWithContentsOfURL:soundUrl error:nil];
    [pingPlayer setVolume:0.5];
    
    synth = [[AVSpeechSynthesizer alloc] init];
    
    manVoice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-gb"];
    womanVoice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-au"];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

        [self speak:@"Welcome to ID Labs." withVoice:womanVoice];
      
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(11 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

            if (! firstInteraction) {

                firstInteraction = YES;
                [self speak:@"When you're ready to teach the network, press the Learn button, and point your camera at the thing you want to recognize." withVoice:manVoice];
                
            }
            
        });
        
    });

}

#pragma mark - Yun


- (IBAction)yunAction:(id)sender {

    firstInteraction = YES;
    
    if (yunConnections.count < 1) {
        
        [self newYunAlert];
    
    }
    
    else { //show Menu

        [self actionSheetWithTitle:@"Yun Tasks" andItemNames:[NSArray arrayWithObjects:@"Instant Command", @"Add task", @"Remove task", @"Add Yun", @"Disconnect Yun", @"Disconnect All",nil] andAction:^(int i, NSString *name) {
            
            switch (i) {
               case 1:// instant command
                {
                    
                    NSMutableArray* dev = [NSMutableArray array];
                    for (YunConnect* y in yunConnections) {
                        
                        [dev addObject:y.host];
                        
                    }
                    
                    [self actionSheetWithTitle:@"Choose Yun" andItemNames:dev andAction:^(int i, NSString *name) {
                        
                        YunConnect* yun;
                        
                        for (YunConnect* y in yunConnections) {
                            
                            if ([name isEqualToString:y.host]) {
                                
                                yun = y;

                                break;
                            }
                        }
                        if (yun) {

                            NSString* st = @"To be sent to ";
                            [self dataEntryAlertWithTitle:@"Type the Command Line" andMessage:[st stringByAppendingString:name] andTextFieldsPlaceholders:[NSArray arrayWithObject:@"Hello Yun!"] andAction:^(NSArray *entries) {
                                UITextField* f = entries.firstObject;
                                
                                [yun sendMessage:[f.text stringByAppendingString:@"\n"]];
                                
                                
                            } returnKeyName:@"Send"];
                            
                            
                        }
                        
                    } fromSourceView:yunButton lastRed:NO];
                    
                }

                break;
                    
                case 2://add task
                {
                    
                    [self actionSheetWithTitle:@"Choose object" andItemNames:predictorNames andAction:^(int i, NSString *name) {
                        

                        __block NSString* objectName = name;


                        NSMutableArray* dev = [NSMutableArray array];
                        for (YunConnect* y in yunConnections) {
                            
                            [dev addObject:y.host];
                            
                        }
                        
                        [self actionSheetWithTitle:@"Choose Yun" andItemNames:dev andAction:^(int i, NSString *name) {
                            
                            __block NSString* deviceName = name;
                            
                            [self newTaskAlertWithCompletion:^(NSString *taskName) {
                                
                                //Now task is already added to YunTasks
                                
                                //Now you have an object, device, and task
                                [self OKAlertWithTitle:[taskName stringByAppendingString:@" Task"] andMessage:[NSString stringWithFormat:@"Running on (%@) device when (%@) is detected",[deviceName substringToIndex:[deviceName rangeOfString:@".local"].location],objectName]];
                               
                                //add to the three dictionaries
                                [objectForTaskDict setValue:objectName forKey:taskName];
                                [objectForDevDict setValue:objectName forKey:deviceName];
                                [deviceForTaskDict setValue:deviceName forKey:taskName];
                                
                                
                            }];
                            
                            
                        } fromSourceView:yunButton lastRed:NO];
                        
                    } fromSourceView:yunButton lastRed:NO];
                    

                }
                    
                break;
                    
                case 3://remove tasks
                {
                    
                    NSDictionary* taskDescript = [self getTaskDescriptions];

                    [self actionSheetWithTitle:@"Active Tasks" andItemNames: [taskDescript allKeys] andAction:^(int i, NSString *name) {
                        
                        __block NSString* taskName = [taskDescript objectForKey:name];
                        
                        [self yesNoAlertWithTitle:[NSString stringWithFormat:@"Remove %@ task?",taskName] andAction:^{
                           
                            //remove from yunTasks
                            [yunTasks removeObjectForKey:taskName];
                            
                            NSString* deviceName = [deviceForTaskDict objectForKey:taskName];
                            
                            //remove from the 3 dictionaries
                            [objectForTaskDict removeObjectForKey:taskName];
                            [objectForDevDict removeObjectForKey:deviceName];
                            [deviceForTaskDict removeObjectForKey:taskName];
                            
                            [self speak:[NSString stringWithFormat:@"%@ task removed", taskName] withVoice:womanVoice];
                            
                        }];
                        
                        
                    } fromSourceView:yunButton lastRed:NO];
                
                }

                break;
                    
                case 4: //add a Yun
                {
                    [self newYunAlert];
                
                }
                
                break;
                
                case 5: //disconnect a Yun
                {
                    NSMutableArray* dev = [NSMutableArray array];
                    for (YunConnect* y in yunConnections) {
                        
                        [dev addObject:y.host];
                        
                    }
                    [self actionSheetWithTitle:@"Connected Yuns" andItemNames:dev andAction:^(int i, NSString *name) {
                        
                        NSString* st = @"Disconnect ";
                        [self yesNoAlertWithTitle:[st stringByAppendingString:name] andAction:^{
                            
                            NSMutableArray* toBeDisconnected = [NSMutableArray array];
                            
                            for (YunConnect* y in yunConnections) {
                                
                                if ([name isEqualToString:y.host]) {
                                    
                                    [toBeDisconnected addObject:y];

                                }
                                
                            }
                            
                            for (YunConnect* y in toBeDisconnected) {
                            
                                [self removeYunConnection:y];
                                [yunConnections removeObject:y];
                                
                            }
                            
                            if (yunConnections.count<1) {
                                
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    
                                    [yunButton setImage:[UIImage imageNamed:@"Yun_shade"] forState:UIControlStateNormal];
                                });
                                
                            }
                            
                        }];
                        
                    } fromSourceView:yunButton lastRed:NO];
                }

                break;

                case 6://disconnect all
                {
                    [self yesNoAlertWithTitle:@"Disconnect all Yun?" andAction:^{
                        
                        [self disconnectAllYun];
                        
                    }];
                    
                    
                }
                    
                break;
                    
                default:
                break;
            }
            
        } fromSourceView:yunButton lastRed:YES];
        
    }

}

-(void) removeYunConnection:(YunConnect*)yun {
    
    [yun disconnect];
    
    //remove from dicts
    NSString* deviceName = yun.host;
    [objectForDevDict removeObjectForKey:deviceName];//1

    __block  NSMutableArray* names = [NSMutableArray array];//get names of all tasks running on that device
    [deviceForTaskDict keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
        if ([obj isEqualToString:deviceName]) {//all tasks running on this device
            [names addObject:key];
            return YES;
        }
        return NO;
    }];

    for (NSString* taskName in names) {
        
        [yunTasks removeObjectForKey:taskName];//0
        [deviceForTaskDict removeObjectForKey:taskName];//2
        [objectForTaskDict removeObjectForKey:taskName];//3
        
    }
    
}

-(NSDictionary*) getTaskDescriptions {
    
    //mesh the three dictionaries together.

    NSMutableDictionary* taskDescript = [NSMutableDictionary dictionary];
    
    //loop all tasks
    for (NSString* taskName in [yunTasks allKeys]) {

        //1 task running on 1 device for 1 object
        NSString* objectName = [objectForTaskDict objectForKey:taskName];
        NSString* deviceName = [deviceForTaskDict objectForKey:taskName];
        
        NSString* entry = [taskName stringByAppendingFormat:@": on (%@) for (%@)",[deviceName substringToIndex:[deviceName rangeOfString:@".local"].location] ,objectName];
        [taskDescript setObject:taskName forKey:entry];
        
    }

    return taskDescript;
}

-(void) newYunAlert {
    
    [self dataEntryAlertWithTitle:@"Connect to Yun" andMessage:@"Enter Yun address, username and password" andTextFieldsPlaceholders:[NSArray arrayWithObjects: @"yun1.local", @"root", @"arduino", nil] andAction:^(NSArray *entries) {
        
        UITextField* f1 = [entries objectAtIndex:0];
        
        NSString* hostIP;
        
        if(f1.text.length>0) {
            
            hostIP = f1.text;
            
        } else {
            
            hostIP = [NSString stringWithFormat:@"yun1.local"];
            
        }
        
        bool new = true;
        //make sure it's not a duplicate
        
        NSMutableArray* dev = [NSMutableArray array];
        for (YunConnect* y in yunConnections) {
            
            [dev addObject:y.host];
            
        }
        
        for (NSString* d in dev) {
            
            if ([d isEqualToString:hostIP]) {
                
                new = false;
            }
            
        }
        
        if (new) {
            
            UITextField* f2 = [entries objectAtIndex:1];
            
            NSString* username;
            
            if(f2.text.length>0) {
                
                username = f2.text;
                
            } else {
                
                username = [NSString stringWithFormat:@"root"];
                
            }
            
            UITextField* f3 = [entries objectAtIndex:2];
            
            NSString* password;
            
            if(f3.text.length>0) {
                
                password = f3.text;
                
            } else {
                
                password = [NSString stringWithFormat:@"arduino"];
                
            }
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                
                YunConnect* yun = [[YunConnect alloc]initWithUser:username andPassword:password];
                
                yun.delegate = self;
                
                [yun connectToHost:hostIP];
                
                if (yun.connected) {
                    
                    [yunConnections addObject:yun];
                }
            
                
            });
            
        } else {
            
            [self OKAlertWithTitle:@"This Yun is already connected!" andMessage:@"try another one"];
            
        }
        
        
    } returnKeyName:@"Connect"];
    
}


-(void) newTaskAlertWithCompletion:(void(^)(NSString* taskName)) block {
    
    [self dataEntryAlertWithTitle:@"Add task" andMessage:@"Enter Task Name and Yun Command" andTextFieldsPlaceholders:[NSArray arrayWithObjects:@"<random task>",@"Hello Yun!", nil] andAction:^(NSArray *entries) {
        
        UITextField* f1 = [entries objectAtIndex:0];
        
        NSString* taskName;
        
        if(f1.text.length>0) {
            
            taskName = f1.text;
            
        } else {
            
            taskName = [NSString stringWithFormat:@"Task_%d",arc4random()%1000];
            
        }
        
        bool new = true;
        //make sure it's not a duplicate
        for (NSString* t in [yunTasks allKeys]) {
            
            if ([t isEqualToString:taskName]) {
                
                new = false;
            }
            
        }
        
        if (new) {
            
            UITextField* f2 = [entries objectAtIndex:1];
            
            NSString* commandLine;
            
            if(f2.text.length>0) {
                
                commandLine = f2.text;
                
            } else {
                
                commandLine = @"Hello Yun!";
                
            }
            
            //add new task
            [yunTasks setObject:commandLine forKey:taskName];
            [self speak:[taskName stringByAppendingString:@" task added"] withVoice:womanVoice];
            
            if (block) {
                
                block(taskName);
            }

            
            
        } else {
            
            [self OKAlertWithTitle:@"This name is already used !" andMessage:@"try another one"];
        }
        
        
    } returnKeyName:@"Add"];
    

}

-(void) disconnectAllYun {
    
    for (YunConnect* yun in yunConnections) {
        
        [self removeYunConnection:yun];
        
    }
    
    [yunConnections removeAllObjects];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [yunButton setImage:[UIImage imageNamed:@"Yun_shade"] forState:UIControlStateNormal];
    });

    
}

#pragma mark - YunConnect delegate
-(void)YunDidConnect:(YunConnect *)connection{
    
    [yunButton setImage:[UIImage imageNamed:@"Yun"] forState:UIControlStateNormal];
    //NSString* log = @"Connected to ";
    //NSLog([log stringByAppendingString:connection.host]);
    
    [self speak:@"Yun connected" withVoice:womanVoice];
    
}

-(void)YunFailedToConnect:(YunConnect *)connection{

    [self speak:@"Yun failed to connect" withVoice:womanVoice];
    
}

-(void)YunConnect:(YunConnect *)connection didReceiveMessage:(NSString *)message fromSide:(bool)side {

    //NSLog(message);
    
}

-(void)YunDidDisconnect:(YunConnect *)connection{
    
    //NSString* log = @"Disconneced from ";
    //NSLog([log stringByAppendingString:connection.host]);
    
    [self speak:@"Yun disconnected" withVoice:womanVoice];
    
}



#pragma mark -

-(void)didReceiveMemoryWarning{
    
    /*
    warningCount++;
    
    if (warningCount>1) {

        [self pauseFrameProcessing];
        [self presentViewController:[UIAlertController alertControllerWithTitle:@"Memory Warning" message:@"Pausing for a moment..." preferredStyle:UIAlertControllerStyleAlert] animated:YES completion:^{
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                
                [self dismissViewControllerAnimated:YES completion:^{
                    
                    [self resumeFrameProcessing];
                }];
            });
        }];

        
        warningCount =0;
    } else {
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            
            warningCount--;
        });

    }
    
     */
    
}

- (void)dealloc
{
    [self teardownAVCapture];
    

}


@end
