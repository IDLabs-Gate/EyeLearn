# Eye|lLearn
Visual object recognition on iOS for contextual home automation using Arduino Yun.

![Eye] (https://github.com/IDLabs-Gate/EyeLearn/blob/master/Eye.png)

### Initial TODO

“Build an AR iOS App that recognises a controllable object in the video feed from camera, then presents relevant UI to the user and establishes a wireless connection with the embedded system in the object. The connection is to send control signals from the App and receive state data to present to the user. The embedded system should be capable of driving mechanical elements (e.g. DC motors) in the object.”

###Basic Determinations:
- **Object Recognition technique:** Deep Learning 
-> [Convolutional Neural Networks]
- **Accessible Solution for CNN:** Jetpac's [DeepBeliefSDK]
- **Embedded System:** [Arduino Yun]
- **Wireless Technology:** WiFi -> Secure Shell -> [NMSSH]

###EyeLearn Xcode project:

##### Main file: TrainViewController.m

####Include DeepBelief header
Using the SDK for Jetpac’s Deep Belief image recognition framework, a network object is created by jpcnn_create_network( ) based on the pre-trained network in the attached jetpac.ntwk file. Initial classification is carried out by jpcnn_classify_image( ) on the penultimate layer of the network to extract a set of 4096 features of each processed image. These features are then fed into a support vector machine (SVM) that we train using jpcnn_train( ) to differentiate between our custom objects and predict the captured object, and the final decision is made through a simple decision making logic stage.

####Camera capture using AVFoundation classes -> setupAVCapture: method
Source images are captured by the iOS device video camera. First an AVCaptureSession is initialised to use an AVCaptureDevice via an AVCaptureConnection. Captured frames are periodically passed as a parameter to captureOutput: didOutputSampleBuffer: method.
An AVCaptureVideoPreviewLayer  is also added to the background to display the video feed to the user for interaction purposes, thus the augmented reality nature of the App.

####Frames obtained in captureOutput: didOutputSampleBuffer: method 
the passed sample buffer needs to be accessed by CMSampleBufferGetImageBuffer( ) to get the pixel buffer. A Core Image CIImage is then initialised with the data to under go further editing before entering the classification stage.
A state machine is used to decide which course of action to take with the Core Image according to the current state of the program, whether in prediction mode or training mode or otherwise, and whether Face detection option is activated.
Preprocessing and classification is carried out in a global dispatch queue of high priority, it has a simple boolean lock to prevent issuing another block until the one at hand finishes off. Processing can go mainly into routes: runAlgorithmOnFrame: and runFaceDetectionOnFram:

####runAlgorithmOnFrame: 
This is the collective preprocessing, training, and prediction of periodically captured images containing objects to be recognised. First a series of dimensionality and orientation modifications are applied to the CIImage in order to yield a 230x230 square out of the rectangular video frame to be used as the input to the Jetpac classifier: the first of these is applying a selection window if user had tapped into certain part of the screen, extracting the required part of the image into a CGImage before encapsulating it back into a CIImage. Then a warping process is applied via a CIFilter with name: CILanczosScaleTransform, which convert the windowed rectangle into a square of correction dimensions. After that a CIFilter with name: CIStraightenFilter is applied to rotate the image appropriately to match AVCaptureVideoOrientation with the required orientation of the device. A thumbnail preview of the resulting image is sent to a UIImageView for the user to monitor the exact input to the classifier in analysis mode of the App.
Finally a CVPixelBuffer is rendered out of the square image, and is used to create a compatible image buffer for the use of classifier by jpcnn_create_image_buffer_from_uint8_data. The output of the classifier is used according to the current state of the program in either training the SVM or recognising a new object.

####runFaceDetectionOnFrame:
The frame image can optionally be used to detect faces present in the video feed and draw squares around them. Features like smiles can be detected too. A CIDetector of type CIDetectorTypeFace is initialised and used to extract an array of CIFaceFeature features out of the rectangular frame image. These features are then traversed to get the rectangles of the image in which they are located and to check for specific features like smiles. Red CGRects are then set to be drawn at these locations and a recog_name is registered for a “Face” or a “Face_Smiley”.

####Performance measures
Execution times for many of the above mentioned processes are measured as NSTimeIntervals. CNN time for convolutional network classifier execution time, SVM time for the prediction time of custom classes, Face time for face features extraction, and warp time for the pre-processing of warping the rectangular frame image into a square. Average time on A5 chip (iPad2, iPad mini1) was 2.3, 0.01, 0.1, and 0.17 sec in order. The CNN time extends by about 1 sec more if running simultaneously with Face detection. These times are expected to be much less on A7 chip and later for the classifier is reported to take around 0.3 sec instead of 2.3 on iPhone 5S.

####Multitarget recognition -> SVM
The jetpac implementation for SVM was partially bypassed in order to accommodate for simultaneous multi target training and prediction. It retains the Yes/No 2 classes for each training example, but allows to save the resulting predictor in device by savePredictor: toFileNamed: and run predictions on multiple of them each frame.

####Dropbox Integration -> Save/Load predictors
Saved SVM predictors are automatically synced to Dropbox account storage, and can be loaded later on to be added to the list of predictors checked each frame via simple user interface. In analysis mode each predictor is displayed at the top of the screen with a progress bar displaying the probability for the associated object to be present on the latest frame.

####Tap Action Selection -> Window 
When the user tap on the screen the tapAciton: method draws a 300x300*1.33 rectangle around his finger and extract the corresponding window from the video feed to be the only one used in classification algorithm. The tap triggers a decision making to identify the object in the selection window and the result is displayed in a popover from the tap point that carries the name of the object and a list of saved tasks related to it that can be chosen to control the object using Arduino Yun devices.

####Video Orientation 
The Face detector needs to correctly know the orientation of the captured image in order to correctly extract face features. The App has a fixed orientation of Landscape-Right, and the matching setting with it is to set the CIDetectorImageOrientation in the options dictionary of the featuresInImge: options: method to the integer ( 6 ) which denotes the enum value: PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP

####YunConnect -> NMSSH
The SSH ObjC library NMSSH is used to establish a connection via WiFi with possible multiple Arduino Yun devices and open a telnet chat session with them. A simplified user interface encapsulates these chat sessions into tasks that are stored in correspondence to certain Yun device in a certain object. When an object is tapped and a corresponding Yun device is connected to the App, a popover appears with all stored tasks that can be executed in that device.

![Control] (https://github.com/IDLabs-Gate/EyeLearn/blob/master/control_pic.png)


[DeepBeliefSDK]:https://github.com/jetpacapp/DeepBeliefSDK
[Convolutional Neural Networks]:http://www.cs.toronto.edu/~fritz/absps/imagenet.pdf
[Arduino Yun]:http://www.arduino.cc/en/Main/ArduinoBoardYun?from=Products.ArduinoYUN
[NMSSH]:https://github.com/Lejdborg/NMSSH

