//
//  SDAFParseAPIClient.h
//  immortalsantee@me.com
//
//  Created by Santosh Maharjan on 7/16/15.
//  Copyright (c) 2015 Santosh Maharjan. All rights reserved.
//  https://github.com/immortalsantee/SyncEngine

#import "AFHTTPRequestOperationManager.h"

typedef void (^SuccessBlockType)(AFHTTPRequestOperation *operation, id responseObject);
typedef void (^FailureBlockType)(AFHTTPRequestOperation *operation, NSError *error);
typedef void (^formData)(id <AFMultipartFormData> formData);

@interface SDAFParseAPIClient : AFHTTPRequestOperationManager

+ (SDAFParseAPIClient *)sharedClient;

/*
 *  simple raw data accepting form
 */
- (AFHTTPRequestOperation *)POSTRequestForClass:(NSString *)className
                                    APIBasedURL:(NSString *)URL
                                     parameters:(NSDictionary *)parameters
                                        success:(SuccessBlockType)success
                                        failure:(FailureBlockType)failure;

/*
 *  Form-data accepting form
 */
- (AFHTTPRequestOperation *)POSTRequestForClass:(NSString *)className
                                    APIBasedURL:(NSString *)URL
                                     parameters:(NSDictionary *)parameters
                                       formData:(formData)formdata
                                        success:(SuccessBlockType)success
                                        failure:(FailureBlockType)failure;

@end