# Eye|lLearn
Visual object recognition on iOS for contextual home automation using Arduino Yun.

### Initial TODO

“Build an AR iOS App that recognises a controllable object in the video feed from camera, then presents relevant UI to the user and establishes a wireless connection with the embedded system in the object. The connection is to send control signals from the App and receive state data to present to the user. The embedded system should be capable of driving mechanical elements (e.g. DC motors) in the object.”

###Basic Determinations:
- **Object Recognition technique:** Deep Learning 
-> [Convolutional Neural Networks]
- **Accessible Solution for CNN:** Jetpac's [DeepBeliefSDK]
- **Embedded System:** [Arduino Yun]
- **Wireless Technology:** WiFi -> Secure Shell -> [NMSSH]



[DeepBeliefSDK]:https://github.com/jetpacapp/DeepBeliefSDK
[Convolutional Neural Networks]:http://www.cs.toronto.edu/~fritz/absps/imagenet.pdf
[Arduino Yun]:http://www.arduino.cc/en/Main/ArduinoBoardYun?from=Products.ArduinoYUN
[NMSSH]:https://github.com/Lejdborg/NMSSH
