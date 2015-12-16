//
//  NSManagedObject+JSON.h
//  immortalsantee@me.com
//
//  Created by Santosh Maharjan on 7/16/15.
//  Copyright (c) 2015 Santosh Maharjan. All rights reserved.
//  https://github.com/immortalsantee/SyncEngine

#import <CoreData/CoreData.h>

@interface NSManagedObject (JSON)

- (NSDictionary *) JSONToCreateObjectOnServer:(NSString *)serverEvent forTable:(NSString *)tableName;
-(NSData *) imageInNSData;
-(NSString *) URLBasedOnClass;

@end