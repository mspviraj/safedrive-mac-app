
//  Copyright (c) 2014 Infincia LLC. All rights reserved.
//

#import "SDServiceManager.h"

@import ServiceManagement;

@implementation SDServiceManager
@dynamic serviceStatus;

- (instancetype)init {
    self = [super init];
    if (self) {

    }
    return self;
}

- (void)dealloc {
    //never
}


#pragma mark
#pragma mark Public API

+(SDServiceManager *)sharedServiceManager {
    static SDServiceManager *localInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        localInstance = [[SDServiceManager alloc] init];
    });
    return localInstance;
}

#pragma mark - Service deployment

-(void)deployService {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // copy launch agent to ~/Library/LaunchAgents/
    NSURL *libraryURL = [fileManager URLForDirectory:NSLibraryDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
    NSURL *launchAgentsURL = [libraryURL URLByAppendingPathComponent:@"LaunchAgents" isDirectory:YES];
    NSURL *launchAgentDestinationURL = [launchAgentsURL URLByAppendingPathComponent:@"io.safedrive.SafeDrive.Service.plist" isDirectory:YES];

    NSURL *launchAgentSourceURL = [[NSBundle mainBundle] URLForResource:@"io.safedrive.SafeDrive.Service" withExtension:@"plist"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:launchAgentDestinationURL.path]) {
        [[NSFileManager defaultManager] removeItemAtURL:launchAgentDestinationURL error:nil];
    }
    NSError *launchAgentCopyError = nil;
    if (![fileManager copyItemAtURL:launchAgentSourceURL toURL:launchAgentDestinationURL error:&launchAgentCopyError]) {
        NSLog(@"Error copying launch agent: %@", launchAgentCopyError.localizedDescription);
    }
    
    // copy background service to ~/Library/Application Support/SafeDrive/
    NSURL *applicationSupportURL = [fileManager URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
    NSURL *safeDriveApplicationSupportURL = [applicationSupportURL URLByAppendingPathComponent:@"SafeDrive" isDirectory:YES];
    
    NSError *directoryError = nil;
    if (![fileManager createDirectoryAtURL:safeDriveApplicationSupportURL withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
        NSLog(@"Error creating support directory: %@", directoryError.localizedDescription);
    }    
    
    NSURL *serviceDestinationURL = [safeDriveApplicationSupportURL URLByAppendingPathComponent:@"SafeDriveService.app" isDirectory:YES];

    NSURL *serviceSourceURL = [[NSBundle mainBundle] URLForResource:@"SafeDriveService" withExtension:@"app" subdirectory:@"../PlugIns"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:serviceDestinationURL.path]) {
        [[NSFileManager defaultManager] removeItemAtURL:serviceDestinationURL error:nil];
    }
    NSError *serviceCopyError = nil;
    if (![fileManager copyItemAtURL:serviceSourceURL toURL:serviceDestinationURL error:&serviceCopyError]) {
        NSLog(@"Error copying service: %@", serviceCopyError.localizedDescription);
    }
}


#pragma mark - Service Agent control

-(void)loadService {
    NSURL *servicePlist = [[NSBundle mainBundle] URLForResource:@"io.safedrive.SafeDrive.Service" withExtension:@"plist"];

    NSDictionary *jobDict = [[NSMutableDictionary alloc] initWithContentsOfFile:servicePlist.path];
    CFErrorRef jobError = NULL;
    
    if (!SMJobSubmit(kSMDomainUserLaunchd, (__bridge CFDictionaryRef)jobDict, NULL, &jobError)) {
        NSError *err = (__bridge NSError *)jobError;
        NSLog(@"Load service error: %@", err.localizedDescription);
    }
}

-(void)unloadService {
    CFErrorRef jobError = NULL;
    if (!SMJobRemove(kSMDomainUserLaunchd, (CFStringRef)@"io.safedrive.SafeDrive.Service", NULL, 0, &jobError)) {
        NSError *err = (__bridge NSError *)jobError;
        NSLog(@"Unload service error: %@", err.localizedDescription);
    }
}

-(BOOL)serviceStatus {
    CFDictionaryRef jobDictRef = SMJobCopyDictionary(kSMDomainUserLaunchd, (CFStringRef)@"io.safedrive.SafeDrive.Service");
    NSDictionary *jobDict = (__bridge_transfer NSDictionary *)jobDictRef;    
    return jobDict ? YES : NO;
}

@end