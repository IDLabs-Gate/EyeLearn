#include <Console.h>
#include <Stepper.h>

int in1Pin = 12;
int in2Pin = 11;
int in3Pin = 10;
int in4Pin = 9;

String message;

Stepper motor(768,in1Pin,in2Pin,in3Pin,in4Pin);

void setup() 
{
    Bridge.begin();
    Console.begin();

    while(!Console);
    
    Console.println("You are connected to the Console!");
    
    pinMode(in1Pin,OUTPUT);
    pinMode(in2Pin,OUTPUT);
    pinMode(in3Pin,OUTPUT);
    pinMode(in4Pin,OUTPUT);
    
    motor.setSpeed(20);
    
}

void loop() 
{

    while (Console.available())
    {
        char c = Console.read();
        
        if(c == '\n') {
         //complete message has been read in "message", respond!

         if (message.length() > 0) {

            //do something
            int steps = message.toInt();
            motor.step(steps);

            delay(1000);
            
         }

          message = ""; //clear
        }
        else {
         
         message += c; //append
          
        }
        
    }
  
    
}

