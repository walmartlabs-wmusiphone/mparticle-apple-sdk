//
//  MPIdentityApi.m
//

#import "MPIdentityApi.h"
#import "MPIdentityApiManager.h"
#import "mParticle.h"
#import "MPBackendController.h"
#import "MPConsumerInfo.h"
#import "MPIUserDefaults.h"
#import "MPSession.h"
#import "MPPersistenceController.h"
#import "MPIdentityDTO.h"
#import "MPEnums.h"
#import "MPILogger.h"
#import "MPKitContainer.h"
#import "MPDevice.h"

typedef NS_ENUM(NSUInteger, MPIdentityRequestType) {
    MPIdentityRequestIdentify = 0,
    MPIdentityRequestLogin = 1,
    MPIdentityRequestLogout = 2,
    MPIdentityRequestModify = 3
};

@interface MParticle ()

@property (nonatomic, strong, readonly) MPPersistenceController *persistenceController;
@property (nonatomic, strong, readonly) MPKitContainer *kitContainer;

@end

@interface MPIdentityApi ()

@property (nonatomic, strong) MPIdentityApiManager *apiManager;
@property(nonatomic, strong, readwrite, nonnull) MParticleUser *currentUser;

@end

@interface MParticle ()

+ (dispatch_queue_t)messageQueue;
@property (nonatomic, strong, nonnull) MPBackendController *backendController;

@end

@interface MPBackendController ()

- (NSMutableDictionary<NSString *, id> *)userAttributesForUserId:(NSNumber *)userId;

@end

@interface MParticleUser ()

- (void)setUserIdentitySync:(NSString *)identityString identityType:(MPUserIdentity)identityType;
- (void)setUserId:(NSNumber *)userId;
- (void)setIsLoggedIn:(BOOL)isLoggedIn;
@end

@interface MPKitContainer ()

@property (nonatomic, strong) NSMutableDictionary<NSNumber *, MPKitConfiguration *> *kitConfigurations;

@end

@implementation MPIdentityApi

@synthesize currentUser = _currentUser;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _apiManager = [[MPIdentityApiManager alloc] init];
    }
    return self;
}

- (void)onModifyRequestComplete:(MPIdentityApiRequest *)request httpResponse:(MPIdentityHTTPModifySuccessResponse *) httpResponse completion:(MPIdentityApiResultCallback)completion error: (NSError *) error {
    if (error) {
        if (completion) {
            completion(nil, error);
        }
        return;
    }
    if (request.userIdentities) {
        NSMutableDictionary *userIDsCopy = [request.userIdentities mutableCopy];
        
        if (userIDsCopy[@(MPUserIdentityCustomerId)]) {
            [self.currentUser setUserIdentitySync:userIDsCopy[@(MPUserIdentityCustomerId)] identityType:MPUserIdentityCustomerId];
            [userIDsCopy removeObjectForKey:@(MPUserIdentityCustomerId)];
        }
        
        if (userIDsCopy[@(MPUserIdentityEmail)]) {
            [self.currentUser setUserIdentitySync:userIDsCopy[@(MPUserIdentityEmail)] identityType:MPUserIdentityEmail];
            [userIDsCopy removeObjectForKey:@(MPUserIdentityEmail)];
        }
        
        [userIDsCopy enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id  _Nonnull identityValue, BOOL * _Nonnull stop) {
            MPUserIdentity identityType = (MPUserIdentity)key.intValue;
            if ((NSNull *)identityValue == [NSNull null]) {
                identityValue = nil;
            }
            [self.currentUser setUserIdentitySync:identityValue identityType:identityType];
        }];
    }
    
    [self forwardCallToKits:request identityRequestType:MPIdentityRequestModify user:self.currentUser];
    
    if (completion) {
        MPIdentityApiResult *apiResult = [[MPIdentityApiResult alloc] init];
        apiResult.user = self.currentUser;
        completion(apiResult, nil);
    }
}

- (void)onIdentityRequestComplete:(MPIdentityApiRequest *)request identityRequestType:(MPIdentityRequestType)identityRequestType httpResponse:(MPIdentityHTTPSuccessResponse *)httpResponse completion:(MPIdentityApiResultCallback)completion error: (NSError *) error {
    if (error) {
        if (completion) {
            completion(nil, error);
        }
        return;
    }
    NSNumber *previousMPID = [MPPersistenceController mpId];
    [MPPersistenceController setMpid:httpResponse.mpid];
    MPIdentityApiResult *apiResult = [[MPIdentityApiResult alloc] init];
    MParticleUser *previousUser = self.currentUser;
    MParticleUser *user = [[MParticleUser alloc] init];
    user.userId = httpResponse.mpid;
    user.isLoggedIn = httpResponse.isLoggedIn;
    apiResult.user = user;
    self.currentUser = user;
    MPSession *session = [MParticle sharedInstance].backendController.session;
    session.userId = httpResponse.mpid;
    NSString *userIdsString = session.sessionUserIds;
    NSMutableArray *userIds = [[userIdsString componentsSeparatedByString:@","] mutableCopy];
    
    MPIUserDefaults *userDefaults = [MPIUserDefaults standardUserDefaults];

    if (user.userId.longLongValue != 0) {
        [userDefaults setMPObject:[NSDate date] forKey:kMPLastIdentifiedDate userId:user.userId];
        [userDefaults synchronize];
    }
    
    if (httpResponse.mpid.longLongValue != 0 &&
        ([userIds lastObject] && ![[userIds lastObject] isEqualToString:httpResponse.mpid.stringValue])) {
        [userIds addObject:httpResponse.mpid];
    }
    
    session.sessionUserIds = userIds.count > 0 ? [userIds componentsJoinedByString:@","] : @"";
    [[MParticle sharedInstance].persistenceController updateSession:session];
    
    if (request.userIdentities) {
        NSMutableDictionary *userIDsCopy = [request.userIdentities mutableCopy];
        
        if (userIDsCopy[@(MPUserIdentityCustomerId)]) {
            [self.currentUser setUserIdentitySync:userIDsCopy[@(MPUserIdentityCustomerId)] identityType:MPUserIdentityCustomerId];
            [userIDsCopy removeObjectForKey:@(MPUserIdentityCustomerId)];
        }
        
        if (userIDsCopy[@(MPUserIdentityEmail)]) {
            [self.currentUser setUserIdentitySync:userIDsCopy[@(MPUserIdentityEmail)] identityType:MPUserIdentityEmail];
            [userIDsCopy removeObjectForKey:@(MPUserIdentityEmail)];
        }
        
        [userIDsCopy enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id  _Nonnull identityValue, BOOL * _Nonnull stop) {
            MPUserIdentity identityType = (MPUserIdentity)key.intValue;
            [self.currentUser setUserIdentitySync:identityValue identityType:identityType];
        }];
    }
    
    if (httpResponse.mpid.intValue != previousMPID.intValue) {
        [self onMPIDChange:request httpResponse:httpResponse previousUser:previousUser newUser:user];
    }
    
    [self forwardCallToKits:request identityRequestType:identityRequestType user:user];
    
    if (completion) {
        completion(apiResult, nil);
    }
}

- (void)onMPIDChange:(MPIdentityApiRequest *)request httpResponse:(MPIdentityHTTPSuccessResponse *)httpResponse previousUser:(MParticleUser *)previousUser newUser:(MParticleUser *)newUser {
    if (request.onUserAlias) {
        @try {
            request.onUserAlias(previousUser, newUser);
        } @catch (NSException *exception) {
            MPILogError(@"Identity request - onUserAlias block threw an exception when invoked by the SDK: %@", exception);
        }
    }
    
    MPIUserDefaults *userDefaults = [MPIUserDefaults standardUserDefaults];

    [userDefaults setMPObject:@(httpResponse.isEphemeral) forKey:kMPIsEphemeralKey userId:httpResponse.mpid];
    [userDefaults synchronize];
    
    [[MParticle sharedInstance].persistenceController moveContentFromMpidZeroToMpid:httpResponse.mpid];
    
    if (newUser) {
        NSDictionary *userInfo = @{mParticleUserKey:newUser};
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:mParticleIdentityStateChangeListenerNotification object:nil userInfo:userInfo];
        });
    }
    
    NSArray<NSDictionary *> *kitConfig = [[MParticle sharedInstance].kitContainer.originalConfig copy];
    if (kitConfig) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[MParticle sharedInstance].kitContainer configureKits:kitConfig];
        });
    }
}

- (void)forwardCallToKits:(MPIdentityApiRequest *)request identityRequestType:(MPIdentityRequestType)identityRequestType user:(MParticleUser *)user{
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (identityRequestType) {
            case MPIdentityRequestIdentify: {
                [[MParticle sharedInstance].kitContainer forwardIdentitySDKCall:@selector(onIdentifyComplete: request:)
                                                                     kitHandler:^(id<MPKitProtocol> kit, MPKitConfiguration *kitConfig) {
                                                                         FilteredMParticleUser *filteredUser = [[FilteredMParticleUser alloc] initWithMParticleUser:user kitConfiguration:kitConfig];
                                                                         FilteredMPIdentityApiRequest *filteredRequest = [[FilteredMPIdentityApiRequest alloc] initWithIdentityRequest:request kitConfiguration:kitConfig];
                                                                         [kit onIdentifyComplete:filteredUser request:filteredRequest];
                                                                     }];
                break;
            }
            case MPIdentityRequestLogin: {
                [[MParticle sharedInstance].kitContainer forwardIdentitySDKCall:@selector(onLoginComplete: request:)
                                                                     kitHandler:^(id<MPKitProtocol> kit, MPKitConfiguration *kitConfig) {
                                                                         FilteredMParticleUser *filteredUser = [[FilteredMParticleUser alloc] initWithMParticleUser:user kitConfiguration:kitConfig];
                                                                         FilteredMPIdentityApiRequest *filteredRequest = [[FilteredMPIdentityApiRequest alloc] initWithIdentityRequest:request kitConfiguration:kitConfig];
                                                                         [kit onLoginComplete:filteredUser request:filteredRequest];
                                                                     }];
                break;
            }
            case MPIdentityRequestLogout: {
                [[MParticle sharedInstance].kitContainer forwardIdentitySDKCall:@selector(onLogoutComplete: request:)
                                                                     kitHandler:^(id<MPKitProtocol> kit, MPKitConfiguration *kitConfig) {
                                                                         FilteredMParticleUser *filteredUser = [[FilteredMParticleUser alloc] initWithMParticleUser:user kitConfiguration:kitConfig];
                                                                         FilteredMPIdentityApiRequest *filteredRequest = [[FilteredMPIdentityApiRequest alloc] initWithIdentityRequest:request kitConfiguration:kitConfig];
                                                                         [kit onLogoutComplete:filteredUser request:filteredRequest];
                                                                     }];
                break;
            }
            case MPIdentityRequestModify: {
                [[MParticle sharedInstance].kitContainer forwardIdentitySDKCall:@selector(onModifyComplete: request:)
                                                                     kitHandler:^(id<MPKitProtocol> kit, MPKitConfiguration *kitConfig) {
                                                                         FilteredMParticleUser *filteredUser = [[FilteredMParticleUser alloc] initWithMParticleUser:user kitConfiguration:kitConfig];
                                                                         FilteredMPIdentityApiRequest *filteredRequest = [[FilteredMPIdentityApiRequest alloc] initWithIdentityRequest:request kitConfiguration:kitConfig];
                                                                         [kit onModifyComplete:filteredUser request:filteredRequest];
                                                                     }];
                break;
            }
            default: {
                MPILogError(@"Unknown identity request type: %@", @(identityRequestType));
                break;
            }
        }
    });
}

- (MParticleUser *)currentUser {
    if (_currentUser) {
        return _currentUser;
    }

    NSNumber *mpid = [MPPersistenceController mpId];
    MParticleUser *user = [[MParticleUser alloc] init];
    user.userId = mpid;
    _currentUser = user;
    return _currentUser;
}

- (MParticleUser *)getUser:(NSNumber *)mpId {
    MPIUserDefaults *userDefaults = [MPIUserDefaults standardUserDefaults];
    if ([userDefaults isExistingUserId:mpId]) {
        MParticleUser *user = [[MParticleUser alloc] init];
        user.userId = mpId;
        return user;
    } else {
        return nil;
    }
}

- (NSArray<MParticleUser *> *)getAllUsers {
    MPIUserDefaults *userDefaults = [MPIUserDefaults standardUserDefaults];
    NSMutableArray<MParticleUser *> *userArray = [[NSMutableArray alloc] init];
    
    for (NSNumber *userID in [userDefaults userIDsInUserDefaults]) {
        MParticleUser *user = [[MParticleUser alloc] init];
        user.userId = userID;
        
        [userArray addObject:user];
    }
    
    return userArray;
}

- (NSString *)deviceApplicationStamp {
    MPDevice *device = [[MPDevice alloc] init];

    return device.deviceIdentifier;
}

- (void)identifyNoDispatch:(MPIdentityApiRequest *)identifyRequest completion:(nullable MPIdentityApiResultCallback)completion {
    [self.apiManager identify:identifyRequest completion:^(MPIdentityHTTPBaseSuccessResponse * _Nonnull httpResponse, NSError * _Nullable error) {
        [self onIdentityRequestComplete:identifyRequest identityRequestType:MPIdentityRequestIdentify httpResponse:(MPIdentityHTTPSuccessResponse *)httpResponse completion:completion error: error];
    }];
}

- (void)identify:(MPIdentityApiRequest *)identifyRequest completion:(nullable MPIdentityApiResultCallback)completion {
    MPIdentityApiResultCallback wrappedCompletion = ^(MPIdentityApiResult * _Nullable apiResult, NSError * _Nullable error) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(apiResult, error);
            });
        }
    };
    dispatch_async([MParticle messageQueue], ^{
        [self identifyNoDispatch:identifyRequest completion:wrappedCompletion];
    });
}

- (void)identifyWithCompletion:(nullable MPIdentityApiResultCallback)completion {
    [self identify:(id _Nonnull)nil completion:completion];
}

- (void)login:(MPIdentityApiRequest *)loginRequest completion:(nullable MPIdentityApiResultCallback)completion {
    MPIdentityApiResultCallback wrappedCompletion = ^(MPIdentityApiResult *_Nullable apiResult, NSError *_Nullable error) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(apiResult, error);
            });
        }
    };
    
    dispatch_async([MParticle messageQueue], ^{
        
        [self.apiManager loginRequest:loginRequest completion:^(MPIdentityHTTPBaseSuccessResponse * _Nonnull httpResponse, NSError * _Nullable error) {
            [self onIdentityRequestComplete:loginRequest identityRequestType:MPIdentityRequestLogin httpResponse:(MPIdentityHTTPSuccessResponse *)httpResponse completion:wrappedCompletion error: error];
        }];
        
    });
}

- (void)loginWithCompletion:(nullable MPIdentityApiResultCallback)completion {
    [self login:(id _Nonnull)nil completion:completion];
}

- (void)logout:(MPIdentityApiRequest *)logoutRequest completion:(nullable MPIdentityApiResultCallback)completion {
    MPIdentityApiResultCallback wrappedCompletion = ^(MPIdentityApiResult *_Nullable apiResult, NSError *_Nullable error) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(apiResult, error);
            });
        }
    };
    
    dispatch_async([MParticle messageQueue], ^{
        [self.apiManager logout:logoutRequest completion:^(MPIdentityHTTPBaseSuccessResponse * _Nonnull httpResponse, NSError * _Nullable error) {
            [self onIdentityRequestComplete:logoutRequest identityRequestType:MPIdentityRequestLogout httpResponse:(MPIdentityHTTPSuccessResponse *)httpResponse completion:wrappedCompletion error: error];
        }];
    });
}

- (void)logoutWithCompletion:(nullable MPIdentityApiResultCallback)completion {
    [self logout:(id _Nonnull)nil completion:completion];
}

- (void)modify:(MPIdentityApiRequest *)modifyRequest completion:(nullable MPIdentityApiResultCallback)completion {
    MPIdentityApiResultCallback wrappedCompletion = ^(MPIdentityApiResult *_Nullable apiResult, NSError *_Nullable error) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(apiResult, error);
            });
        }
    };
    dispatch_async([MParticle messageQueue], ^{
        [self.apiManager modify:modifyRequest completion:^(MPIdentityHTTPModifySuccessResponse * _Nonnull httpResponse, NSError * _Nullable error) {
            [self onModifyRequestComplete:modifyRequest httpResponse:httpResponse completion:wrappedCompletion error: error];
        }];
    });
}

@end

@implementation MPIdentityApiResult

@end

@implementation MPIdentityHTTPErrorResponse

- (instancetype)initWithJsonObject:(NSDictionary *)dictionary httpCode:(NSInteger) httpCode {
    self = [super init];
    if (self) {
        _httpCode = httpCode;
        if (dictionary) {
            _code = [dictionary[kMPIdentityRequestKeyCode] unsignedIntegerValue];
            _message = dictionary[kMPIdentityRequestKeyMessage];
        } else {
            _code = httpCode;
        }
    }
    return self;
}

- (instancetype)initWithCode:(MPIdentityErrorResponseCode) code message: (NSString *) message error: (NSError *) error {
    self = [super init];
    if (self) {
        _code = code;
        _innerError = error;
        _message = message;
    }
    return self;
}

- (NSString *)description {
    NSMutableString *description = [[NSMutableString alloc] initWithString:@"MPIdentityHTTPErrorResponse {\n"];
    [description appendFormat:@"  httpCode: %@\n", @(_httpCode)];
    [description appendFormat:@"  code: %@\n", @(_code)];
    [description appendFormat:@"  message: %@\n", _message];
    [description appendFormat:@"  inner error: %@\n", _innerError];
    [description appendString:@"}"];
    return description;
}

@end
