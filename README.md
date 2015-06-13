# EyeLearn
Visual object recognition on iOS for contextual home automation using Arduino Yun.

### Initial TODO

“Build an AR iOS App that recognises a controllable object in the video feed from camera, then presents relevant UI to the user and establishes a wireless connection with the embedded system in the object. The connection is to send control signals from the App and receive state data to present to the user. The embedded system should be capable of driving mechanical elements (e.g. DC motors) in the object.”

#####Tasks involved
<( ) dependent on , < >( ) inter-dependent 

- 1> Jumpstart AR on iOS. 
- 2> Suppose the initial set of controls/states and build its UI overlay. 
- 3> Determine object/mark recognition technique to be used, search for accessible solutions. 
- 4> Implement and test the visual recognition technique on target object(s) <( 3 ) 
- 5> Determine the kind of embedded system to wirelessly communicate with iOS devices while driving mechanical elements < >( 6, 7 ) 
- 6> Determine wireless technology to connect the iOS device and the embedded system, securing necessary hardware/frameworks support on both sides < >( 5 ) 
- 7> Determine the mechanical elements to be used and match their power/control requirements to the embedded system < >( 5 ) 
- 8> Order the required hardware/software <( 5,6,7 ). 
- 9> Jumpstart the embedded system kit, secure/implement any additional circuitry required for operation <( 8 ) 
- 10> Set-up and test the wireless connection <( 8,9 ) 
- 11> Set-up and test the mechanical interface <( 8,9 ) 
- 12> Revisit the set of controls/states and tweak its UI overlay <( all ) 
- 13> Connect and test the whole system <( all ) 

###Basic Determinations:
- Object Recognition technique: Deep Learning 
-> [Convolutional Neural Networks]
- Accessible Solution for CNN: Jetpac's [DeepBeliefSDK]
- Embedded System: [Arduino Yun]
- Wireless Technology: WiFi -> Secure Shell -> [NMSSH]



[DeepBeliefSDK]:https://github.com/jetpacapp/DeepBeliefSDK
[Convolutional Neural Networks]:http://www.cs.toronto.edu/~fritz/absps/imagenet.pdf
[Arduino Yun]:http://www.arduino.cc/en/Main/ArduinoBoardYun?from=Products.ArduinoYUN
[NMSSH]:https://github.com/Lejdborg/NMSSH
