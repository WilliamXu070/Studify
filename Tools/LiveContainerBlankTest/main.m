#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *postButton;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    UIViewController *viewController = [UIViewController new];
    viewController.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.08 blue:0.10 alpha:1.0];

    UIStackView *stackView = [UIStackView new];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentFill;
    stackView.spacing = 18;

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = @"Studify Blank IPA";
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 0;

    UILabel *bodyLabel = [UILabel new];
    bodyLabel.text = @"If you can see this, LiveContainer can launch a normal standalone IPA. Use the button below to test plain HTTP from this app to your Mac server.";
    bodyLabel.textColor = [UIColor colorWithWhite:0.82 alpha:1.0];
    bodyLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    bodyLabel.textAlignment = NSTextAlignmentCenter;
    bodyLabel.numberOfLines = 0;

    self.statusLabel = [UILabel new];
    self.statusLabel.text = @"Status: launched";
    self.statusLabel.textColor = [UIColor colorWithRed:0.63 green:0.86 blue:1.0 alpha:1.0];
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightSemibold];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;

    self.postButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.postButton setTitle:@"Send POST Test" forState:UIControlStateNormal];
    [self.postButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.postButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    self.postButton.backgroundColor = [UIColor colorWithRed:0.10 green:0.42 blue:0.95 alpha:1.0];
    self.postButton.layer.cornerRadius = 8;
    self.postButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.postButton.heightAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;
    [self.postButton addTarget:self action:@selector(sendPostTest) forControlEvents:UIControlEventTouchUpInside];

    [stackView addArrangedSubview:titleLabel];
    [stackView addArrangedSubview:bodyLabel];
    [stackView addArrangedSubview:self.statusLabel];
    [stackView addArrangedSubview:self.postButton];
    [viewController.view addSubview:stackView];

    UILayoutGuide *safeArea = viewController.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stackView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:24],
        [stackView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-24],
        [stackView.centerYAnchor constraintEqualToAnchor:safeArea.centerYAnchor]
    ]];

    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];

    return YES;
}

- (void)sendPostTest {
    NSURL *url = [NSURL URLWithString:@"http://172.18.147.149:8787/v1/jobs/playlist"];
    if (!url) {
        [self updateStatus:@"Status: invalid URL" color:[UIColor systemRedColor]];
        return;
    }

    [self updateStatus:@"Status: sending POST..." color:[UIColor colorWithRed:0.63 green:0.86 blue:1.0 alpha:1.0]];
    self.postButton.enabled = NO;
    self.postButton.alpha = 0.65;

    UIDevice *device = UIDevice.currentDevice;
    NSString *deviceId = device.identifierForVendor.UUIDString ?: @"unknown";
    NSString *bundleId = NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
    NSString *sentAt = [NSISO8601DateFormatter.new stringFromDate:NSDate.date];

    NSDictionary *payload = @{
        @"playlistUri": @"spotify:playlist:livecontainer-blank-test",
        @"playlistUrl": @"https://open.spotify.com/playlist/livecontainer-blank-test",
        @"deviceId": deviceId,
        @"deviceName": device.name ?: @"unknown",
        @"clientVersion": @"studify-blank-ios-0.1",
        @"spotifyVersion": @"blank-test",
        @"sentAt": sentAt,
        @"bundleIdentifier": bundleId
    };

    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 12;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"studify-blank-ios-0.1" forHTTPHeaderField:@"X-Studify-Client"];
    request.HTTPBody = body;

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.postButton.enabled = YES;
            self.postButton.alpha = 1.0;

            if (error) {
                [self updateStatus:[NSString stringWithFormat:@"Status: request failed\n%@", error.localizedDescription]
                              color:[UIColor systemRedColor]];
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSString *bodyText = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            [self updateStatus:[NSString stringWithFormat:@"Status: HTTP %ld\n%@", (long)httpResponse.statusCode, bodyText ?: @""]
                          color:[UIColor systemGreenColor]];
        });
    }];

    [task resume];
}

- (void)updateStatus:(NSString *)status color:(UIColor *)color {
    self.statusLabel.text = status;
    self.statusLabel.textColor = color;
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
