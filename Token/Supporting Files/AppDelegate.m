#import "AppDelegate.h"

#import "Token-Swift.h"

#import "NSData+ows_StripToken.h"

#import <EtherealCereal/EtherealCereal.h>

#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <SignalServiceKit/TSStorageManager+keyingMaterial.h>
#import <SignalServiceKit/OWSSyncContactsMessage.h>
#import <SignalServiceKit/NSDate+millisecondTimeStamp.h>
#import <SignalServiceKit/TextSecureKitEnv.h>
#import <SignalServiceKit/OWSIncomingMessageReadObserver.h>
#import <SignalServiceKit/TSSocketManager.h>

@interface AppDelegate ()

@property (nonatomic) OWSIncomingMessageReadObserver *incomingMessageReadObserver;

@property (nonatomic) OWSMessageFetcherJob *messageFetcherJob;

@property (nonatomic) UIWindow *screenProtectionWindow;

@property (nonatomic) NSString *token;
@property (nonatomic) NSString *voipToken;

@end

@implementation AppDelegate
@synthesize token = _token;
@synthesize voipToken = _voipToken;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSString *tokenChatServiceBaseURL = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"TokenChatServiceBaseURL"];
    [OWSSignalService setBaseURL:tokenChatServiceBaseURL];

    [self setupBasicAppearance];
    [self setupTSKitEnv];
    [self setupSignalService];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userDidSignOut) name:@"UserDidSignOut" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(createNewUser) name:@"CreateNewUser" object:nil];

    [self configureAndPresentWindow];

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"RequiresSignIn"]) {
        [self presentSignIn];
    } else {
        [self createNewUser];
    }

    return YES;
}

- (void)configureAndPresentWindow {
    self.window = [[UIWindow alloc] init];
    self.window.backgroundColor = [Theme viewBackgroundColor];
    self.window.rootViewController = [[TabBarController alloc] init];

    [self.window makeKeyAndVisible];
}

- (void)handleFirstLaunch {
    // To drive this point really home we could show this for every launch instead.
//    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DidShowMoneyAlert"]) {
//        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Be aware!" message:@"This is a beta version of Token. It can be unstable, and it's possible that you lose money." preferredStyle:UIAlertControllerStyleAlert];
//        [alert addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDefault handler:nil]];
//
//        [self.window.rootViewController presentViewController:alert animated:YES completion:^{
//            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DidShowMoneyAlert"];
//        }];
//    }
}

- (void)userDidSignOut {
    [TSAccountManager unregisterTextSecureWithSuccess:^{
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[TSStorageManager sharedManager] wipeSignalStorage];
        [[Yap sharedInstance] wipeStorage];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"RequiresSignIn"];
        exit(0);
    } failure:^(NSError * _Nonnull error) {
        // alert user
        NSLog(@"Error attempting to unregister text secure.");
    }];
}

- (void)createNewUser {
    if (TokenUser.current == nil) {
        [[IDAPIClient shared] registerUserIfNeeded:^{
            [[ChatAPIClient shared] registerUser];
            [self didCreateUser];
        }];
    } else {
        [[IDAPIClient shared] retrieveUserWithUsername:[TokenUser.current username] completion:^(TokenUser * _Nullable user) {
            NSLog(@"%@", user);
            if (user == nil) {
                [[IDAPIClient shared] registerUserIfNeeded:^{
                    [[ChatAPIClient shared] registerUser];
                    [self didCreateUser];
                }];
            } else {
                [self didCreateUser];
                [self handleFirstLaunch];
            }
        }];
    }
}

- (void)didCreateUser {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"RequiresSignIn"];
    [self.window.rootViewController dismissViewControllerAnimated:YES completion: NULL];
}

- (void)presentSignIn {
    SignInNavigationController *signInNavigationController = [[SignInNavigationController alloc] init];
    [self.window.rootViewController presentViewController:signInNavigationController animated:NO completion:nil];
}

- (void)setupBasicAppearance {
    NSDictionary *attributtes = @{NSForegroundColorAttributeName: [Theme navigationTitleTextColor], NSFontAttributeName: [Theme boldWithSize:17]};

    UINavigationBar *navBarAppearance = [UINavigationBar appearance];
    [navBarAppearance setTitleTextAttributes:attributtes];
    [navBarAppearance setTintColor:[Theme navigationTitleTextColor]];
    [navBarAppearance setBarTintColor:[Theme navigationBarColor]];

    attributtes = @{NSForegroundColorAttributeName: [Theme tintColor], NSFontAttributeName: [Theme regularWithSize:17]};
    UIBarButtonItem *barButtonAppearance = [UIBarButtonItem appearanceWhenContainedInInstancesOfClasses:@[[UINavigationBar class]]];
    [barButtonAppearance setTitleTextAttributes:attributtes forState:UIControlStateNormal];
}

- (void)setupSignalService {
    [[TSStorageManager sharedManager] storePhoneNumber:[[Cereal shared] address]];
    UIApplicationState launchState = [UIApplication sharedApplication].applicationState;
    [[TSAccountManager sharedInstance] ifRegistered:YES runAsync:^{
        if (launchState == UIApplicationStateInactive) {
            NSLog(@"The app was launched from inactive");
            [TSSocketManager becomeActiveFromForeground];
        } else if (launchState == UIApplicationStateBackground) {
            NSLog(@"The app was launched from being backgrounded");
            [TSSocketManager becomeActiveFromBackgroundExpectMessage:NO];
        } else {
            NSLog(@"The app was launched in an unknown way");
        }

        [TSPreKeyManager refreshPreKeys];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self registerForRemoteNotifications];
        });
    }];
}

- (void)setupTSKitEnv {
    [TextSecureKitEnv sharedEnv].contactsManager = [[ContactsManager alloc] init];
    [TextSecureKitEnv sharedEnv].notificationsManager = [[SignalNotificationManager alloc] init];
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    [storageManager setupDatabase];

    self.networkManager = [TSNetworkManager sharedManager];
    self.contactsManager = [[ContactsManager alloc] init];
    self.contactsUpdater = [[ContactsUpdater alloc] init];

    self.messageSender = [[OWSMessageSender alloc] initWithNetworkManager:self.networkManager storageManager:storageManager contactsManager:self.contactsManager contactsUpdater:self.contactsUpdater];

    self.incomingMessageReadObserver = [[OWSIncomingMessageReadObserver alloc] initWithStorageManager:storageManager messageSender:self.messageSender];
    [self.incomingMessageReadObserver startObserving];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    [SignalNotificationManager updateApplicationBadgeNumber];

    UIBackgroundTaskIdentifier __block bgTask = UIBackgroundTaskInvalid;
    bgTask = [application beginBackgroundTaskWithExpirationHandler:^{ }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if ([TSAccountManager isRegistered]) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self activateScreenProtection];
                [TSSocketManager resignActivity];
            });
        }

        [application endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    });
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [SignalNotificationManager updateApplicationBadgeNumber];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    [SignalNotificationManager updateApplicationBadgeNumber];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [[TSAccountManager sharedInstance] ifRegistered:YES runAsync:^{
        // We're double checking that the app is active, to be sure since we
        // can't verify in production env due to code
        // signing.
        [TSSocketManager becomeActiveFromForeground];
    }];

    [self deactivateScreenProtection];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)activateScreenProtection {
    if (self.screenProtectionWindow == nil) {
        UIWindow *window = [[UIWindow alloc] init];
        window.hidden = YES;
        window.opaque = YES;
        window.userInteractionEnabled = NO;
        window.windowLevel = CGFLOAT_MAX;
        [window setBackgroundColor:[UIColor whiteColor]];

        self.screenProtectionWindow = window;
    }

    self.screenProtectionWindow.hidden = NO;
}

- (void)deactivateScreenProtection {
    self.screenProtectionWindow.hidden = YES;
}

#pragma mark - Accessors 

- (NSString *)token {
    if (!_token) {
        _token = @"";
    }

    return _token;
}

- (NSString *)voipToken {
    if (!_voipToken) {
        _voipToken = @"";
    }

    return _voipToken;
}

- (void)setToken:(NSString *)token {
    _token = token;

    [self updateRemoteNotificationCredentials];
}

- (void)setVoipToken:(NSString *)voipToken {
    _voipToken = voipToken;

    [self updateRemoteNotificationCredentials];
}

#pragma mark - Push notifications

- (void)registerForRemoteNotifications {
    UNAuthorizationOptions authOptions = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;

    [center requestAuthorizationWithOptions:authOptions completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (error){
            @throw error.localizedDescription;
        } else if (granted) {
            [[UIApplication sharedApplication] registerForRemoteNotifications];
        }
    }];

    OWSSignalService *signalService = [OWSSignalService new];
    self.messageFetcherJob = [[OWSMessageFetcherJob alloc] initWithMessagesManager:[TSMessagesManager sharedManager] messageSender:self.messageSender networkManager:self.networkManager signalService:signalService];

    PKPushRegistry *voipRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    voipRegistry.delegate = self;
    voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}

- (void)updateRemoteNotificationCredentials {
    [[TSAccountManager sharedInstance] registerForPushNotificationsWithPushToken:self.token voipToken:self.voipToken success:^{
        NSLog(@"TOKEN: chat PN register - SUCCESS: token: %@, voip: %@", self.token, self.voipToken);

        [[EthereumAPIClient shared] registerForNotifications: ^(BOOL success){
            if (success) {
                [[EthereumAPIClient shared] registerForPushNotificationsWithDeviceToken:self.token];
            }
        }];

    } failure:^(NSError * _Nonnull error) {
        NSLog(@"TOKEN: chat PN register - FAILURE: %@", error.localizedDescription);
    }];
}

- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(PKPushType)type {
    [self.messageFetcherJob runAsync];
}

- (void)pushRegistry:(PKPushRegistry *)registry didInvalidatePushTokenForType:(PKPushType)type {

}

- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(PKPushType)type {
    self.voipToken = [credentials.token ows_tripToken];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    [BackgroundNotificationHandler handle:notification :^(UNNotificationPresentationOptions options) {
        completionHandler(options);
    }];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)())completionHandler {
    NSString *identifier = response.notification.request.content.threadIdentifier;
    [Navigator navigateTo:identifier animated:YES];

    completionHandler();
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {

    [SignalNotificationHandler handleMessage:userInfo completion:^(UIBackgroundFetchResult result) {
        if (result == UIBackgroundFetchResultNewData) {
            [self.messageFetcherJob runAsync];
        }

        completionHandler(result);
    }];

    [EthereumNotificationHandler handlePayment:userInfo completion:^(UIBackgroundFetchResult result) {
        completionHandler(result);
    }];
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    self.token = [deviceToken hexadecimalString];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    NSLog(@"!");
}

@end
