/*
 * Copyright 2017 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <XCTest/XCTest.h>

#import <FirebaseCore/FIRApp.h>

#import "FIRDatabaseReference.h"
#import "FIRDatabaseReference_Private.h"
#import "FIRDatabase.h"
#import "FIRDatabaseConfig_Private.h"
#import "FIROptions.h"
#import "FTestHelpers.h"
#import "FMockStorageEngine.h"
#import "FTestBase.h"
#import "FTestHelpers.h"
#import "FIRFakeApp.h"

@interface FIRDatabaseTests : FTestBase

@end

static const NSInteger kFErrorCodeWriteCanceled = 3;
static NSString *kFirebaseTestAltNamespace = @"https://foobar.firebaseio.com";

@implementation FIRDatabaseTests

- (void) testFIRDatabaseForNilApp {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    XCTAssertThrowsSpecificNamed([FIRDatabase databaseForApp:nil], NSException, @"InvalidFIRApp");
#pragma clang diagnostic pop
}

- (void) testDatabaseForApp {
    FIRDatabase *database = [self databaseForURL:self.databaseURL];
    XCTAssertEqualObjects(self.databaseURL, [database reference].URL);
}

- (void) testDatabaseForAppWithInvalidURLs {
    XCTAssertThrows([self databaseForURL:nil]);
    XCTAssertThrows([self databaseForURL:@"not-a-url"]);
    XCTAssertThrows([self databaseForURL:@"http://fblocal.com"]);
    XCTAssertThrows([self databaseForURL:@"http://x.example.com/paths/are/bad"]);
}

- (void)testDatabaseForAppWithURL {
    id app = [[FIRFakeApp alloc] initWithName:@"testDatabaseForAppWithURL" URL:kFirebaseTestAltNamespace];
    FIRDatabase *database = [FIRDatabase databaseForApp:app URL:@"http://foo.bar.com"];
    XCTAssertEqualObjects(@"https://foo.bar.com", [database reference].URL);
}

- (void)testDatabaseForAppWithURLAndPort {
    id app = [[FIRFakeApp alloc] initWithName:@"testDatabaseForAppWithURLAndPort"
                                          URL:kFirebaseTestAltNamespace];
    FIRDatabase *database = [FIRDatabase databaseForApp:app URL:@"http://foo.bar.com:80"];
    XCTAssertEqualObjects(@"http://foo.bar.com:80", [database reference].URL);
}

- (void)testDatabaseForAppWithHttpsURL {
    id app = [[FIRFakeApp alloc] initWithName:@"testDatabaseForAppWithHttpsURL"
                                          URL:kFirebaseTestAltNamespace];
    FIRDatabase *database = [FIRDatabase databaseForApp:app URL:@"https://foo.bar.com"];
    XCTAssertEqualObjects(@"https://foo.bar.com", [database reference].URL);
}

- (void)testDifferentInstanceForAppWithURL {
    id app = [[FIRFakeApp alloc] initWithName:@"testDifferentInstanceForAppWithURL"
                                          URL:kFirebaseTestAltNamespace];
    FIRDatabase *database1 = [FIRDatabase databaseForApp:app URL:@"https://foo1.bar.com"];
    FIRDatabase *database2 = [FIRDatabase databaseForApp:app URL:@"https://foo1.bar.com/"];
    FIRDatabase *database3 = [FIRDatabase databaseForApp:app URL:@"https://foo2.bar.com"];
    XCTAssertEqual(database1, database2);
    XCTAssertNotEqual(database1, database3);
}

- (void)testDatabaseForAppWithInvalidCustomURLs {
    id app = [[FIRFakeApp alloc] initWithName:@"testDatabaseForAppWithInvalidCustomURLs"
                                        URL:kFirebaseTestAltNamespace];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    XCTAssertThrows([FIRDatabase databaseForApp:app URL:nil]);
#pragma clang diagnostic pop
    XCTAssertThrows([FIRDatabase databaseForApp:app URL:@"not-a-url"]);
    XCTAssertThrows([FIRDatabase databaseForApp:app URL:@"http://fblocal.com"]);
    XCTAssertThrows([FIRDatabase databaseForApp:app URL:@"http://x.fblocal.com:9000/paths/are/bad"]);
}

- (void) testDeleteDatabase {
    // Set up a custom FIRApp with a custom database based on it.
    FIROptions *options = [[FIROptions alloc] initWithGoogleAppID:@"1:123:ios:123abc"
                                                      GCMSenderID:@"gcm_sender_id"];
    options.databaseURL = self.databaseURL;
    NSString *customAppName = @"MyCustomApp";
    [FIRApp configureWithName:customAppName options:options];
    FIRApp *customApp = [FIRApp appNamed:customAppName];
    FIRDatabase *customDatabase = [FIRDatabase databaseForApp:customApp];
    XCTAssertNotNil(customDatabase);

    // Delete the custom app and wait for it to be done.
    XCTestExpectation *customAppDeletedExpectation =
        [self expectationWithDescription:@"Deleting the custom app should be successful."];
    [customApp deleteApp:^(BOOL success) {
        // The app shouldn't exist anymore, ensure that the databaseForApp throws.
        XCTAssertThrows([FIRDatabase databaseForApp:[FIRApp appNamed:customAppName]]);

        [customAppDeletedExpectation fulfill];
    }];

    // Wait for the custom app to be deleted.
    [self waitForExpectations:@[customAppDeletedExpectation] timeout:2];

    // Configure the app again, then grab a reference to the database. Assert it's different.
    [FIRApp configureWithName:customAppName options:options];
    FIRApp *secondCustomApp = [FIRApp appNamed:customAppName];
    FIRDatabase *secondCustomDatabase = [FIRDatabase databaseForApp:secondCustomApp];
    XCTAssertNotNil(secondCustomDatabase);
    XCTAssertNotEqualObjects(customDatabase, secondCustomDatabase);
}

- (void) testReferenceWithPath {
    FIRDatabase *db = [self defaultDatabase];
    NSString *expectedURL = [NSString stringWithFormat:@"%@/foo", self.databaseURL];
    XCTAssertEqualObjects(expectedURL, [db referenceWithPath:@"foo"].URL);
}

- (void) testReferenceFromURLWithEmptyPath {
    FIRDatabaseReference *ref = [[self defaultDatabase] referenceFromURL:self.databaseURL];
    XCTAssertEqualObjects(self.databaseURL, ref.URL);
}

- (void) testReferenceFromURLWithPath {
    NSString *url = [NSString stringWithFormat:@"%@/foo/bar", self.databaseURL];
    FIRDatabaseReference *ref = [[self defaultDatabase] referenceFromURL:url];
    XCTAssertEqualObjects(url, ref.URL);
}

- (void) testReferenceFromURLWithWrongURL {
    NSString *url = [NSString stringWithFormat:@"%@/foo/bar", @"https://foobar.firebaseio.com"];
    XCTAssertThrows([[self defaultDatabase] referenceFromURL:url]);
}

- (void) testReferenceEqualityForFIRDatabase {
    FIRDatabase *db1 = [self databaseForURL:self.databaseURL name:@"db1"];
    FIRDatabase *db2 = [self databaseForURL:self.databaseURL name:@"db2"];
    FIRDatabase *altDb = [self databaseForURL:self.databaseURL name:@"altDb"];
    FIRDatabase *wrongHostDb = [self databaseForURL:@"http://tests.example.com"];

    FIRDatabaseReference *testRef1 = [db1 reference];
    FIRDatabaseReference *testRef2 = [db1 referenceWithPath:@"foo"];
    FIRDatabaseReference *testRef3 = [altDb reference];
    FIRDatabaseReference *testRef4 = [wrongHostDb reference];
    FIRDatabaseReference *testRef5 = [db2 reference];
    FIRDatabaseReference *testRef6 = [db2 reference];

    // Referential equality
    XCTAssertTrue(testRef1.database == testRef2.database);
    XCTAssertFalse(testRef1.database == testRef3.database);
    XCTAssertFalse(testRef1.database == testRef4.database);
    XCTAssertFalse(testRef1.database == testRef5.database);
    XCTAssertFalse(testRef1.database == testRef6.database);

    // references from same FIRDatabase same identical .database references.
    XCTAssertTrue(testRef5.database == testRef6.database);

    [db1 goOffline];
    [db2 goOffline];
    [altDb goOffline];
    [wrongHostDb goOffline];
}

- (FIRDatabaseReference *)rootRefWithEngine:(id<FStorageEngine>)engine name:(NSString *)name {
    FIRDatabaseConfig *config = [FIRDatabaseConfig configForName:name];
    config.persistenceEnabled = YES;
    config.forceStorageEngine = engine;
    return [[FIRDatabaseReference alloc] initWithConfig:config];
}

- (void) testPurgeWritesPurgesAllWrites {
    FMockStorageEngine *engine = [[FMockStorageEngine alloc] init];
    FIRDatabaseReference *ref = [self rootRefWithEngine:engine name:@"purgeWritesPurgesAllWrites"];
    FIRDatabase *database = ref.database;

    [database goOffline];

    [[ref childByAutoId] setValue:@"test-value-1"];
    [[ref childByAutoId] setValue:@"test-value-2"];
    [[ref childByAutoId] setValue:@"test-value-3"];
    [[ref childByAutoId] setValue:@"test-value-4"];

    [self waitForEvents:ref];

    XCTAssertEqual(engine.userWrites.count, (NSUInteger)4);

    [database purgeOutstandingWrites];
    [self waitForEvents:ref];
    XCTAssertEqual(engine.userWrites.count, (NSUInteger)0);

    [database goOnline];
}

- (void) testPurgeWritesAreCanceledInOrder {
    FMockStorageEngine *engine = [[FMockStorageEngine alloc] init];
    FIRDatabaseReference *ref = [self rootRefWithEngine:engine name:@"purgeWritesAndCanceledInOrder"];
    FIRDatabase *database = ref.database;

    [database goOffline];

    NSMutableArray *order = [NSMutableArray array];

    [[ref childByAutoId] setValue:@"test-value-1" withCompletionBlock:^(NSError *error, FIRDatabaseReference *ref) {
        XCTAssertEqual(error.code, kFErrorCodeWriteCanceled);
        [order addObject:@"1"];
    }];
    [[ref childByAutoId] setValue:@"test-value-2" withCompletionBlock:^(NSError *error, FIRDatabaseReference *ref) {
        XCTAssertEqual(error.code, kFErrorCodeWriteCanceled);
        [order addObject:@"2"];
    }];
    [[ref childByAutoId] setValue:@"test-value-3" withCompletionBlock:^(NSError *error, FIRDatabaseReference *ref) {
        XCTAssertEqual(error.code, kFErrorCodeWriteCanceled);
        [order addObject:@"3"];
    }];
    [[ref childByAutoId] setValue:@"test-value-4" withCompletionBlock:^(NSError *error, FIRDatabaseReference *ref) {
        XCTAssertEqual(error.code, kFErrorCodeWriteCanceled);
        [order addObject:@"4"];
    }];

    [self waitForEvents:ref];

    XCTAssertEqual(engine.userWrites.count, (NSUInteger)4);

    [database purgeOutstandingWrites];
    [self waitForEvents:ref];
    XCTAssertEqual(engine.userWrites.count, (NSUInteger)0);
    XCTAssertEqualObjects(order, (@[@"1", @"2", @"3", @"4"]));

    [database goOnline];
}

- (void)testPurgeWritesCancelsOnDisconnects {
    FMockStorageEngine *engine = [[FMockStorageEngine alloc] init];
    FIRDatabaseReference *ref = [self rootRefWithEngine:engine name:@"purgeWritesCancelsOnDisconnects"];
    FIRDatabase *database = ref.database;

    [database goOffline];

    NSMutableArray *events = [NSMutableArray array];

    [[ref childByAutoId] onDisconnectSetValue:@"test-value-1" withCompletionBlock:^(NSError *error, FIRDatabaseReference *ref) {
        XCTAssertEqual(error.code, kFErrorCodeWriteCanceled);
        [events addObject:@"1"];
    }];

    [[ref childByAutoId] onDisconnectSetValue:@"test-value-2" withCompletionBlock:^(NSError *error, FIRDatabaseReference *ref) {
        XCTAssertEqual(error.code, kFErrorCodeWriteCanceled);
        [events addObject:@"2"];
    }];

    [self waitForEvents:ref];

    [database purgeOutstandingWrites];

    [self waitForEvents:ref];

    XCTAssertEqualObjects(events, (@[@"1", @"2"]));
}

- (void) testPurgeWritesReraisesEvents {
    FMockStorageEngine *engine = [[FMockStorageEngine alloc] init];
    FIRDatabaseReference *ref = [[self rootRefWithEngine:engine name:@"purgeWritesReraiseEvents"] childByAutoId];
    FIRDatabase *database = ref.database;

    [self waitForCompletionOf:ref setValue:@{@"foo": @"foo-value", @"bar": @{@"qux": @"qux-value"}}];

    NSMutableArray *fooValues = [NSMutableArray array];
    NSMutableArray *barQuuValues = [NSMutableArray array];
    NSMutableArray *barQuxValues = [NSMutableArray array];
    NSMutableArray *cancelOrder = [NSMutableArray array];

    [[ref child:@"foo"] observeEventType:FIRDataEventTypeValue withBlock:^(FIRDataSnapshot *snapshot) {
        [fooValues addObject:snapshot.value];
    }];
    [[ref child:@"bar/quu"] observeEventType:FIRDataEventTypeValue withBlock:^(FIRDataSnapshot *snapshot) {
        [barQuuValues addObject:snapshot.value];
    }];
    [[ref child:@"bar/qux"] observeEventType:FIRDataEventTypeValue withBlock:^(FIRDataSnapshot *snapshot) {
        [barQuxValues addObject:snapshot.value];
    }];

    [database goOffline];

    [[ref child:@"foo"] setValue:@"new-foo-value" withCompletionBlock:^(NSError *error, FIRDatabaseReference *ref) {
        XCTAssertEqual(error.code, kFErrorCodeWriteCanceled);
        // This should be after we raised events
        XCTAssertEqualObjects(fooValues.lastObject, @"foo-value");
        [cancelOrder addObject:@"foo-1"];
    }];

    [[ref child:@"bar"] updateChildValues:@{@"quu": @"quu-value", @"qux": @"new-qux-value"}
                                     withCompletionBlock:^(NSError *error, FIRDatabaseReference *ref) {
        XCTAssertEqual(error.code, kFErrorCodeWriteCanceled);
        // This should be after we raised events
        XCTAssertEqualObjects(barQuxValues.lastObject, @"qux-value");
        XCTAssertEqualObjects(barQuuValues.lastObject, [NSNull null]);
        [cancelOrder addObject:@"bar"];
    }];

    [[ref child:@"foo"] setValue:@"newest-foo-value" withCompletionBlock:^(NSError *error, FIRDatabaseReference *ref) {
        XCTAssertEqual(error.code, kFErrorCodeWriteCanceled);
        // This should be after we raised events
        XCTAssertEqualObjects(fooValues.lastObject, @"foo-value");
        [cancelOrder addObject:@"foo-2"];
    }];

    [database purgeOutstandingWrites];

    [self waitForEvents:ref];

    XCTAssertEqualObjects(cancelOrder, (@[@"foo-1", @"bar", @"foo-2"]));
    XCTAssertEqualObjects(fooValues, (@[@"foo-value", @"new-foo-value", @"newest-foo-value", @"foo-value"]));
    XCTAssertEqualObjects(barQuuValues, (@[[NSNull null], @"quu-value", [NSNull null]]));
    XCTAssertEqualObjects(barQuxValues, (@[@"qux-value", @"new-qux-value", @"qux-value"]));

    [database goOnline];
    // Make sure we're back online and reconnected again
    [self waitForRoundTrip:ref];

    // No events should be reraised
    XCTAssertEqualObjects(cancelOrder, (@[@"foo-1", @"bar", @"foo-2"]));
    XCTAssertEqualObjects(fooValues, (@[@"foo-value", @"new-foo-value", @"newest-foo-value", @"foo-value"]));
    XCTAssertEqualObjects(barQuuValues, (@[[NSNull null], @"quu-value", [NSNull null]]));
    XCTAssertEqualObjects(barQuxValues, (@[@"qux-value", @"new-qux-value", @"qux-value"]));
}

- (void)testPurgeWritesCancelsTransactions {
    FMockStorageEngine *engine = [[FMockStorageEngine alloc] init];
    FIRDatabaseReference *ref = [[self rootRefWithEngine:engine name:@"purgeWritesCancelsTransactions"] childByAutoId];
    FIRDatabase *database = ref.database;

    NSMutableArray *events = [NSMutableArray array];

    [ref observeEventType:FIRDataEventTypeValue withBlock:^(FIRDataSnapshot *snapshot) {
        [events addObject:[NSString stringWithFormat:@"value-%@", snapshot.value]];
    }];

    // Make sure the first value event is fired
    [self waitForRoundTrip:ref];

    [database goOffline];

    [ref runTransactionBlock:^FIRTransactionResult *(FIRMutableData *currentData) {
        [currentData setValue:@"1"];
        return [FIRTransactionResult successWithValue:currentData];
    } andCompletionBlock:^(NSError *error, BOOL committed, FIRDataSnapshot *snapshot) {
        XCTAssertEqual(error.code, kFErrorCodeWriteCanceled);
        [events addObject:@"cancel-1"];
    }];

    [ref runTransactionBlock:^FIRTransactionResult *(FIRMutableData *currentData) {
        [currentData setValue:@"2"];
        return [FIRTransactionResult successWithValue:currentData];
    } andCompletionBlock:^(NSError *error, BOOL committed, FIRDataSnapshot *snapshot) {
        XCTAssertEqual(error.code, kFErrorCodeWriteCanceled);
        [events addObject:@"cancel-2"];
    }];

    [database purgeOutstandingWrites];

    [self waitForEvents:ref];

    // The order should really be cancel-1 then cancel-2, but meh, to difficult to implement currently...
    XCTAssertEqualObjects(events, (@[@"value-<null>", @"value-1", @"value-2", @"value-<null>", @"cancel-2", @"cancel-1"]));
}

- (void) testPersistenceEnabled {
    id app = [[FIRFakeApp alloc] initWithName:@"testPersistenceEnabled" URL:self.databaseURL];
    FIRDatabase *database = [FIRDatabase databaseForApp:app];
    database.persistenceEnabled = YES;
    XCTAssertTrue(database.persistenceEnabled);

    // Just do a dummy observe that should get null added to the persistent cache.
    FIRDatabaseReference *ref = [[database reference] childByAutoId];
    [self waitForValueOf:ref toBe:[NSNull null]];

    // Now go offline and since null is cached offline, our observer should still complete.
    [database goOffline];
    [self waitForValueOf:ref toBe:[NSNull null]];
}

- (void) testPersistenceCacheSizeBytes {
    id app = [[FIRFakeApp alloc] initWithName:@"testPersistenceCacheSizeBytes" URL:self.databaseURL];
    FIRDatabase *database = [FIRDatabase databaseForApp:app];
    database.persistenceEnabled = YES;

    int oneMegabyte = 1 * 1024 * 1024;

    XCTAssertThrows([database setPersistenceCacheSizeBytes: 1], @"Cache must be a least 1 MB.");
    XCTAssertThrows([database setPersistenceCacheSizeBytes: 101 * oneMegabyte],
                    @"Cache must be less than 100 MB.");
    database.persistenceCacheSizeBytes = 2 * oneMegabyte;
    XCTAssertEqual(2 * oneMegabyte, database.persistenceCacheSizeBytes);

    [database reference];  // Initialize database.

    XCTAssertThrows([database setPersistenceCacheSizeBytes: 3 * oneMegabyte],
                    @"Persistence can't be changed after initialization.");
    XCTAssertEqual(2 * oneMegabyte, database.persistenceCacheSizeBytes);
}

- (void) testCallbackQueue {
    id app = [[FIRFakeApp alloc] initWithName:@"testCallbackQueue" URL:self.databaseURL];
    FIRDatabase *database = [FIRDatabase databaseForApp:app];
    dispatch_queue_t callbackQueue = dispatch_queue_create("testCallbackQueue", NULL);
    database.callbackQueue = callbackQueue;
    XCTAssertEqual(callbackQueue, database.callbackQueue);

    __block BOOL done = NO;
    [database.reference.childByAutoId observeSingleEventOfType:FIRDataEventTypeValue
                                                     withBlock:^(FIRDataSnapshot *snapshot) {
        dispatch_assert_queue(callbackQueue);
        done = YES;
    }];
    WAIT_FOR(done);
    [database goOffline];
}

- (FIRDatabase *) defaultDatabase {
    return [self databaseForURL:self.databaseURL];
}

- (FIRDatabase *) databaseForURL:(NSString *)url {
    NSString *name = [NSString stringWithFormat:@"url:%@", url];
    return [self databaseForURL:url name:name];
}

- (FIRDatabase *) databaseForURL:(NSString *)url name:(NSString *)name {
    id app = [[FIRFakeApp alloc] initWithName:name URL:url];
    return [FIRDatabase databaseForApp:app];
}
@end
