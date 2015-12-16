//
//  NSManagedObject+JSON.m
//  immortalsantee@me.com
//
//  Created by Santosh Maharjan on 7/16/15.
//  Copyright (c) 2015 Santosh Maharjan. All rights reserved.
//  https://github.com/immortalsantee/SyncEngine

#import "NSManagedObject+JSON.h"

@implementation NSManagedObject (JSON)

- (NSDictionary *) JSONToCreateObjectOnServer:(NSString *)serverEvent forTable:(NSString *)tableName{
    
    NSMutableDictionary *jsonDictionary = [[NSMutableDictionary alloc] init];
    
    [jsonDictionary setObject:serverEvent forKey:@"_event"];
    [jsonDictionary setObject:tableName forKey:@"_table"];
    
    for (NSAttributeDescription *keyType in self.entity.properties) {
        [jsonDictionary setObject:[self valueForKey:keyType.name] ? [self valueForKey:keyType.name] : @"" forKey:keyType.name];
    }
    
    return jsonDictionary;
}


-(NSData *) imageInNSData{
    return nil;
}


-(NSString *) URLBasedOnClass{
    return @"";
}


@end