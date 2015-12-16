//
//  SDCoredataContoller.h
//  immortalsantee@me.com
//
//  Created by Santosh Maharjan on 7/16/15.
//  Copyright (c) 2015 Santosh Maharjan. All rights reserved.
//  https://github.com/immortalsantee/SyncEngine

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface SDCoredataController : NSObject

@property (nonatomic, strong) NSString *databaseName;

+ (id)sharedInstance;

- (void)setDBName:(NSString *)dbName;
- (NSManagedObjectContext *)masterManagedObjectContext;
- (NSManagedObjectContext *)backgroundManagedObjectContext;
- (NSManagedObjectContext *)newManagedObjectContext;
- (void)saveMasterContext;
- (void)saveBackgroundContext;
- (NSManagedObjectModel *)managedObjectModel;
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator;


@end