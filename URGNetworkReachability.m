/*
 Created by antonio on 21.07.12.
 
 Copyright (c) 2012, Anton Dobkin. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 
 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.
 
 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE. 
 */

#import <sys/socket.h>
#import <netinet/in.h>
#import <netinet6/in6.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>

#import <CoreFoundation/CoreFoundation.h>
#import "URGNetworkReachability.h"

#if (!defined(__clang__) || __clang_major__ < 3) && !defined(__bridge)
    #define __bridge
#endif

#if __has_feature(objc_arc)
    #define URG_MEM_AUTORELEASE(obj) (obj);
    #define URG_MEM_SUPER_DEALLOC
    #define URG_MEM_AUTORELEASE_POOL_START @autoreleasepool {
    #define URG_MEM_AUTORELEASE_POOL_END }
    #define URG_PROPERTY_RETAIN strong
#else
    #define URG_MEM_AUTORELEASE(obj) ([(obj) autorelease]);
    #define URG_MEM_SUPER_DEALLOC ([super dealloc]);
    #define URG_MEM_AUTORELEASE_POOL_START NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    #define URG_MEM_AUTORELEASE_POOL_END [pool release];
    #define URG_PROPERTY_RETAIN retain
#endif

#define INIT_SOCKADDR_IN(addr) \
    do { \
        size_t addr_len = sizeof(addr);\
        memset(&addr, 0, addr_len); \
        addr.sin_len = addr_len; \
        addr.uin_family = AF_INET; \
    } while(0);


NSString *const URGNetworkReachabilityChangedNotification = @"URGNetworkReachabilityChangedNotification";

static void _URGNetworkReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info) {
#pragma unused (target, flags)
    URGNetworkReachability *reach = (__bridge URGNetworkReachability *) info;
    URG_MEM_AUTORELEASE_POOL_START
        [reach reachabilityChanged];
    URG_MEM_AUTORELEASE_POOL_END
}

@interface URGNetworkReachability()
@property (nonatomic, URG_PROPERTY_RETAIN) id reachabilityObject;
@end

@implementation URGNetworkReachability

@synthesize reachabilityChangedBlock;
@synthesize reachabilityObject;
@synthesize hostName = _hostName;

-(id)initWithHostName: (NSString *) name {
    self = [super init];
    if(self) {
        SCNetworkReachabilityRef reachabilityRef = nil;
        if(name) {
            reachabilityRef = SCNetworkReachabilityCreateWithName(NULL, [name UTF8String]);
        } else {
            struct sockaddr_in address;
            INIT_SOCKADDR_IN(address)
            reachabilityRef = SCNetworkReachabilityCreateWithAddress(NULL, (const struct sockaddr*)&address);
        }
        if(!reachabilityRef) {
            return nil;
        }
        _reachabilityRef = reachabilityRef;
        _hostName = [name copy];
    }
    return self;
}

-(id) init {
    return [self initWithHostName:nil];
}

+(URGNetworkReachability *) reachabilityWithHostName: (NSString *)name {
    return URG_MEM_AUTORELEASE([[URGNetworkReachability alloc] initWithHostName:name]);
}

+(URGNetworkReachability *) reachability {
    return URG_MEM_AUTORELEASE([[URGNetworkReachability alloc] initWithHostName:nil]);
}

+(URGNetworkReachability *) sharedInstance {
    static URGNetworkReachability *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        if (_sharedInstance == nil){
            _sharedInstance = [[URGNetworkReachability alloc] initWithHostName:nil];
        }
    });
    
    return _sharedInstance;
}

-(void)startNofifier {
    SCNetworkReachabilityContext context = { 0, (__bridge void *)(self), NULL, NULL, NULL};
    if(SCNetworkReachabilitySetCallback(_reachabilityRef, _URGNetworkReachabilityCallback, &context)) {
        self.reachabilityObject = self;
        SCNetworkReachabilityScheduleWithRunLoop(_reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        _notifierStarted = YES;
    }
}

-(void)stopNotifier {
    if(_reachabilityRef) {
        SCNetworkReachabilityUnscheduleFromRunLoop(_reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    }
    self.reachabilityObject = nil;
    _notifierStarted = NO;
}

-(BOOL) isReacheble {
    if (_reachabilityRef != NULL) {
        SCNetworkReachabilityFlags flags = 0;
        if(SCNetworkReachabilityGetFlags(_reachabilityRef, &flags)){
            BOOL isReachable = ((flags & kSCNetworkFlagsReachable) != 0);
            BOOL connectionRequired = ((flags & kSCNetworkFlagsConnectionRequired) != 0);
            return (isReachable && !connectionRequired) ? YES : NO;
        }
    }
    return NO;
}

-(void) dealloc {
    [self stopNotifier];
    if(_reachabilityRef != NULL) {
        CFRelease(_reachabilityRef);
        _reachabilityRef = NULL;
    }
    URG_MEM_RELEASE(_hostname)
    URG_MEM_SUPER_DEALLOC
}

-(NSInteger) currentStatus {
    SCNetworkReachabilityFlags flags;
    NSInteger status = URGNetworkStatusNotReachable;
    
    Boolean ret = SCNetworkReachabilityGetFlags(_reachabilityRef, &flags);
    
    if(ret && [self isReacheble]) {
        if((flags & kSCNetworkReachabilityFlagsIsWWAN)) {
            status = URGNetworkStatusReachableViaCellular;
        } else {
            status = URGNetworkStatusReachableViaWiFi;
        }
    }
    return status;
}

-(void) reachabilityChanged {
    if(self.reachabilityChangedBlock) {
        self.reachabilityChangedBlock(self);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:URGNetworkReachabilityChangedNotification
                                                            object:self];
    });
}

-(BOOL) isReachebleViaWiFi {
    return [self currentStatus] == URGNetworkStatusReachableViaWiFi;
}

-(BOOL) isReachebleViaCellular {
    return [self currentStatus] == URGNetworkStatusReachableViaCellular;
}

@end
