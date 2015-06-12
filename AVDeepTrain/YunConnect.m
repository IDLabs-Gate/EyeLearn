//
//  YunConnect.m
//  YunConnect
//
//  Created by Muhammad Hilal on 4/23/15.
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

#import "YunConnect.h"
#import "NMSSH.h"

static NSString* const DEFAULT_USER = @"root";
static NSString* const DEFAULT_PASSWORD = @"arduino";
static NSString* const TELNET_COMMAND = @"telnet localhost 6571\r\n";

@interface YunConnect () <NMSSHSessionDelegate, NMSSHChannelDelegate>

{
    NMSSHSession* session;
    NMSSHChannel* channel;
    
    NSString* buffer;
    
    NSString* username;
    NSString* password;
    
    dispatch_queue_t serialQueue;
 
    NSString* lastMessage;
}


@end


@implementation YunConnect
@synthesize connected = _connected;

-(instancetype)init{
    
    return [self initWithUser:DEFAULT_USER andPassword:DEFAULT_PASSWORD];
}

-(instancetype)initWithUser:(NSString *)u andPassword:(NSString *)p{
    
    self = [super init];
    
    username = u;
    password = p;
    
    _connected = NO;
    
    serialQueue = dispatch_queue_create("NMSSH_Queue", DISPATCH_QUEUE_SERIAL);
    
    buffer = [NSString string];
    
    return self;
}

-(void)connectToHost:(NSString *)h{
    
    if (!_connected) {
        
        self.host = h;
        session = [NMSSHSession connectToHost:h withUsername:username];
        session.delegate = self;
        
        if (session.isConnected) {
            
            //sync
            dispatch_sync(serialQueue, ^{
                
                [session authenticateByPassword:password];
                
                if (session.isAuthorized) {
                    
                    channel = [[NMSSHChannel alloc]initWithSession:session];
                    channel.requestPty = YES;
                    
                    NSError* error =nil;
                    
                    [channel startShell:&error];
                    sleep(2);
                    
                    [channel write:TELNET_COMMAND error:&error];
                    sleep(1);
                    
                    channel.delegate = self;
                    
                    _connected = YES;
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        
                        [self.delegate YunDidConnect:self];
                    });
                    
                }
            });
     
        }
        
    }
    
    if (!_connected) {//still
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [self.delegate YunFailedToConnect:self];
            
        });
        
    }

    
}

-(void)disconnect{
    
    if (_connected) {
        
        dispatch_sync(serialQueue, ^{
            
            [channel closeShell];
            [session disconnect];
            
            _connected = NO;
            
        });
        
        dispatch_async(dispatch_get_main_queue(), ^{

            [self.delegate YunDidDisconnect:self];
            
        });

    }
}

-(void)sendMessage:(NSString *)m {
    
    if (_connected) {
        
        dispatch_async(serialQueue, ^{

            NSError* error = nil;
            
            [channel write:m error:&error];
            
            lastMessage = [m stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];;
            
        });
    }
}

#pragma mark - Channel Delegate

-(void)channelShellDidClose:(NMSSHChannel *)channel{
    
    
}

-(void)channel:(NMSSHChannel *)channel didReadData:(NSString *)message{
   
    dispatch_async(serialQueue, ^{
        
            NSRange range = [message rangeOfString:@"\n"];
            if (range.length == 0) {//no end of line
                buffer = [buffer stringByAppendingString:message];
            }
            else {
                
                buffer = [buffer stringByAppendingString:[message substringToIndex:range.location]];
                
                NSString* text = [buffer stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
                
                //reset buffer
                buffer = [NSString string];
                
                //check which side sent this message
                bool side = true;
                
                NSString* m = [message stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
                
                if ([m isEqualToString:lastMessage]) {//It's my message
                    //randomize lastMessage
                    lastMessage = [NSString stringWithFormat:@"%d",arc4random()%1000];
                    side = false;
                }
                
                if (text.length) {
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        
                        [self.delegate YunConnect:self didReceiveMessage:text fromSide:side];
                    });

                    
                }
                
            }
            
        
        
    });
    
}

@end
