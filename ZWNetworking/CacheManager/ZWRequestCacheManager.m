//
//  ZWRequestCacheManager.m
//  MojiCustomerClient
//
//  Created by 刘志伟 on 2019/11/7.
//  Copyright © 2019 liuzhiwei. All rights reserved.
//

#import "ZWRequestCacheManager.h"
#import "ZWMemoryCache.h"
#import "ZWDiskCache.h"
#import "ZWLRUManager.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *const cacheDirKey = @"ZWCacheDirKey";

static NSString *const downloadDirKey = @"ZWDownloadDirKey";

static NSUInteger diskCapacity = 60 * 1024 * 1024;

static NSTimeInterval cacheTime = 7 * 24 * 60 * 60;


@implementation ZWRequestCacheManager

+ (ZWRequestCacheManager *)shareManager {
    
    static ZWRequestCacheManager *_ZWRequestCacheManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _ZWRequestCacheManager = [[ZWRequestCacheManager alloc] init];
    });
    return _ZWRequestCacheManager;
}

- (void)setCacheTime:(NSTimeInterval)time diskCapacity:(NSUInteger)capacity {
    
    diskCapacity = capacity;
    cacheTime = time;
}

- (void)cacheResponseObject:(id)responseObject
                 requestUrl:(NSString *)requestUrl
                     params:(NSDictionary *)params {
    
    assert(responseObject);
    
    assert(requestUrl);
    
    if (!params) params = @{};
    
    NSString *originString = [NSString stringWithFormat:@"%@%@",requestUrl,params];
    NSString *hash = [self md5:originString];
    
    NSData *data = nil;
    NSError *error = nil;
    if ([responseObject isKindOfClass:[NSData class]]) {
       
        data = responseObject;
    }else if ([responseObject isKindOfClass:[NSDictionary class]]){
        
        data = [NSJSONSerialization dataWithJSONObject:responseObject options:NSJSONWritingPrettyPrinted error:&error];
    }
    
    if (error == nil) {
        //缓存到内存中
        [ZWMemoryCache writeData:responseObject forKey:hash];
        
        //缓存到磁盘中
        //磁盘路径
        NSString *directoryPath = nil;
      
        directoryPath = [[NSUserDefaults standardUserDefaults] objectForKey:cacheDirKey];
        
        if (!directoryPath) {
        
            directoryPath = [@"ZWNetworking" stringByAppendingPathComponent:@"NetworkCache"];
            //[[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0] stringByAppendingPathComponent:@"ZWNetworking"] stringByAppendingPathComponent:@"NetworkCache"];
            
            [[NSUserDefaults standardUserDefaults] setObject:directoryPath forKey:cacheDirKey];
            
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        
        [ZWDiskCache writeData:data toDir:[self dataFilePathWithName:directoryPath] filename:hash];
        
        [[ZWLRUManager shareManager] addFileNode:hash];
    }
}

- (NSString *)dataFilePathWithName:(NSString *)name {
    
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    
    NSString *completitonPath = [path stringByAppendingPathComponent:name];
    
    return completitonPath;
}

- (id)getCacheResponseObjectWithRequestUrl:(NSString *)requestUrl
                                    params:(NSDictionary *)params {
    assert(requestUrl);
    
    id cacheData = nil;
    
    if (!params) params = @{};
    
    NSString *originString = [NSString stringWithFormat:@"%@%@",requestUrl,params];
    NSString *hash = [self md5:originString];
    
    //先从内存中查找
    cacheData = [ZWMemoryCache readDataWithKey:hash];
    
    if (!cacheData) {
        NSString *directoryPath = [[NSUserDefaults standardUserDefaults] objectForKey:cacheDirKey];
        
        if (directoryPath) {
            cacheData = [ZWDiskCache readDataFromDir:[self dataFilePathWithName:directoryPath] filename:hash];
            
            if (cacheData) [[ZWLRUManager shareManager] refreshIndexOfFileNode:hash];
        }
    }
    
    if (cacheData) {
        
        NSError *error = nil;
        id  responseJson = [NSJSONSerialization JSONObjectWithData:cacheData options:NSJSONReadingMutableContainers error:&error];
        
        return responseJson;
        
    } else {
        
        return nil;
    }
    
    
}

- (void)storeDownloadData:(NSData *)data
               requestUrl:(NSString *)requestUrl {
    assert(data);
    
    assert(requestUrl);
    
    NSString *fileName = nil;
    NSString *type = nil;
    NSArray *strArray = nil;
    
    strArray = [requestUrl componentsSeparatedByString:@"."];
    if (strArray.count > 0) {
        type = strArray[strArray.count - 1];
    }
    
    if (type) {
        fileName = [NSString stringWithFormat:@"%@.%@",[self md5:requestUrl],type];
    }else {
        fileName = [NSString stringWithFormat:@"%@",[self md5:requestUrl]];
    }
    
    NSString *directoryPath = nil;
    directoryPath = [[NSUserDefaults standardUserDefaults] objectForKey:downloadDirKey];
    if (!directoryPath) {
        directoryPath = [@"ZWNetworking" stringByAppendingPathComponent:@"ZWDownload"];
        
//        [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0] stringByAppendingPathComponent:@""] stringByAppendingPathComponent:@"Download"];
        
        [[NSUserDefaults standardUserDefaults] setObject:directoryPath forKey:downloadDirKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    
    [ZWDiskCache writeData:data toDir:directoryPath filename:fileName];
}

- (NSURL *)getDownloadDataFromCacheWithRequestUrl:(NSString *)requestUrl {
    assert(requestUrl);
    
    NSData *data = nil;
    NSString *fileName = nil;
    NSString *type = nil;
    NSArray *strArray = nil;
    NSURL *fileUrl = nil;
    
    strArray = [requestUrl componentsSeparatedByString:@"."];
    if (strArray.count > 0) {
        type = strArray[strArray.count - 1];
    }
    
    if (type) {
        fileName = [NSString stringWithFormat:@"%@.%@",[self md5:requestUrl],type];
    }else {
        fileName = [NSString stringWithFormat:@"%@",[self md5:requestUrl]];
    }
    
    NSString *directoryPath = [[NSUserDefaults standardUserDefaults] objectForKey:downloadDirKey];
    
    if (directoryPath) data = [ZWDiskCache readDataFromDir:[self dataFilePathWithName:directoryPath] filename:fileName];
    
    if (data) {
        NSString *path = [directoryPath stringByAppendingPathComponent:fileName];
        fileUrl = [NSURL fileURLWithPath:path];
    }
    
    return fileUrl;
}

- (NSUInteger)totalCacheSize {
    
    NSString *diretoryPath = [[NSUserDefaults standardUserDefaults] objectForKey: cacheDirKey];
    
    return [ZWDiskCache dataSizeInDir:diretoryPath];
}

- (NSUInteger)totalDownloadDataSize {
    
    NSString *diretoryPath = [[NSUserDefaults standardUserDefaults] objectForKey: downloadDirKey];
    
    return [ZWDiskCache dataSizeInDir:diretoryPath];
}

- (void)clearDownloadData {
    
    NSString *diretoryPath = [[NSUserDefaults standardUserDefaults] objectForKey:downloadDirKey];
    
    [ZWDiskCache clearDataIinDir:diretoryPath];
}

- (NSString *)getDownDirectoryPath {
    
    NSString *diretoryPath = [[NSUserDefaults standardUserDefaults] objectForKey:downloadDirKey];
    return diretoryPath;
}

- (NSString *)getCacheDiretoryPath {
    NSString *diretoryPath = [[NSUserDefaults standardUserDefaults] objectForKey:cacheDirKey];
    return diretoryPath;
}

- (void)clearTotalCache {
    NSString *directoryPath = [[NSUserDefaults standardUserDefaults] objectForKey:cacheDirKey];
    
    [ZWDiskCache clearDataIinDir:directoryPath];
}

- (void)clearLRUCache {
    if ([self totalCacheSize] > diskCapacity) {
        NSArray *deleteFiles = [[ZWLRUManager shareManager] removeLRUFileNodeWithCacheTime:cacheTime];
        NSString *directoryPath = [[NSUserDefaults standardUserDefaults] objectForKey:cacheDirKey];
       
        if (directoryPath && deleteFiles.count > 0) {
        
            [deleteFiles enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL * _Nonnull stop) {
            
                NSString *filePath = [directoryPath stringByAppendingPathComponent:obj];
                [ZWDiskCache deleteCache:filePath];
            }];
            
        }
    }
}

#pragma mark - 散列值
- (NSString *)md5:(NSString *)string {
    if (string == nil || string.length == 0) {
        return nil;
    }
    
    unsigned char digest[CC_MD5_DIGEST_LENGTH],i;
    
    CC_MD5([string UTF8String],(int)[string lengthOfBytesUsingEncoding:NSUTF8StringEncoding],digest);
    
    NSMutableString *ms = [NSMutableString string];
    
    for (i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [ms appendFormat:@"%02x",(int)(digest[i])];
    }
    
    return [ms copy];
}


@end
