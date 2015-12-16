//
//  SDAFParseAPIClient.m
//  immortalsantee@me.com
//
//  Created by Santosh Maharjan on 7/16/15.
//  Copyright (c) 2015 Santosh Maharjan. All rights reserved.
//  https://github.com/immortalsantee/SyncEngine

#import "SDAFParseAPIClient.h"

@implementation SDAFParseAPIClient


+ (SDAFParseAPIClient *)sharedClient {
    static SDAFParseAPIClient *sharedClient = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedClient = [[SDAFParseAPIClient alloc] init];
    });
    
    return sharedClient;
}


- (AFHTTPRequestOperation *)POSTRequestForClass:(NSString *)className
                                    APIBasedURL:(NSString *)URL
                                     parameters:(NSDictionary *)parameters
                                        success:(SuccessBlockType)success
                                        failure:(FailureBlockType)failure{
    
    AFHTTPRequestOperation *operation = [self POST:URL parameters:parameters success:success failure:failure];
    return operation;
}


- (AFHTTPRequestOperation *)POSTRequestForClass:(NSString *)className
                                    APIBasedURL:(NSString *)URL
                                     parameters:(NSDictionary *)parameters
                                       formData:(formData)formdata
                                        success:(SuccessBlockType)success
                                        failure:(FailureBlockType)failure{
    
    AFHTTPRequestOperation *operation = [self POST:URL parameters:parameters constructingBodyWithBlock:formdata success:success failure:failure];
    return operation;
}


@end