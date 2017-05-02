#import "AppDelegate.h"

#import "Token-Swift.h"

#import "NSData+ows_StripToken.h"
#import "EmptyCallHandler.h"

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
#import <SignalServiceKit/OWSDispatch.h>

#import <AxolotlKit/SessionCipher.h>

@import WebRTC;

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

    // Set the seed the generator for rand().
    //
    // We should always use arc4random() instead of rand(), but we
    // still want to ensure that any third-party code that uses rand()
    // gets random values.
    srand((unsigned int)time(NULL));

    [self verifyDBKeysAvailableBeforeBackgroundLaunch];

    [self setupBasicAppearance];
    [self setupTSKitEnv];
    [self setupSignalService];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userDidSignOut) name:@"UserDidSignOut" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(createNewUser) name:@"CreateNewUser" object:nil];

    [self configureAndPresentWindow];

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"RequiresSignIn"]) {
        [self presentSignIn];
    } else {
        [self createNewUserOrMigrateIfNeeded];
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
        [[TSStorageManager sharedManager] resetSignalStorage];
        [[Yap sharedInstance] wipeStorage];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"RequiresSignIn"];
        exit(0);
    } failure:^(NSError *error) {
        // alert user
        NSLog(@"Error attempting to unregister text secure.");
    }];
}

- (void)createNewUserOrMigrateIfNeeded {
    if (TokenUser.current == nil) {
        [[IDAPIClient shared] registerUserIfNeeded:^{
            [[ChatAPIClient shared] registerUser];
            [self didCreateUser];
        }];
    } if (TokenUser.current.needsMigration) {
        // migrate
        [[IDAPIClient shared] retrieveUserWithUsername:[TokenUser.current username] completion:^(TokenUser * _Nullable user) {
            if (user == nil) {
                exit(-1);
            } else {

            }
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
                [[ChatAPIClient shared] registerUser];
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
    [navBarAppearance setTintColor:[Theme tintColor]];
    [navBarAppearance setBarTintColor:[Theme navigationBarColor]];

    attributtes = @{NSForegroundColorAttributeName: [Theme tintColor], NSFontAttributeName: [Theme regularWithSize:17]};
    UIBarButtonItem *barButtonAppearance = [UIBarButtonItem appearanceWhenContainedInInstancesOfClasses:@[[UINavigationBar class]]];
    [barButtonAppearance setTitleTextAttributes:attributtes forState:UIControlStateNormal];
}

- (void)setupSignalService {
    // Encryption/Descryption mutates session state and must be synchronized on a serial queue.
    [SessionCipher setSessionCipherDispatchQueue:[OWSDispatch sessionStoreQueue]];

    [[TSStorageManager sharedManager] storePhoneNumber:[[Cereal shared] address]];
    [[TSAccountManager sharedInstance] ifRegistered:YES runAsync:^{

        [TSSocketManager requestSocketOpen];
        RTCInitializeSSL();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self registerForRemoteNotifications];
        });
    }];
}

- (void)setupTSKitEnv {
    self.networkManager = [TSNetworkManager sharedManager];
    self.contactsManager = [[ContactsManager alloc] init];
    self.contactsUpdater = [ContactsUpdater sharedUpdater];

    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    [storageManager setupDatabase];

    self.messageSender = [[OWSMessageSender alloc] initWithNetworkManager:self.networkManager storageManager:storageManager contactsManager:self.contactsManager contactsUpdater:self.contactsUpdater];

    TextSecureKitEnv *sharedEnv = [[TextSecureKitEnv alloc] initWithCallMessageHandler:[[EmptyCallHandler alloc] init] contactsManager:self.contactsManager messageSender:self.messageSender notificationsManager:[[SignalNotificationManager alloc] init]];
    [TextSecureKitEnv setSharedEnv:sharedEnv];

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
                // [TSSocketManager resignActivity];
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
        [TSSocketManager requestSocketOpen];
    }];

    [self deactivateScreenProtection];
    [TSPreKeyManager checkPreKeysIfNecessary];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)activateScreenProtection {
    if (self.screenProtectionWindow == nil) {
        UIWindow *window = [[UIWindow alloc] init];
        window.hidden = YES;
        window.backgroundColor = [UIColor clearColor];
        window.userInteractionEnabled = NO;
        window.windowLevel = CGFLOAT_MAX;

        UIVisualEffectView *effectView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraLight]];
        effectView.alpha = 0.9;

        [window addSubview:effectView];

        [effectView setTranslatesAutoresizingMaskIntoConstraints:NO];
        [[effectView.topAnchor constraintEqualToAnchor:window.topAnchor] setActive:YES];
        [[effectView.leftAnchor constraintEqualToAnchor:window.leftAnchor] setActive:YES];
        [[effectView.bottomAnchor constraintEqualToAnchor:window.bottomAnchor] setActive:YES];
        [[effectView.rightAnchor constraintEqualToAnchor:window.rightAnchor] setActive:YES];

        self.screenProtectionWindow = window;
    }

    self.screenProtectionWindow.hidden = NO;
}

- (void)deactivateScreenProtection {
    self.screenProtectionWindow.hidden = YES;
}

- (void)verifyDBKeysAvailableBeforeBackgroundLaunch {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateBackground) {
        return;
    }

    if (![TSStorageManager isDatabasePasswordAccessible]) {
        exit(0);
    }
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

    } failure:^(NSError *error) {
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
    NSLog(@"Failed to register for remote notifications. %@", error);
}

@end
