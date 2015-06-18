#include <Console.h>

const int ledPin = 13;

String message;

void setup() 
{
    
    Bridge.begin();
    Console.begin();

    while(!Console);
    
    Console.println("You are connected to the Console!");
    
    pinMode(ledPin,OUTPUT);
}

void loop() 
{

    while (Console.available())
    {
        char c = Console.read();
        
        if(c == '\n') {
         //complete message has been read in "message", respond!

         if (message.length() > 0) {
           
             Console.print("I received < ");
             Console.print(message);
             Console.println(" > from you."); //println to complete response
         }

          if (message == "high")
              digitalWrite(ledPin, HIGH);
              
          if (message == "low")
              digitalWrite(ledPin, LOW);
              
          message = ""; //clear
        }
        else {
         
         message += c; //append
          
        }
        
    }
  
    
}
