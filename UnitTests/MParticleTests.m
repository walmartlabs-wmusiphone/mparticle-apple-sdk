#import <XCTest/XCTest.h>
#import "mParticle.h"
#import "MPBaseTestCase.h"
#import "MPStateMachine.h"
#import "MPSession.h"
#import "MPBackendController.h"
#import "OCMock.h"

@interface MParticle ()

+ (dispatch_queue_t)messageQueue;
@property (nonatomic, strong) MPStateMachine *stateMachine;
@property (nonatomic, strong) MPBackendController *backendController;
- (BOOL)isValidBridgeName:(NSString *)bridgeName;
- (void)handleWebviewCommand:(NSString *)command dictionary:(NSDictionary *)dictionary;

@end

@interface MParticleTests : MPBaseTestCase {
    NSNotification *lastNotification;
}

@end

@implementation MParticleTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
    lastNotification = nil;
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
    lastNotification = nil;
}

- (void)testResetInstance {
    MParticle *instance = [MParticle sharedInstance];
    MParticle *instance2 = [MParticle sharedInstance];
    XCTAssertNotNil(instance);
    XCTAssertEqual(instance, instance2);
    [instance reset];
    MParticle *instance3 = [MParticle sharedInstance];
    MParticle *instance4 = [MParticle sharedInstance];
    XCTAssertNotEqual(instance, instance3);
    XCTAssertEqual(instance3, instance4);
}

- (void)testOptOut {
    MParticle *instance = [MParticle sharedInstance];
    instance.stateMachine = [[MPStateMachine alloc] init];
    
    XCTAssertFalse(instance.optOut, "By Default Opt Out should be set to false");
    
    instance.optOut = YES;
    XCTAssert(instance.optOut, "Opt Out failed to set True");
    
    instance.optOut = NO;
    XCTAssertFalse(instance.optOut, "Opt Out failed to set False");
}

- (void)testOptOutEndsSession {
    MParticle *instance = [MParticle sharedInstance];
    instance.stateMachine = [[MPStateMachine alloc] init];
    instance.optOut = YES;
    
    MParticleSession *session = instance.currentSession;
    XCTAssertNil(session, "Setting Opt Out failed end the current session");
}

- (void)testNonOptOutHasSession {
    XCTestExpectation *expectation = [self expectationWithDescription:@"async work"];
    MParticle *instance = [MParticle sharedInstance];
    [instance startWithOptions:[MParticleOptions optionsWithKey:@"unit-test-key" secret:@"unit-test-secret"]];
    dispatch_async([MParticle messageQueue], ^{
        MParticleSession *session = instance.currentSession;
        XCTAssertNotNil(session, "Not Opted Out but nil current session");
        [expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testNoAutoTrackingHasNoSession {
    XCTestExpectation *expectation = [self expectationWithDescription:@"async work"];
    MParticle *instance = [MParticle sharedInstance];
    MParticleOptions *options = [MParticleOptions optionsWithKey:@"unit-test-key" secret:@"unit-test-secret"];
    options.automaticSessionTracking = NO;
    [instance startWithOptions:options];
    dispatch_async([MParticle messageQueue], ^{
        MParticleSession *session = instance.currentSession;
        XCTAssertNil(session, "No auto tracking but non-nil current session");
        [expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testNoAutoTrackingManualSession {
    XCTestExpectation *expectation = [self expectationWithDescription:@"async work"];
    MParticle *instance = [MParticle sharedInstance];
    MParticleOptions *options = [MParticleOptions optionsWithKey:@"unit-test-key" secret:@"unit-test-secret"];
    options.automaticSessionTracking = NO;
    [instance startWithOptions:options];
    [instance beginSession];
    dispatch_async([MParticle messageQueue], ^{
        MParticleSession *session = instance.currentSession;
        XCTAssertNotNil(session, "No auto tracking called begin but nil current session");
        [expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testNoAutoTrackingManualEndSession {
    XCTestExpectation *expectation = [self expectationWithDescription:@"async work"];
    MParticle *instance = [MParticle sharedInstance];
    MParticleOptions *options = [MParticleOptions optionsWithKey:@"unit-test-key" secret:@"unit-test-secret"];
    options.automaticSessionTracking = NO;
    [instance startWithOptions:options];
    [instance beginSession];
    [instance endSession];
    dispatch_async([MParticle messageQueue], ^{
        MParticleSession *session = instance.currentSession;
        XCTAssertNil(session, "No auto tracking called begin/end but non-nil current session");
        [expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

#if TARGET_OS_IOS == 1
- (void)testAutoTrackingContentAvail {
    XCTestExpectation *expectation = [self expectationWithDescription:@"async work"];
    MParticle *instance = [MParticle sharedInstance];
    MParticleOptions *options = [MParticleOptions optionsWithKey:@"unit-test-key" secret:@"unit-test-secret"];
    options.automaticSessionTracking = YES;
    options.proxyAppDelegate = NO;
    [instance startWithOptions:options];
    [instance endSession];
    
    [instance didReceiveRemoteNotification:@{@"aps":@{@"content-available":@"1"}, @"foo-notif-content": @"foo-notif-content-value"}];
    dispatch_async([MParticle messageQueue], ^{
        MParticleSession *session = instance.currentSession;
        XCTAssertNil(session, "Auto tracking but non-nil current session after content-available push");
        [expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testAutoTrackingNonContentAvail {
    XCTestExpectation *expectation = [self expectationWithDescription:@"async work"];
    MParticle *instance = [MParticle sharedInstance];
    MParticleOptions *options = [MParticleOptions optionsWithKey:@"unit-test-key" secret:@"unit-test-secret"];
    options.automaticSessionTracking = YES;
    options.proxyAppDelegate = NO;
    [instance startWithOptions:options];
    [instance endSession];
    
    [instance didReceiveRemoteNotification:@{@"aps":@{@"alert":@"Testing.. (0)",@"badge":@1,@"sound":@"default"}, @"foo-notif-content": @"foo-notif-content-value"}];
    dispatch_async([MParticle messageQueue], ^{
        MParticleSession *session = instance.currentSession;
        XCTAssertNotNil(session, "Auto tracking but nil current session after non-content-available push");
        [expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:10 handler:nil];
}
#endif

- (void)testNormalSessionContents {
    XCTestExpectation *expectation = [self expectationWithDescription:@"async work"];
    MParticle *instance = [MParticle sharedInstance];
    [instance startWithOptions:[MParticleOptions optionsWithKey:@"unit-test-key" secret:@"unit-test-secret"]];
    dispatch_async([MParticle messageQueue], ^{
        MParticle.sharedInstance.stateMachine.currentSession.uuid = @"76F1ABB9-7A9A-4D4E-AB4D-56C8FF79CAD1";
        MParticleSession *session = instance.currentSession;
        NSNumber *sessionID = session.sessionID;
        NSString *uuid = session.UUID;
        XCTAssertEqualObjects(@"76F1ABB9-7A9A-4D4E-AB4D-56C8FF79CAD1", uuid);
        XCTAssertEqual(-6881666186511944082, sessionID.integerValue);
        [expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)handleTestSessionStart:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:mParticleSessionDidBeginNotification object:nil];
    lastNotification = notification;
}

- (void)handleTestSessionEnd:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:mParticleSessionDidEndNotification object:nil];
    lastNotification = notification;
}

- (void)testIsValidBridgeName {
    BOOL valid = [[MParticle sharedInstance] isValidBridgeName:@"abc_123"];
    XCTAssertFalse(valid);
    valid = [[MParticle sharedInstance] isValidBridgeName:@"abc123"];
    XCTAssertTrue(valid);
    valid = [[MParticle sharedInstance] isValidBridgeName:@"àbc123"];
    XCTAssertFalse(valid);
    valid = [[MParticle sharedInstance] isValidBridgeName:@""];
    XCTAssertFalse(valid);
}

#if TARGET_OS_IOS == 1
- (void)testWebviewLogEvent {
    id mockBackend = OCMClassMock([MPBackendController class]);
    
    MPEvent *testEvent = [[MPEvent alloc] initWithName:@"foo webview event 1" type:MPEventTypeNavigation];
    testEvent.info = @{@"foo webview event attribute 1":@"foo webview event attribute value 1"};
    
    [[[mockBackend expect] ignoringNonObjectArgs] logEvent:[OCMArg checkWithBlock:^BOOL(id value) {
        MPEvent *returnedEvent = ((MPEvent *)value);
        XCTAssertEqualObjects(returnedEvent.name, testEvent.name);
        XCTAssertEqual(returnedEvent.type, testEvent.type);
        XCTAssertEqualObjects(returnedEvent.info, testEvent.info);
        
        return YES;
    }] completionHandler:[OCMArg any]];
    
    MParticle *instance = [[MParticle alloc] init];
    id mockInstance = OCMPartialMock(instance);
    [[[mockInstance stub] andReturn:mockBackend] backendController];
    
    NSString *command = @"logEvent";
    NSDictionary *dictionary = @{@"EventDataType":@(MPJavascriptMessageTypePageEvent), @"EventName":@"foo webview event 1", @"EventCategory":@(MPEventTypeNavigation), @"EventAttributes":@{@"foo webview event attribute 1":@"foo webview event attribute value 1"}};
    [instance handleWebviewCommand:command dictionary:dictionary];
    
    [mockBackend verifyWithDelay:2];
    
    [mockInstance stopMocking];
    [mockBackend stopMocking];
}

- (void)testTrackNotificationsDefault {
    id mockBackend = OCMClassMock([MPBackendController class]);
    
    MParticle *instance = [[MParticle alloc] init];
    id mockInstance = OCMPartialMock(instance);
    [[[mockInstance stub] andReturn:mockBackend] backendController];
    
    MParticleOptions *options = [MParticleOptions optionsWithKey:@"unit-test-key" secret:@"unit-test-secret"];
    [mockInstance startWithOptions:options];
    
    XCTAssertTrue(instance.trackNotifications, "By Default Track Notifications should be set to true");
    
    [mockInstance stopMocking];
    [mockBackend stopMocking];
}

- (void)testTrackNotificationsOff {
    id mockBackend = OCMClassMock([MPBackendController class]);
    
    MParticle *instance = [[MParticle alloc] init];
    id mockInstance = OCMPartialMock(instance);
    [[[mockInstance stub] andReturn:mockBackend] backendController];
    
    MParticleOptions *options = [MParticleOptions optionsWithKey:@"unit-test-key" secret:@"unit-test-secret"];
    options.trackNotifications = NO;
    [mockInstance startWithOptions:options];
    
    XCTAssertFalse(instance.trackNotifications, "Track Notifications failed to set False");
    
    [mockInstance stopMocking];
    [mockBackend stopMocking];
}

- (void)testTrackNotificationsOn {
    id mockBackend = OCMClassMock([MPBackendController class]);
    
    MParticle *instance = [[MParticle alloc] init];
    id mockInstance = OCMPartialMock(instance);
    [[[mockInstance stub] andReturn:mockBackend] backendController];
    
    MParticleOptions *options = [MParticleOptions optionsWithKey:@"unit-test-key" secret:@"unit-test-secret"];
    options.trackNotifications = YES;
    [mockInstance startWithOptions:options];
    
    XCTAssertTrue(instance.trackNotifications, "Track Notifications failed to set True");
    
    [mockInstance stopMocking];
    [mockBackend stopMocking];
}

- (void)testSessionStartNotification {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTestSessionStart:) name:mParticleSessionDidBeginNotification object:nil];
    XCTestExpectation *expectation = [self expectationWithDescription:@"async work"];
    MParticle *instance = [MParticle sharedInstance];
    [instance startWithOptions:[MParticleOptions optionsWithKey:@"unit-test-key" secret:@"unit-test-secret"]];
    dispatch_async([MParticle messageQueue], ^{
        XCTAssertNotNil(self->lastNotification);
        NSDictionary *userInfo = self->lastNotification.userInfo;
        XCTAssertEqual(2, userInfo.count);
        NSNumber *sessionID = userInfo[mParticleSessionId];
        XCTAssertEqualObjects(NSStringFromClass([sessionID class]), @"__NSCFNumber");
        NSString *sessionUUID = userInfo[mParticleSessionUUID];
        XCTAssertEqualObjects(NSStringFromClass([sessionUUID class]), @"__NSCFString");
        [expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testSessionEndNotification {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTestSessionEnd:) name:mParticleSessionDidEndNotification object:nil];
    XCTestExpectation *expectation = [self expectationWithDescription:@"async work"];
    MParticle *instance = [MParticle sharedInstance];
    [instance startWithOptions:[MParticleOptions optionsWithKey:@"unit-test-key" secret:@"unit-test-secret"]];
    dispatch_async([MParticle messageQueue], ^{
        [[MParticle sharedInstance].backendController endSession];
        dispatch_async(dispatch_get_main_queue(), ^{
            XCTAssertNotNil(self->lastNotification);
            NSDictionary *userInfo = self->lastNotification.userInfo;
            XCTAssertEqual(2, userInfo.count);
            NSNumber *sessionID = userInfo[mParticleSessionId];
            XCTAssertEqualObjects(NSStringFromClass([sessionID class]), @"__NSCFNumber");
            NSString *sessionUUID = userInfo[mParticleSessionUUID];
            XCTAssertEqualObjects(NSStringFromClass([sessionUUID class]), @"__NSCFString");
            [expectation fulfill];
        });
    });
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testLogNotificationWithUserInfo {
    MParticle *instance = [MParticle sharedInstance];
    id mockInstance = OCMPartialMock(instance);
    [[[mockInstance stub] andReturnValue:OCMOCK_VALUE(NO)] trackNotifications];
    [[[mockInstance stub] andReturn:mockInstance] sharedInstance];

    id mockBackendController = OCMClassMock([MPBackendController class]);
    instance.backendController = mockBackendController;
    
    NSNotification *testNotification = [[NSNotification alloc] initWithName:@"tester" object:self userInfo:@{@"foo-notif-key-1":@"foo-notif-value-1"}];
    
    [[mockBackendController expect] logUserNotification:OCMOCK_ANY];
    
    [mockInstance logNotificationOpenedWithUserInfo:[testNotification userInfo]];
    
    [mockBackendController verifyWithDelay:1.0];
    [mockBackendController stopMocking];
    [mockInstance stopMocking];
}

- (void)testLogWebviewEventContainingSlash {
    MParticle *instance = [MParticle sharedInstance];
    id mockInstance = OCMPartialMock(instance);
    [[[mockInstance stub] andReturn:mockInstance] sharedInstance];
    
    [(MParticle *)[mockInstance expect] logEvent:[OCMArg checkWithBlock:^BOOL(MPEvent *value) {
        return [value.info[@"referrer_source"] isEqual:@"http://example.com/foo?bar=1"];
    }]];
    
    NSURL *url = [NSURL URLWithString:@"mp-sdk://logEvent/%7B%22EventName%22%3A%22foo%20content%20view%22%2C%22EventCategory%22%3A1%2C%22UserAttributes%22%3A%7B%7D%2C%22UserIdentities%22%3A%7B%7D%2C%22Store%22%3A%7B%7D%2C%22EventAttributes%22%3A%7B%22foo%20document%20id%22%3A12345%2C%22referrer_source%22%3A%22http%3A%2F%2Fexample.com%2Ffoo%3Fbar%3D1%22%7D%2C%22SDKVersion%22%3A%221.2.3.4%22%2C%22SessionId%22%3Anull%2C%22EventDataType%22%3A4%2C%22Debug%22%3Afalse%2C%22Location%22%3Anull%2C%22OptOut%22%3Anull%2C%22ExpandedEventCount%22%3A0%2C%22AppVersion%22%3Anull%2C%22ClientGeneratedId%22%3Anull%2C%22DeviceId%22%3Anull%2C%22MPID%22%3Anull%2C%22ConsentState%22%3Anull%2C%22Timestamp%22%3A12345%7D"];
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [mockInstance processWebViewLogEvent:url];
#pragma clang diagnostic pop
    

    [mockInstance verifyWithDelay:1.0];
    [mockInstance stopMocking];
}
#endif

@end
