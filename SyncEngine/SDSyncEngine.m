//
//  SDSyncEngine.m
//  immortalsantee@me.com
//
//  Created by Santosh Maharjan on 7/16/15.
//  Copyright (c) 2015 Santosh Maharjan. All rights reserved.
//  https://github.com/immortalsantee/SyncEngine

#import "SDSyncEngine.h"
#import <CoreData/CoreData.h>

#import "NSManagedObject+JSON.h"
#import "NSString+URLBYCLASS.h"

#import "SDAFParseAPIClient.h"
#import "AFHTTPRequestOperation.h"
#import "SDCoredataController.h"


@interface SDSyncEngine()

@property (nonatomic, strong) NSMutableArray *registeredClassesToSync;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) dispatch_queue_t backgroundSyncQueue;

@end


NSString * const kSDSyncEngineInitialCompleteKey = @"SDSyncEngineInitialSyncCompleted";
NSString * const kSDSyncEngineSyncCompletedNotificationName = @"SDSyncEngineSyncCompleted";


@implementation SDSyncEngine

@synthesize syncInProgress = _syncInProgress;
@synthesize syncCompleteMessage = _syncCompleteMessage;
@synthesize registeredClassesToSync = _registeredClassesToSync;
@synthesize dateFormatter = _dateFormatter;

#pragma mark : class method instance

+ (SDSyncEngine *)sharedEngine {
    static SDSyncEngine *sharedEngine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedEngine = [[SDSyncEngine alloc] init];
    });
    return sharedEngine;
}

- (void)setURLForRequest:(NSString *)url{
    self.baseURL = url;
}


#pragma mark : Register a class : Entity name registering

- (void)registerNSManagedObjectClassToSync:(Class)aClass {
    if (!self.registeredClassesToSync) {
        self.registeredClassesToSync = [NSMutableArray array];
    }
    
    if ([aClass isSubclassOfClass:[NSManagedObject class]]) {
        if (![self.registeredClassesToSync containsObject:NSStringFromClass(aClass)]) {
            if (!self.syncInProgress) {
                [self.registeredClassesToSync addObject:NSStringFromClass(aClass)];
            }
        } else {
            NSLog(@"Unable to register %@ as it is already registered", NSStringFromClass(aClass));
        }
    } else {
        NSLog(@"Unable to register %@ as it is not a subclass of NSManagedObject", NSStringFromClass(aClass));
    }
}


#pragma mark : Unregister all class : Deleting all registered class

-(void)unRegisterAllNSManagedObjectClass{
    if (!self.syncInProgress){
        [self.registeredClassesToSync removeAllObjects];
    }
}



#pragma mark : Sync Conditions

- (BOOL)initialSyncComplete {
    NSLog(@"initial sync complete status = %d",[[[NSUserDefaults standardUserDefaults] valueForKey:kSDSyncEngineInitialCompleteKey] boolValue]);
    return [[[NSUserDefaults standardUserDefaults] valueForKey:kSDSyncEngineInitialCompleteKey] boolValue];
}

- (void)setInitialSyncCompleted {
    [[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithBool:YES] forKey:kSDSyncEngineInitialCompleteKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSLog(@"setInitialSyncCompleted status = %d",[[[NSUserDefaults standardUserDefaults] valueForKey:kSDSyncEngineInitialCompleteKey] boolValue]);
}

- (void)executeSyncCompletedOperations {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setInitialSyncCompleted];
        [[NSNotificationCenter defaultCenter] postNotificationName:kSDSyncEngineSyncCompletedNotificationName object:nil];
        [self willChangeValueForKey:@"syncInProgress"];
        _syncInProgress = NO;
        [self didChangeValueForKey:@"syncInProgress"];
        
        if (_syncCompleteMessage) {
            [self showAlerViewWithMessage:_syncCompleteMessage];
            _syncCompleteMessage = nil;
        }
    });
}

- (void)showAlerViewWithMessage:(NSString *)message {
    UIAlertView *alertview = [[UIAlertView alloc] initWithTitle:nil message:message delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil, nil];
    [alertview show];
}


#pragma mark : start syncing

- (void)startSync {
    if (!self.syncInProgress) {
        [self willChangeValueForKey:@"syncInProgress"];
        _syncInProgress = YES;
        [self didChangeValueForKey:@"syncInProgress"];
        
        self.backgroundSyncQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        dispatch_async(self.backgroundSyncQueue, ^{
            [self downloadDataForRegisteredObjectsFromServer:YES];
        });
    }
}




#pragma mark 1) download data of registered classes from server to local path as .json(XML) file

- (void)downloadDataForRegisteredObjectsFromServer:(BOOL)useUpdatedAtDate {
    
    dispatch_group_t group = dispatch_group_create();
    
    for (NSString *className in self.registeredClassesToSync) {
        
        dispatch_group_enter(group);
        
        NSDate *mostRecentUpdatedDate = nil;
        if (useUpdatedAtDate) {
            mostRecentUpdatedDate = [self mostRecentUpdatedAtDateForEntityWithName:className];
        }
        
        NSDictionary *parameters = [self parameters:className updatedAfterDate:mostRecentUpdatedDate loggedInUserId:[className loggedInUserId] forTable:className];
        NSLog(@"\nclass name = %@ || \nclasswise Loggedin userid = %@ || \nurl based class = %@ || \nparameters = %@\n\n", className, [className loggedInUserId] , self.baseURL, parameters);
        
        AFHTTPRequestOperation *operation = [[SDAFParseAPIClient sharedClient] POSTRequestForClass:className APIBasedURL:self.baseURL parameters:parameters formData:^(id<AFMultipartFormData> formData) {
            // no images
        } success:^(AFHTTPRequestOperation *operation, id responseObject) {
            
            NSLog(@"Response data are \n(class =  %@) \n%@",className,responseObject);
            
            if ([responseObject isKindOfClass:[NSDictionary class]]) {
                
                [self writeJSONResponse:(id)[responseObject valueForKey:@"results"] toDiskForClassWithName:className];
                
            }else{
                NSLog(@"[responseObject valueForKey:@\"results\"] is not NSDictionary type ");
            }
            dispatch_group_leave(group);
            
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            NSLog(@"Request for class %@ failed with error: %@", className, [operation responseString]);
            dispatch_group_leave(group);
        }];
        
        operation.responseSerializer = [AFJSONResponseSerializer serializer];
        [operation start];
        
    }
    
    
    dispatch_group_notify(group, self.backgroundSyncQueue, ^{
        [self processJSONDataRecordsIntoCoreData];
    });
}






#pragma mark 5) Store .JSON OR XML file to coredata

- (void)processJSONDataRecordsIntoCoreData {
    
    NSManagedObjectContext *managedObjectContext = [[SDCoredataController sharedInstance] backgroundManagedObjectContext];
    
    for (NSString *className in self.registeredClassesToSync) {
        
        if (![self initialSyncComplete]) {
            
            NSDictionary *JSONDictionary = [self JSONDictionaryForClassWithName:className];
            NSLog(@"JSONDictionary = %@",JSONDictionary);
            
            NSArray *records = (NSArray *)JSONDictionary;
            NSLog(@"records = %@",records);
            for (NSDictionary *record in records) {
                NSLog(@"proper format of record is = %@", record);
                [self newManagedObjectWithClassName:className forRecord:record];
            }
            
        } else {
            
            NSLog(@"we entered else condition");
            
            NSArray *downloadedRecords = [self JSONDataRecordsForClass:className sortedByKey:@"server_id"];
            
            if ([downloadedRecords lastObject]) {
                
                NSArray *storedRecords = [self managedObjectsForClass:className sortedByKey:@"server_id" usingArrayOfIds:[downloadedRecords valueForKey:@"server_id"] inArrayOfIds:YES];
                
                for (NSDictionary *record in downloadedRecords) {
                    
                    NSArray *coreDatas = [[NSArray alloc] initWithArray:[storedRecords valueForKey:@"server_id"]];
                    NSString *downloadRecord = [record valueForKey:@"server_id"];
                    
                    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
                    formatter.numberStyle = NSNumberFormatterDecimalStyle;
                    NSNumber *serverID = [formatter numberFromString:[NSString stringWithFormat:@"%@",downloadRecord]];
                    
                    NSLog(@"coredatabase = %@",coreDatas);
                    NSLog(@"downlaod = %@", downloadRecord);
                    
                    if ([coreDatas containsObject:serverID]) {
                        
                        NSLog(@"update for coredata");
                        
                        int index = (int)[[storedRecords valueForKey:@"server_id"] indexOfObject:serverID];
                        [self updateManagedObject:[storedRecords objectAtIndex:index] withRecord:record];
                        
                    }else{
                        
                        NSLog(@"Insertion for coredata");
                        [self newManagedObjectWithClassName:className forRecord:record];
                        
                    }
                    
                }
            }
        }
        
        [managedObjectContext performBlockAndWait:^{
            NSError *error = nil;
            if (![managedObjectContext save:&error]) {
                NSLog(@"Unable to save context for class %@", className);
            }else{
                NSLog(@"context saved for class = %@",className);
            }
        }];
        
        [[SDCoredataController sharedInstance] saveBackgroundContext];
        [[SDCoredataController sharedInstance] saveMasterContext];
        
        [self deleteJSONDataRecordsForClassWithName:className];
        
    }
    [self postLocalObjectsToServer];
    
}



#pragma  mark 13 Post local data to server

- (void)postLocalObjectsToServer {
    
    dispatch_group_t group = dispatch_group_create();
    
    NSMutableArray *operations = [NSMutableArray array];
    
    for (NSString *className in self.registeredClassesToSync) {
        
        NSArray *objectsToCreate = [self managedObjectsForClass:className withSyncStatus:SDObjectCreated];
        
        for (NSManagedObject *objectToCreate in objectsToCreate) {
            
            dispatch_group_enter(group);
            
            NSDictionary *jsonString    =   [objectToCreate JSONToCreateObjectOnServer:@"sync_add" forTable:className];
            NSData *imageData           =   [objectToCreate imageInNSData];
            
            NSLog(@"add parameter for post local objects to server = %@", jsonString);
            
            
            AFHTTPRequestOperation *operation = [[SDAFParseAPIClient sharedClient] POSTRequestForClass:className APIBasedURL:self.baseURL parameters:jsonString formData:^(id<AFMultipartFormData> formData) {
                if (imageData) {
                    [formData appendPartWithFileData:imageData name:@"file" fileName:@"file.jpg" mimeType:@"image/jpeg"];
                }
            } success:^(AFHTTPRequestOperation *operation, id responseObject) {
                
                NSLog(@"Response_code of class (%@) || result = %@",className,responseObject);
                
                if ([[responseObject objectForKey:@"response_code"] isEqualToString:@"success"]) {
                    
                    [objectToCreate setValue:[NSNumber numberWithInt:SDObjectSynced] forKey:@"sync_status"];
                    [responseObject enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop)
                     {
                         if ([[objectToCreate.entity propertiesByName] objectForKey:key]!= nil)
                         {
                             [self setValue:obj forKey:key forManagedObject:objectToCreate];
                         }
                         else
                         {
                             NSLog(@"from SDObjectCreated section :  (%@) key is not available in coredata for new update",key);
                         }
                     }];
                    
                    
                    
                }else{
                    //either need to delete journal with response id
                    //
                }
                dispatch_group_leave(group);
                
            } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                NSLog(@"Failed creation: %@", operation.responseString);
                dispatch_group_leave(group);
            }];
            
            
            
            operation.responseSerializer = [AFJSONResponseSerializer serializer];
            
            [operations addObject:operation];
            [operation start];
            
        }
    }
    
    dispatch_group_notify(group, self.backgroundSyncQueue, ^{
        
        if ([operations count] > 0) {
            [[SDCoredataController sharedInstance] saveBackgroundContext];
            [[SDCoredataController sharedInstance] saveMasterContext];
        }
        
        [self updateLocalObjectsToServer];
    });
    
}



#pragma mark 15) Coredata To Server: Update local data to server

- (void)updateLocalObjectsToServer {
    
    dispatch_group_t group = dispatch_group_create();
    
    NSMutableArray *operations = [NSMutableArray array];
    
    for (NSString *className in self.registeredClassesToSync) {
        
        NSArray *objectsToCreate = [self managedObjectsForClass:className withSyncStatus:SDObjectUpdated];
        
        for (NSManagedObject *objectToCreate in objectsToCreate) {
            
            dispatch_group_enter(group);
            
            NSDictionary *jsonString    =   [objectToCreate JSONToCreateObjectOnServer:@"sync_update" forTable:className];
            
            NSData *imageData           =   [objectToCreate imageInNSData];
            NSLog(@"parameter for upload (%@)= %@",className, jsonString);
            
            AFHTTPRequestOperation *operation = [[SDAFParseAPIClient sharedClient] POSTRequestForClass:className APIBasedURL:self.baseURL parameters:jsonString formData:^(id<AFMultipartFormData> formData)
            {
                if (imageData)
                {
                    [formData appendPartWithFileData:imageData name:@"file" fileName:@"file.jpg" mimeType:@"image/jpeg"];
                }
            } success:^(AFHTTPRequestOperation *operation, id responseObject)
            {
                NSDictionary *responseDictionary = responseObject;
                NSLog(@"Success response for class ( %@ ) : %@",className, responseDictionary);
                
                if ([[responseDictionary valueForKey:@"response_code"] isEqualToString:@"success"])
                {
                    [objectToCreate setValue:[NSNumber numberWithInt:SDObjectSynced] forKey:@"sync_status"];
                    [responseObject enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop)
                     {
                         if ([[objectToCreate.entity propertiesByName] objectForKey:key]!= nil)
                         {
                             [self setValue:obj forKey:key forManagedObject:objectToCreate];
                         }
                         else
                         {
                             NSLog(@"from SDObjectCreated section :  (%@) key is not available in coredata for new update",key);
                         }
                     }];
                }
                
                dispatch_group_leave(group);
                
            } failure:^(AFHTTPRequestOperation *operation, NSError *error)
            {
                NSLog(@"Error on response on sync Update: %@ \n %@", operation.responseString, error);
                dispatch_group_leave(group);
            }];
            
            operation.responseSerializer = [AFJSONResponseSerializer serializer];
            
            [operations addObject:operation];
            [operation start];
            
        }
    }
    
    dispatch_group_notify(group, self.backgroundSyncQueue, ^{
        
        if ([operations count] > 0)
        {
            [[SDCoredataController sharedInstance] saveBackgroundContext];
            [[SDCoredataController sharedInstance] saveMasterContext];
        }
        
        [self deleteObjectsOnServer];
    });
    
}



#pragma mark 16) Server : delete objects on server asdf

- (void)deleteObjectsOnServer
{
    
    dispatch_group_t group = dispatch_group_create();
    
    NSMutableArray *operations = [NSMutableArray array];
    
    for (NSString *className in self.registeredClassesToSync)
    {
        
        NSArray *objectsToDelete = [self managedObjectsForClass:className withSyncStatus:SDObjectDeleted];
        
        for (NSManagedObject *objectToDelete in objectsToDelete)
        {
            
            dispatch_group_enter(group);
            
            NSDictionary *jsonString    =   [objectToDelete JSONToCreateObjectOnServer:@"sync_delete" forTable:className];
            NSLog(@"request json string for deleteion class (%@) is %@",className, jsonString);
            
            AFHTTPRequestOperation *operation = [[SDAFParseAPIClient sharedClient] POSTRequestForClass:className APIBasedURL:self.baseURL parameters:jsonString formData:^(id<AFMultipartFormData> formData)
            {
                //
            } success:^(AFHTTPRequestOperation *operation, id responseObject)
            {
                
                NSLog(@"Deletion Response : %@", responseObject);
                
                if ([[responseObject valueForKey:@"response_code"] isEqualToString:@"success"]) {
                    [[[SDCoredataController sharedInstance] backgroundManagedObjectContext] deleteObject:objectToDelete];
                }else{
                    NSLog(@"data not deleted from coredata. But data in server is deleted. Please uninstall and install the app again.");
                }
                dispatch_group_leave(group);
                
            } failure:^(AFHTTPRequestOperation *operation, NSError *error)
            {
                NSLog(@"Failed to delete: %@", operation.responseString);
                dispatch_group_leave(group);
            }];
            
            operation.responseSerializer = [AFJSONResponseSerializer serializer];
            
            [operations addObject:operation];
            [operation start];
            
        }
        
    }
    
    
    dispatch_group_notify(group, self.backgroundSyncQueue, ^
    {
        
        if ([operations count] > 0)
        {
            
            NSError *error = nil;
            BOOL saved = [[[SDCoredataController sharedInstance] backgroundManagedObjectContext] save:&error];
            if (!saved) {
                NSLog(@"Unable to save context after deleting records");
            }else{
                NSLog(@"context deleted successfully.");
            }
            
            [[SDCoredataController sharedInstance] saveBackgroundContext];
            [[SDCoredataController sharedInstance] saveMasterContext];
            
        }else{
            
            NSError *error = nil;
            BOOL saved = [[[SDCoredataController sharedInstance] backgroundManagedObjectContext] save:&error];
            if (!saved)
            {
                NSLog(@"Unable to save context after deleting records");
            }else
            {
                NSLog(@"context deleted successfully.");
            }
            
            [[SDCoredataController sharedInstance] saveBackgroundContext];
            [[SDCoredataController sharedInstance] saveMasterContext];
        }
        
        [self executeSyncCompletedOperations];
    });
    
}





#pragma mark 14) return array with singleton instance nsmaganedobjectcontext with sync status

- (NSArray *)managedObjectsForClass:(NSString *)className withSyncStatus:(SDObjectSyncStatus)syncStatus
{
    __block NSArray *results = nil;
    NSManagedObjectContext *managedObjectContext = [[SDCoredataController sharedInstance] backgroundManagedObjectContext];
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:className];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"sync_status = %d", syncStatus];
    [fetchRequest setPredicate:predicate];
    [managedObjectContext performBlockAndWait:^
    {
        NSError *error = nil;
        results = [managedObjectContext executeFetchRequest:fetchRequest error:&error];
    }];
    NSLog(@"results from coredata are for class (%@) = %@",className, results);
    return results;
}




#pragma mark 7) Coredata : Insert new managed object context

- (void)newManagedObjectWithClassName:(NSString *)className forRecord:(NSDictionary *)downloadedRecord
{
    if ([downloadedRecord isKindOfClass:[NSDictionary class]])
    {
        NSManagedObject *newManagedObject = [NSEntityDescription insertNewObjectForEntityForName:className inManagedObjectContext:[[SDCoredataController sharedInstance] backgroundManagedObjectContext]];
        
        //[downloadedRecord setValue:[NSString stringWithFormat:@"%d",SDObjectSynced] forKey:@"sync_status"];
        
        __block BOOL deleteFlag = NO;
        
        [downloadedRecord enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop)
        {
            /*
              *  Check if key is available or not in coredata to insert data
              */
            if ([[newManagedObject.entity propertiesByName] objectForKey:key])
            {
                NSString *myKey = [NSString stringWithFormat:@"%@",key];
                
                if ([myKey isEqualToString:@"sync_status"])
                {
                    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
                    formatter.numberStyle = NSNumberFormatterDecimalStyle;
                    NSNumber *value = [formatter numberFromString:[NSString stringWithFormat:@"%@",obj]];
                    
                    NSLog(@"value = %@",value);
                    
                    if ([value isEqualToNumber:[NSNumber numberWithInt:SDObjectDeleted]])
                    {
                        deleteFlag = YES;
                    }
                    
                }
                [self setValue:obj forKey:key forManagedObject:newManagedObject];
            }else
            {
                NSLog(@" (%@) key is not available in coredata for new insert",key);
            }
        }];
        [downloadedRecord setValue:[NSString stringWithFormat:@"%d",SDObjectSynced] forKey:@"sync_status"];
        if (deleteFlag)
        {
            [[[SDCoredataController sharedInstance] backgroundManagedObjectContext] deleteObject:newManagedObject];
        }
    }
}







#pragma mark 8) Getting Json data from local folder

- (NSArray *)JSONDataRecordsForClass:(NSString *)className sortedByKey:(NSString *)key
{
    NSDictionary *JSONDictionary = [self JSONDictionaryForClassWithName:className];
    
    NSLog(@"return datas from cache data %@ key is =%@",JSONDictionary, key);
    
    if (JSONDictionary)
    {
        NSString *checkNull;
        
        @try
        {
            if ([JSONDictionary objectForKey:@"results"])
            {
                checkNull = @"not null";
            }else
            {
                checkNull = nil;
            }
        }
        @catch (NSException *exception)
        {
            checkNull = nil;
        }
        
        NSArray *records = checkNull ? [[JSONDictionary valueForKey:@"results"] copy] : [JSONDictionary copy];
        
        if ([records valueForKey:key])
        {
            return [records sortedArrayUsingDescriptors:[NSArray arrayWithObject: [NSSortDescriptor sortDescriptorWithKey:key ascending:YES]]];
        }else
        {
            NSLog(@"not sucess data");
        }
    }
    return nil;
}


#pragma mark 9) similar managededobjects of id from server

- (NSArray *)managedObjectsForClass:(NSString *)className sortedByKey:(NSString *)key usingArrayOfIds:(NSArray *)idArray inArrayOfIds:(BOOL)inIds
{
    NSLog(@"comparing data from this array = %@",idArray);
    
    __block NSArray *results = nil;
    NSManagedObjectContext *managedObjectContext = [[SDCoredataController sharedInstance] backgroundManagedObjectContext];
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:className];
    NSPredicate *predicate;
    if (inIds) {
        predicate = [NSPredicate predicateWithFormat:@"server_id IN %@", idArray];
    } else {
        predicate = [NSPredicate predicateWithFormat:@"NOT (server_id IN %@)", idArray];
    }
    
    [fetchRequest setPredicate:predicate];
    [fetchRequest setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"server_id" ascending:YES]]];
    [managedObjectContext performBlockAndWait:^
    {
        NSError *error = nil;
        results = [managedObjectContext executeFetchRequest:fetchRequest error:&error];
    }];
    NSLog(@"total count from coredata = %lu",(unsigned long)results.count);
    for (NSManagedObject *array in results) {
        NSLog(@"affected server_id  = %@",[array valueForKey:@"server_id"]);
    }
    return results;
}


#pragma mark 10) Coredata : Update managed object context

- (void)updateManagedObject:(NSManagedObject *)managedObject withRecord:(NSDictionary *)record
{
    __block BOOL deleteFlag = NO;
    
    [record enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop)
    {
        /*
          *  Check if key is available or not in coredata to update data
          */
        if ([[managedObject.entity propertiesByName] objectForKey:key]!= nil)
        {
            NSString *myKey = [NSString stringWithFormat:@"%@",key];
            
            if ([myKey isEqualToString:@"sync_status"])
            {
                NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
                formatter.numberStyle = NSNumberFormatterDecimalStyle;
                NSNumber *value = [formatter numberFromString:[NSString stringWithFormat:@"%@",obj]];
                
                NSLog(@"value = %@",value);
                
                if ([value isEqualToNumber:[NSNumber numberWithInt:SDObjectDeleted]])
                {
                    deleteFlag = YES;
                }
            }
            [self setValue:obj forKey:key forManagedObject:managedObject];
        }else
        {
            NSLog(@" (%@) key is not available in coredata for new update",key);
        }
    }];
    
    NSManagedObjectContext *managedObjectContext = [[SDCoredataController sharedInstance] backgroundManagedObjectContext];
    if (deleteFlag)
    {
        [managedObjectContext deleteObject:managedObject];
    }
    
}



#pragma mark Check is property is NSNumber type or not

- (BOOL)isNSNumberType:(NSManagedObject *)managedObject forKey:(NSString  *)key
{
    for (NSAttributeDescription *keyType in managedObject.entity.properties)
    {
        if ([keyType.name isEqualToString:key])
        {
            if ([keyType.attributeValueClassName isEqualToString:@"NSNumber"])
            {
                return true;
            }
            break;
        }
    }
    return false;
}


#pragma mark Check is property is NSDate type or not

- (BOOL)isNSDateType:(NSManagedObject *)managedObject forKey:(NSString  *)key
{
    for (NSAttributeDescription *keyType in managedObject.entity.properties) {
        if ([keyType.name isEqualToString:key])
        {
            if ([keyType.attributeValueClassName isEqualToString:@"NSDate"])
            {
                return true;
            }
            break;
        }
    }
    return false;
}


#pragma mark 11) Set Value for key for managed object

- (void)setValue:(id)value forKey:(NSString *)key forManagedObject:(NSManagedObject *)managedObject
{
    if ([self isNSDateType:managedObject forKey:key])
    {
        NSDate *date = [self dateUsingStringFromAPI:value];
        [managedObject setValue:date forKey:key];
        
        /***   NSUserdefault Structure.
            *   key     =   Class name.     Example : Entity
            *   value   =   NSDate          Example : 2015-08-25 10:38:00
            */
        if ([key isEqualToString:@"updated_at"])
        {
            NSString *className = managedObject.entity.name;
            
            if ([[NSUserDefaults standardUserDefaults] valueForKey:className])
            {
                if([(NSDate*)[[NSUserDefaults standardUserDefaults] valueForKey:className] compare: date] == NSOrderedAscending)
                {
                    [[NSUserDefaults standardUserDefaults]setValue:date forKey:className];
                }
            }else
            {
                [[NSUserDefaults standardUserDefaults] setValue:date forKey:className];
            }
        }
        
    }else if ([self isNSNumberType:managedObject forKey:key])
    {
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        NSNumber *newValue = [formatter numberFromString:[NSString stringWithFormat:@"%@",value]]; //because value is of id type and will crash as numberfromstring will take string.
        
        [managedObject setValue:newValue forKey:key];
    }else {
        if ([key isEqualToString:@"id"])
        {
            [managedObject setValue:value forKey:@"server_id"];
        }else
        {
            [managedObject setValue:value forKey:key];
        }
    }
}


#pragma mark 12) deleting json record as per class name

- (void)deleteJSONDataRecordsForClassWithName:(NSString *)className
{
    NSURL *url = [NSURL URLWithString:className relativeToURL:[self JSONDataRecordsDirectory]];
    NSError *error = nil;
    BOOL deleted = [[NSFileManager defaultManager] removeItemAtURL:url error:&error];
    if (!deleted)
    {
        NSLog(@"Unable to delete JSON Records at %@, reason: %@", url, error);
    }else
    {
        NSLog(@"Deleting (%@) JSON Records successful",className);
    }
}





#pragma mark 6) Dictionary data from locally saved .josn or xml file

- (NSDictionary *)JSONDictionaryForClassWithName:(NSString *)className
{
    NSURL *fileURL = [NSURL URLWithString:className relativeToURL:[self JSONDataRecordsDirectory]];
    
    NSLog(@"file url = %@",fileURL);
    NSData* data = [NSData dataWithContentsOfFile:[fileURL path]];
    NSDictionary *localDataToDictionary = nil;
    if (data)
    {
        localDataToDictionary = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListReadCorruptError format:nil error:nil];
    }
    return localDataToDictionary;
    
}





#pragma mark - 3) File Management

- (void)writeJSONResponse:(id)response toDiskForClassWithName:(NSString *)className
{
    NSURL *fileURL = [NSURL URLWithString:className relativeToURL:[self JSONDataRecordsDirectory]];
    NSLog(@"file url = %@",fileURL);
    
    if (![(NSDictionary *)response writeToFile:[fileURL path] atomically:YES])
    {
        NSLog(@"Error saving response to disk, will attempt to remove NSNull values and try again.");
        
        NSArray *records = (NSArray *) response;
        NSLog(@"writeJSONResponse method says : nsarray records are from local drive = %@",records);
        
        NSMutableArray *nullFreeRecords = [NSMutableArray array];
        for (NSDictionary *record in records)
        {
            NSMutableDictionary *nullFreeRecord = [NSMutableDictionary dictionaryWithDictionary:record];
            [record enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop)
            {
                if ([obj isKindOfClass:[NSNull class]])
                {
                    [nullFreeRecord setValue:nil forKey:key];
                }
            }];
            [nullFreeRecords addObject:nullFreeRecord];
        }
        
        if (![nullFreeRecords writeToFile:[fileURL path] atomically:YES])
        {
            NSLog(@"Failed all attempts to save response to disk: %@", response);
        }else
        {
            NSLog(@"After failed, successfull to save response to disk : %@",response);
        }
        
    }else{
        NSLog(@"successfull to store to the local.");
    }
}


- (NSURL *)JSONDataRecordsDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *url = [NSURL URLWithString:@"JSONRecords/" relativeToURL:[self applicationCacheDirectory]];
    NSError *error = nil;
    if (![fileManager fileExistsAtPath:[url path]])
    {
        [fileManager createDirectoryAtPath:[url path] withIntermediateDirectories:YES attributes:nil error:&error];
    }
    
    return url;
}


- (NSURL *)applicationCacheDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject];
}

#pragma mark -



#pragma mark 2) Coredata : Most recently updated date of entity name

- (NSDate *)mostRecentUpdatedAtDateForEntityWithName:(NSString *)entityName
{
    NSDate *date = (NSDate *)[[NSUserDefaults standardUserDefaults] valueForKey:entityName];
    NSLog(@"most recent updatedAt = %@", date);
    return date;
}


#pragma mark 4) Generating parameters for requesting data greater than give date as updated_date

- (NSDictionary *)parameters:(NSString *)className updatedAfterDate:(NSDate *)updatedDate loggedInUserId:(NSString *)userid forTable:(NSString *)tableName
{
    NSDictionary *parameters = nil;
    
    NSString *centre_id = [[NSUserDefaults standardUserDefaults] valueForKey:@"centre_id"];
    NSString *user_id = [[NSUserDefaults standardUserDefaults] valueForKey:@"user_id"];
    
    if (updatedDate)
    {
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        [dateFormatter setTimeZone:[NSTimeZone timeZoneWithName:@"GMT"]];
        
        parameters = [NSDictionary dictionaryWithObjectsAndKeys:
                      @"sync_list",@"_event",
                      tableName,@"_table",
                      [dateFormatter stringFromDate:updatedDate],@"updated_at",
                      user_id?user_id:@"",@"user_id",
                      centre_id?centre_id:@"",@"centre_id",
                      nil];
    }else
    {
        parameters = [NSDictionary dictionaryWithObjectsAndKeys:
                      @"sync_list" , @"_event",
                      tableName , @"_table",
                      @"2010-01-01 01:00:00" , @"updated_at",
                      user_id?user_id:@"" , @"user_id",
                      centre_id?centre_id:@"" , @"centre_id",
                      nil];
    }
    
    return parameters;
}






#pragma mark Date formatter

- (void)initializeDateFormatter
{
    if (!self.dateFormatter) {
        self.dateFormatter = [[NSDateFormatter alloc] init];
        [self.dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        [self.dateFormatter setTimeZone:[NSTimeZone timeZoneWithName:@"GMT"]];
    }
}

- (NSString *)dateStringForAPIUsingDate:(NSDate *)date
{
    [self initializeDateFormatter];
    NSString *dateString = [self.dateFormatter stringFromDate:date];
    return dateString;
}

- (NSDate *)dateUsingStringFromAPI:(NSString *)dateString
{
    [self initializeDateFormatter];
    return [self.dateFormatter dateFromString:dateString];
}

#pragma mark -


@end