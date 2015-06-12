//
//  YunConnect.h
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

#import <Foundation/Foundation.h>

@protocol YunConnectDelegate;

@interface YunConnect : NSObject

@property (nonatomic, weak) id<YunConnectDelegate> delegate;
@property  NSString* host;
@property (readonly) bool connected;

-(instancetype)initWithUser:(NSString*)u andPassword:(NSString*)p;

-(void) connectToHost:(NSString*)h;
-(void) disconnect;

-(void) sendMessage:(NSString*)m;


@end


@protocol YunConnectDelegate <NSObject>

-(void) YunDidConnect:(YunConnect*)connection;
-(void) YunFailedToConnect:(YunConnect*)connection;
-(void) YunConnect:(YunConnect*)connection didReceiveMessage:(NSString*)message fromSide:(bool)side; //side 0:me 1:Yun
-(void) YunDidDisconnect:(YunConnect *)connection;



@end