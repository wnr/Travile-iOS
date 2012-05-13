//
//  Account.h
//  Travian Manager
//
//  Created by Matej Kramny on 11/05/2012.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@class Hero;
//@class Profile;

@interface Account : NSObject <NSCoding>

@property (nonatomic, strong) NSString *name; // User's account name

@property (nonatomic, strong) NSArray *villages; // List of villages
@property (nonatomic, strong) NSArray *reports; // Reports
@property (nonatomic, strong) NSArray *messages; // Messages
@property (nonatomic, strong) NSArray *contacts; // Contact list
//@property (nonatomic, strong) Profile *profile;
@property (nonatomic, strong) Hero *hero; // Hero

@property (assign) bool hasBeginnersProtection; // Flags when user has beginner protection

@end
