/* Copyright (C) 2011 - 2013 Matej Kramny <matejkramny@gmail.com>
 * All rights reserved.
 */

#import "TMFarmList.h"
#import "HTMLParser.h"
#import "HTMLNode.h"
#import "TPIdentifier.h"
#import "TMFarmListEntry.h"
#import "TMFarmListEntryFarm.h"
#import "NSString+HTML.h"
#import "TMAccount.h"
#import "TMStorage.h"
#import "TMVillage.h"

@interface TMFarmList () {
	void (^loadCompletion)(); // not sure if a good idea.. unusable with multiple objects trying to get the status of the farm list.
	NSURLConnection *loadConnection;
	NSURLConnection *villageConnection; // loads the village first in case the one isn't selected (in travian..)
	NSMutableData *loadData;
}

@end

@implementation TMFarmList

@synthesize farmLists, loaded, loading;

- (void)loadFarmList:(void (^)())completion {
	loadCompletion = completion;
	loaded = false;
	loading = true;
	
	// first activate correct village
	TMAccount *account = [TMStorage sharedStorage].account;
	TMVillage *village = account.village;
	NSURL *url = [account urlForArguments:[TMAccount resources], @"?", village.urlPart, nil];
	
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL: url cachePolicy:NSURLCacheStorageNotAllowed timeoutInterval:60];
	
	villageConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
}

#pragma mark - TMPageParsingProtocol

- (void)parsePage:(TravianPages)page fromHTMLNode:(HTMLNode *)node {
	if (!((page & TPBuilding) != 0)) {
		return;
	}
	
	HTMLNode *divRaidList = [node findChildWithAttribute:@"id" matchingName:@"raidList" allowPartial:NO];
	if (divRaidList) {
		NSArray *lists = [divRaidList findChildrenWithAttribute:@"id" matchingName:@"list" allowPartial:YES];
		NSMutableArray *mutableFarmLists = [[NSMutableArray alloc] init];
		for (HTMLNode *list in lists) {
			// Find the form tag.
			HTMLNode *form = [list findChildTag:@"form"];
			if (!form) {
				continue;
			}
			// Check if list belongs to this village.. They are hidden when they belong to another village.
			HTMLNode *listContent = [list findChildWithAttribute:@"class" matchingName:@"listContent" allowPartial:YES];
			if ([[listContent getAttributeNamed:@"class"] rangeOfString:@"hide"].location != NSNotFound) {
				continue;
			}
			
			TMFarmListEntry *entry = [[TMFarmListEntry alloc] init];
			
			// Collect input[type='hidden'] tags.
			NSMutableString *postData = [[NSMutableString alloc] init];
			NSArray *hiddenInputs = [list findChildrenWithAttribute:@"type" matchingName:@"hidden" allowPartial:NO];
			for (HTMLNode *hiddenInput in hiddenInputs) {
				NSString *name = [hiddenInput getAttributeNamed:@"name"];
				NSString *value = [hiddenInput getAttributeNamed:@"value"];
				if (!name || !value) continue;
				
				[postData appendFormat:@"%@=%@&", name, value];
			}
			
			entry.postData = postData;
			
			HTMLNode *listTitle = [list findChildWithAttribute:@"class" matchingName:@"listTitleText" allowPartial:NO];
			NSArray *listTitleChildren = [listTitle children];
			NSString *listName = [[[[listTitleChildren objectAtIndex:listTitleChildren.count-2] rawContents] stringByReplacingOccurrencesOfString:@"\n" withString:@""] stringByReplacingOccurrencesOfString:@"\t" withString:@""];
			NSRange firstMinus = [listName rangeOfString:@"-"];
			if (firstMinus.location != NSNotFound) {
				listName = [listName substringFromIndex:firstMinus.location+2];
			}
			
			entry.name = listName;
			
			// Actual rows of farms
			NSArray *slotRows = [listContent findChildrenWithAttribute:@"class" matchingName:@"slotRow" allowPartial:NO];
			NSMutableArray *listFarms = [[NSMutableArray alloc] initWithCapacity:slotRows.count];
			for (HTMLNode *slotRow in slotRows) {
				if ([slotRow findChildOfClass:@"noData"]) {
					continue; // no farms present
				}
				
				TMFarmListEntryFarm *entry = [[TMFarmListEntryFarm alloc] init];
				
				// POST name
				HTMLNode *checkbox = [slotRow findChildWithAttribute:@"type" matchingName:@"checkbox" allowPartial:NO];
				entry.postName = [checkbox getAttributeNamed:@"name"];
				
				// Target Village Name
				HTMLNode *villageNode = [slotRow findChildWithAttribute:@"class" matchingName:@"village" allowPartial:NO];
				HTMLNode *target = [villageNode findChildTag:@"label"];
				entry.targetName = [target contents];
				HTMLNode *coords = [target findChildWithAttribute:@"class" matchingName:@"coordinates" allowPartial:YES];
				if (coords) {
					HTMLNode *coordText = [coords findChildWithAttribute:@"class" matchingName:@"coordText" allowPartial:NO];
					entry.targetName = [[coordText contents] stringByAppendingString:@" "];
					NSArray *coordWrapper = [[coords findChildWithAttribute:@"class" matchingName:@"coordinatesWrapper" allowPartial:NO] children];
					for (HTMLNode *child in coordWrapper) {
						entry.targetName = [entry.targetName stringByAppendingString:[child contents]];
					}
				}
				HTMLNode *villageImg = [villageNode findChildTag:@"img"];
				entry.attackInProgress = NO;
				if (villageImg) {
					if ([[villageImg getAttributeNamed:@"class"] isEqualToString:@"attack att2"]) {
						entry.attackInProgress = YES;
					}
				}
				
				// Population
				HTMLNode *population = [slotRow findChildWithAttribute:@"class" matchingName:@"ew" allowPartial:NO];
				entry.targetPopulation = [[[population contents]  stringByReplacingOccurrencesOfString:@"\t" withString:@""] stringByReplacingOccurrencesOfString:@"\n" withString:@""];
				
				// Distance to target
				HTMLNode *distance = [slotRow findChildWithAttribute:@"class" matchingName:@"distance" allowPartial:NO];
				entry.distance = [[[distance contents] stringByReplacingOccurrencesOfString:@"\t" withString:@""] stringByReplacingOccurrencesOfString:@"\n" withString:@""];
				
				// Last Raid
				HTMLNode *lastRaid = [slotRow findChildWithAttribute:@"class" matchingName:@"lastRaid" allowPartial:NO];
				if (lastRaid) {
					HTMLNode *iReport = [lastRaid findChildWithAttribute:@"class" matchingName:@"iReport" allowPartial:YES];
					TMFarmListEntryFarmLastReportType type = 0;
					if (iReport) {
						NSString *iReportClass = [iReport getAttributeNamed:@"class"];
						if ([iReportClass rangeOfString:@"iReport1"].location != NSNotFound) {
							// No loss
							type |= TMFarmListEntryFarmLastReportTypeLostNone;
						} else if ([iReportClass rangeOfString:@"iReport2"].location != NSNotFound) {
							// Some loss
							type |= TMFarmListEntryFarmLastReportTypeLostSome;
						} else if ([iReportClass rangeOfString:@"iReport3"].location != NSNotFound) {
							// All lost
							type |= TMFarmListEntryFarmLastReportTypeLostAll;
						}
					}
					
					HTMLNode *carry = [lastRaid findChildWithAttribute:@"class" matchingName:@"carry" allowPartial:YES];
					if (carry) {
						NSString *carryClass = [carry getAttributeNamed:@"class"];
						if ([carryClass rangeOfString:@"empty"].location != NSNotFound) {
							// no bounty
							type |= TMFarmListEntryFarmLastReportTypeBountyNone;
						} else if ([carryClass rangeOfString:@"half"].location != NSNotFound) {
							// some bounty
							type |= TMFarmListEntryFarmLastReportTypeBountyPartial;
						} else if ([carryClass rangeOfString:@"full"].location != NSNotFound) {
							// Full
							type |= TMFarmListEntryFarmLastReportTypeBountyFull;
						}
						entry.lastReportBounty = [carry getAttributeNamed:@"alt"];
					}
					
					HTMLNode *aTag = [lastRaid findChildTag:@"a"];
					entry.lastReportTime = [aTag contents];
					entry.lastReportURL = [[aTag getAttributeNamed:@"href"] stringByReplacingOccurrencesOfString:@"berichte.php?id=" withString:@""];
					entry.lastReport = type;
				}
				
				// List of troops
				HTMLNode *troops = [slotRow findChildWithAttribute:@"class" matchingName:@"troops" allowPartial:NO];
				if (troops) {
					NSArray *troopIcons = [troops findChildrenWithAttribute:@"class" matchingName:@"troopIcon" allowPartial:NO];
					NSMutableArray *troopsArray = [[NSMutableArray alloc] initWithCapacity:troopIcons.count];
					for (HTMLNode *troopIcon in troopIcons) {
						HTMLNode *img = [troopIcon findChildTag:@"img"];
						NSString *troopName = @"";
						if (img) {
							troopName = [img getAttributeNamed:@"alt"];
						}
						
						NSString *troopCount = @"";
						HTMLNode *span = [troopIcon findChildTag:@"span"];
						if (span) {
							troopCount = [span contents];
						}
						
						[troopsArray addObject:@{@"name": troopName, @"count": troopCount}];
					}
					
					entry.troops = troopsArray;
				}
				
				[listFarms addObject:entry];
			}
			
			entry.farms = listFarms;
			[mutableFarmLists addObject:entry];
		}
		
		farmLists = mutableFarmLists;
	}
}

#pragma mark - NSURLConnectionDataDelegate, NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {  }
- (BOOL)connectionShouldUseCredentialStorage:(NSURLConnection *)connection	{	return NO;	}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	loadCompletion();
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	if (connection == loadConnection)
		[loadData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSHTTPURLResponse *)response {
	if (connection == loadConnection)
		loadData = [[NSMutableData alloc] initWithLength:0];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	if (connection == villageConnection) {
		// Get request to farm list url..
		NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[[TMStorage sharedStorage].account urlForString:[TMAccount farmList]] cachePolicy:NSURLCacheStorageNotAllowed timeoutInterval:60.0];
		
		[request setHTTPShouldHandleCookies:YES];
		
		loadConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
		villageConnection = nil;
		
		return;
	}
	
	NSError *error = nil;
	HTMLParser *parser = [[HTMLParser alloc] initWithData:loadData error:&error];
	HTMLNode *body = [parser body];
	
	TravianPages page = [TPIdentifier identifyPage:body];
	
	[self parsePage:page fromHTMLNode:body];
	
	[self setLoaded:YES];
	[self setLoading:NO];
	if (loadCompletion) {
		loadCompletion();
	}
}

@end
