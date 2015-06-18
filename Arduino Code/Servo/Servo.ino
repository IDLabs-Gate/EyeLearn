#include <Console.h>
#include <Servo.h>

const int servoPin = 9;

String message;

Servo servo;

void setup() 
{
    Bridge.begin();
    Console.begin();

    while(!Console);
    
    Console.println("You are connected to the Console!");
    
    servo.attach(servoPin);
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
            int angle = message.toInt();

            if (angle >= 0 && angle <= 180)
            {
                servo.write(angle);
                delay(1000);
            }
            
         }

          message = ""; //clear
        }
        else {
         
         message += c; //append
          
        }
        
    }
  
    
}
