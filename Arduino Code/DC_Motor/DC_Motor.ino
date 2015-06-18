#include <Console.h>

const int motorPin = 3;

String message;

void setup() 
{
    
    Bridge.begin();
    Console.begin();

    while(!Console);
    
    Console.println("You are connected to the Console!");
    
    pinMode(motorPin, OUTPUT);
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
            int speed = message.toInt();

            if (speed >= 0 && speed <= 255)
            {
                analogWrite(motorPin, speed);
                delay(100);
            }
            
         }

          message = ""; //clear
        }
        else {
         
         message += c; //append
          
        }
        
    }
  
    
}
