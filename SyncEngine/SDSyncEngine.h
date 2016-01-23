//
//  SDSyncEngine.h
//  immortalsantee@me.com
//
//  Created by Santosh Maharjan on 7/16/15.
//  Copyright (c) 2015 Santosh Maharjan. All rights reserved.
//  https://github.com/immortalsantee/SyncEngine

#import <Foundation/Foundation.h>

@interface SDSyncEngine : NSObject

@property (atomic, readonly) BOOL syncInProgress;
@property (atomic, readonly) BOOL debugMode;
@property (nonatomic, retain) NSString *syncCompleteMessage;
@property (nonatomic, retain) NSString *baseURL;

typedef enum {
    SDObjectSynced = 0,
    SDObjectCreated,
    SDObjectDeleted,
    SDObjectUpdated,
} SDObjectSyncStatus;


+ (SDSyncEngine *)sharedEngine;

- (void)setURLForRequest:(NSString *)url;
- (void)registerNSManagedObjectClassToSync:(Class)aClass;
- (void)unRegisterAllNSManagedObjectClass;
- (void)startSync;

- (NSString *)dateStringForAPIUsingDate:(NSDate *)date;
- (NSDate *)dateUsingStringFromAPI:(NSString *)dateString;

@end



