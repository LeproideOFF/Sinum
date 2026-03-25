// Copyright (c) 2025 Project Nova LLC
// Hook Fortnite 9.41 - Version complète + Mod Menu Debug v3.2.0

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

#define API_URL @"http://127.0.0.1:3551"
#define EPIC_GAMES_URL @"ol.epicgames.com"
#define LOG_SERVER @"http://127.0.0.1:3551/nova/log"
#define HOOK_VERSION @"3.2.0"

// ─────────────────────────────────────────
// MARK: - Logger centralisé
// ─────────────────────────────────────────

void NovaLog(NSString *level, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[NOVA][%@] %@", level, msg);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSString *encoded = [msg stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *urlStr = [NSString stringWithFormat:@"%@?level=%@&msg=%@", LOG_SERVER, level, encoded];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
        [NSURLProtocol setProperty:@YES forKey:@"Handled" inRequest:req];
        [[NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:urlStr]] resume];
    });
}

// ─────────────────────────────────────────
// MARK: - Historique requêtes
// ─────────────────────────────────────────

static NSMutableArray<NSDictionary *> *requestHistory;
static NSInteger totalRequests = 0;
static NSInteger failedRequests = 0;

void addToHistory(NSString *method, NSString *url, NSInteger status, double ms) {
    if (!requestHistory) requestHistory = [NSMutableArray array];
    if (requestHistory.count >= 100) [requestHistory removeObjectAtIndex:0];
    [requestHistory addObject:@{
        @"method": method ?: @"GET",
        @"url": url ?: @"",
        @"status": @(status),
        @"ms": @(ms),
        @"time": [NSDate date]
    }];
    totalRequests++;
    if (status >= 400 || status == 0) failedRequests++;
}

// ─────────────────────────────────────────
// MARK: - Helper rootViewController
// ─────────────────────────────────────────

static UIViewController *NovaRootViewController() {
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *window in scene.windows) {
                if (window.isKeyWindow) return window.rootViewController;
            }
        }
    }
    return nil;
}

// ─────────────────────────────────────────
// MARK: - Mod Menu Controller
// ─────────────────────────────────────────

@interface NovaMenuController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *statsLabel;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, assign) BOOL showOnlyErrors;
@end

@implementation NovaMenuController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.showOnlyErrors = NO;
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:0.97];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 50, self.view.bounds.size.width, 40)];
    title.text = [NSString stringWithFormat:@"🔧 Nova Hook v%@ — Debug Menu", HOOK_VERSION];
    title.textColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:15];
    [self.view addSubview:title];

    self.statsLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 95, self.view.bounds.size.width - 20, 40)];
    self.statsLabel.textColor = [UIColor lightGrayColor];
    self.statsLabel.font = [UIFont systemFontOfSize:11];
    self.statsLabel.numberOfLines = 2;
    [self.view addSubview:self.statsLabel];
    [self updateStats];

    NSArray *buttons = @[
        @{@"title": @"📋 Copier Historique",  @"sel": @"copyHistory"},
        @{@"title": @"🗑 Vider Historique",    @"sel": @"clearHistory"},
        @{@"title": @"⚠️ Filtrer Erreurs",     @"sel": @"toggleErrors"},
        @{@"title": @"📡 Tester Backend",      @"sel": @"testBackend"},
        @{@"title": @"🔄 Reset Compteurs",     @"sel": @"resetCounters"},
        @{@"title": @"📤 Exporter JSON",       @"sel": @"exportJSON"},
        @{@"title": @"🔁 Recharger Timeline",  @"sel": @"reloadTimeline"},
        @{@"title": @"👤 Infos Compte",        @"sel": @"showAccountInfo"},
    ];

    CGFloat btnY = 140;
    for (NSDictionary *btn in buttons) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(10, btnY, self.view.bounds.size.width - 20, 36);
        [b setTitle:btn[@"title"] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13];
        b.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:1.0];
        b.layer.cornerRadius = 8;
        b.layer.borderWidth = 0.5;
        b.layer.borderColor = [UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:0.5].CGColor;
        [b addTarget:self action:NSSelectorFromString(btn[@"sel"]) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:b];
        btnY += 42;
    }

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, btnY + 10, self.view.bounds.size.width, self.view.bounds.size.height - btnY - 10) style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    [self.view addSubview:self.tableView];

    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refreshUI) userInfo:nil repeats:YES];
}

- (void)updateStats {
    self.statsLabel.text = [NSString stringWithFormat:
        @"✅ Total: %ld   ❌ Erreurs: %ld   📶 %@",
        (long)totalRequests, (long)failedRequests, API_URL];
    self.statsLabel.textColor = failedRequests > 0
        ? [UIColor colorWithRed:1 green:0.4 blue:0.4 alpha:1]
        : [UIColor colorWithRed:0.4 green:1 blue:0.6 alpha:1];
}

- (void)refreshUI {
    [self updateStats];
    [self.tableView reloadData];
}

- (void)copyHistory {
    NSMutableString *text = [NSMutableString string];
    for (NSDictionary *e in requestHistory) {
        [text appendFormat:@"[%@] %@ %@ → %ld (%.0fms)\n",
            e[@"time"], e[@"method"], e[@"url"],
            [(NSNumber*)e[@"status"] longValue],
            [(NSNumber*)e[@"ms"] doubleValue]];
    }
    [UIPasteboard generalPasteboard].string = text;
    [self showToast:@"✅ Historique copié !"];
}

- (void)clearHistory {
    [requestHistory removeAllObjects];
    [self.tableView reloadData];
    [self showToast:@"🗑 Historique vidé"];
}

- (void)toggleErrors {
    self.showOnlyErrors = !self.showOnlyErrors;
    [self.tableView reloadData];
    [self showToast:self.showOnlyErrors ? @"⚠️ Erreurs uniquement" : @"📋 Tout afficher"];
}

- (void)resetCounters {
    totalRequests = 0;
    failedRequests = 0;
    [self updateStats];
    [self showToast:@"🔄 Compteurs réinitialisés"];
}

- (void)exportJSON {
    NSError *err;
    NSData *data = [NSJSONSerialization dataWithJSONObject:requestHistory ?: @[] options:NSJSONWritingPrettyPrinted error:&err];
    if (data) {
        [UIPasteboard generalPasteboard].string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [self showToast:@"📤 JSON copié !"];
    }
}

- (void)testBackend {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/lightswitch/api/service/bulk/status", API_URL]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [NSURLProtocol setProperty:@YES forKey:@"Handled" inRequest:req];
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        double ms = (CFAbsoluteTimeGetCurrent() - start) * 1000;
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)r;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!e && http.statusCode == 200)
                [self showToast:[NSString stringWithFormat:@"✅ Backend OK %.0fms", ms]];
            else
                [self showToast:[NSString stringWithFormat:@"❌ Backend DOWN: %@", e.localizedDescription]];
        });
    }] resume];
}

- (void)reloadTimeline {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/fortnite/api/calendar/v1/timeline", API_URL]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [NSURLProtocol setProperty:@YES forKey:@"Handled" inRequest:req];
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)r;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showToast:http.statusCode == 200 ? @"✅ Timeline OK" : @"❌ Timeline erreur"];
        });
    }] resume];
}

- (void)showAccountInfo {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/account/api/public/account/0000000000000000000000000000001", API_URL]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [NSURLProtocol setProperty:@YES forKey:@"Handled" inRequest:req];
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSString *json = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"Erreur";
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"👤 Compte" message:json preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    }] resume];
}

- (void)showToast:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        UILabel *toast = [[UILabel alloc] init];
        toast.text = msg;
        toast.textColor = [UIColor whiteColor];
        toast.backgroundColor = [UIColor colorWithRed:0.1 green:0.5 blue:0.3 alpha:0.95];
        toast.textAlignment = NSTextAlignmentCenter;
        toast.font = [UIFont systemFontOfSize:13];
        toast.layer.cornerRadius = 10;
        toast.clipsToBounds = YES;
        toast.frame = CGRectMake(20, self.view.bounds.size.height - 100, self.view.bounds.size.width - 40, 40);
        [self.view addSubview:toast];
        [UIView animateWithDuration:0.3 delay:1.5 options:0 animations:^{ toast.alpha = 0; } completion:^(BOOL f){ [toast removeFromSuperview]; }];
    });
}

- (NSArray *)filteredHistory {
    if (self.showOnlyErrors) {
        return [requestHistory filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, id b) {
            return [(NSNumber*)e[@"status"] integerValue] >= 400;
        }]];
    }
    return requestHistory ?: @[];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [self filteredHistory].count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
    NSDictionary *e = [self filteredHistory][ip.row];
    NSInteger status = [(NSNumber*)e[@"status"] integerValue];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", e[@"method"], [e[@"url"] lastPathComponent]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld • %.0fms • %@", (long)status, [(NSNumber*)e[@"ms"] doubleValue], e[@"url"]];
    cell.textLabel.font = [UIFont systemFontOfSize:12];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:10];
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = status >= 400 ? [UIColor colorWithRed:1 green:0.4 blue:0.4 alpha:1] : [UIColor colorWithRed:0.4 green:1 blue:0.6 alpha:1];
    cell.detailTextLabel.textColor = [UIColor grayColor];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip { return 48; }

@end

// ─────────────────────────────────────────
// MARK: - Bouton flottant
// ─────────────────────────────────────────

@interface NovaFloatingButton : UIWindow
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, strong) NovaMenuController *menuVC;
@end

@implementation NovaFloatingButton

- (instancetype)initWithWindowScene:(UIWindowScene *)scene {
    self = [super initWithWindowScene:scene];
    if (self) {
        self.frame = CGRectMake(10, 100, 55, 55);
        self.windowLevel = UIWindowLevelAlert + 1;
        self.backgroundColor = [UIColor clearColor];

        self.button = [UIButton buttonWithType:UIButtonTypeCustom];
        self.button.frame = self.bounds;
        [self.button setTitle:@"🔧" forState:UIControlStateNormal];
        self.button.titleLabel.font = [UIFont systemFontOfSize:26];
        self.button.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.15 alpha:0.9];
        self.button.layer.cornerRadius = 27;
        self.button.layer.borderWidth = 1.5;
        self.button.layer.borderColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:0.8].CGColor;
        [self.button addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self.button addGestureRecognizer:pan];
        [self addSubview:self.button];
        [self makeKeyAndVisible];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint delta = [gesture translationInView:self];
    self.center = CGPointMake(self.center.x + delta.x, self.center.y + delta.y);
    [gesture setTranslation:CGPointMake(0, 0) inView:self];
}

- (void)openMenu {
    UIViewController *root = NovaRootViewController();
    if (!root) return;
    self.menuVC = [[NovaMenuController alloc] init];
    self.menuVC.modalPresentationStyle = UIModalPresentationPageSheet;
    [root presentViewController:self.menuVC animated:YES completion:nil];
    NovaLog(@"MENU", @"Menu ouvert");
}

@end

// ─────────────────────────────────────────
// MARK: - CustomURLProtocol
// ─────────────────────────────────────────

@interface CustomURLProtocol : NSURLProtocol <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, assign) CFAbsoluteTime startTime;
@property (nonatomic, copy) NSString *originalURL;
@property (nonatomic, copy) NSString *method;
@end

@implementation CustomURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *url = request.URL.absoluteString;
    if ([url containsString:@"/nova/log"]) return NO;
    if ([url containsString:@"/CloudDir/"]) return NO;
    if ([url containsString:EPIC_GAMES_URL]) {
        if ([NSURLProtocol propertyForKey:@"Handled" inRequest:request]) return NO;
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }

- (void)startLoading {
    self.startTime = CFAbsoluteTimeGetCurrent();
    self.buffer = [NSMutableData data];
    NSMutableURLRequest *req = [self.request mutableCopy];
    self.originalURL = req.URL.absoluteString;
    self.method = req.HTTPMethod ?: @"GET";

    NovaLog(@"REQ", @"%@ %@", self.method, self.originalURL);

    [req.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        NovaLog(@"HDR", @"%@: %@", k, v);
    }];

    if (req.HTTPBody) {
        NSString *body = [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding];
        if (body) NovaLog(@"BODY", @"%@", body);
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:API_URL];
    components.path = req.URL.path;

    NSURLComponents *orig = [NSURLComponents componentsWithURL:req.URL resolvingAgainstBaseURL:NO];
    if (orig.queryItems.count > 0) {
        NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
        for (NSURLQueryItem *item in orig.queryItems) {
            NSString *val = item.value ? [item.value stringByRemovingPercentEncoding] : nil;
            [items addObject:[NSURLQueryItem queryItemWithName:item.name value:val]];
        }
        components.queryItems = items;
    }

    [req setURL:components.URL];
    [req setValue:@"NovaHook/3.2" forHTTPHeaderField:@"X-Nova-Hook"];
    [req setValue:HOOK_VERSION forHTTPHeaderField:@"X-Nova-Version"];
    [NSURLProtocol setProperty:@YES forKey:@"Handled" inRequest:req];

    NovaLog(@"→", @"%@", components.URL.absoluteString);

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 30;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    self.task = [session dataTaskWithRequest:req];
    [self.task resume];
}

- (void)stopLoading { [self.task cancel]; }

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    double ms = (CFAbsoluteTimeGetCurrent() - self.startTime) * 1000;
    NovaLog(@"RES", @"%ld %@ (%.0fms)", (long)http.statusCode, dataTask.currentRequest.URL.path, ms);
    addToHistory(self.method, self.originalURL, http.statusCode, ms);
    [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [self.buffer appendData:data];
    [[self client] URLProtocol:self didLoadData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    double ms = (CFAbsoluteTimeGetCurrent() - self.startTime) * 1000;
    if (error) {
        NovaLog(@"ERR", @"%@ (%.0fms)", error.localizedDescription, ms);
        addToHistory(self.method, self.originalURL, 0, ms);
        [[self client] URLProtocol:self didFailWithError:error];
    } else {
        NSString *resp = [[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding];
        if (resp.length > 0 && resp.length < 500) NovaLog(@"DATA", @"%@", resp);
        [[self client] URLProtocolDidFinishLoading:self];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
completionHandler:(void (^)(NSURLRequest *))completionHandler {
    NovaLog(@"REDIRECT", @"→ %@", request.URL.absoluteString);
    completionHandler(request);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    completionHandler(NSURLSessionAuthChallengeUseCredential,
                      [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
}

@end

// ─────────────────────────────────────────
// MARK: - NSUserDefaults Swizzle
// ─────────────────────────────────────────

@interface NSUserDefaults (NovaSwizzle)
@end
@implementation NSUserDefaults (NovaSwizzle)
+ (void)load {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method orig = class_getInstanceMethod([self class], @selector(stringForKey:));
        Method swiz = class_getInstanceMethod([self class], @selector(nova_stringForKey:));
        method_exchangeImplementations(orig, swiz);
    });
}
- (NSString *)nova_stringForKey:(NSString *)key {
    if ([key isEqualToString:@"AppleLanguages"]) return @"en";
    if ([key isEqualToString:@"AppleLocale"]) return @"en_US";
    return [self nova_stringForKey:key];
}
@end

// ─────────────────────────────────────────
// MARK: - Entry point
// ─────────────────────────────────────────

static NovaFloatingButton *floatingButton;

__attribute__((constructor)) void entry() {
    NovaLog(@"INIT", @"Hook v%@ chargé → %@", HOOK_VERSION, API_URL);
    [NSURLProtocol registerClass:[CustomURLProtocol class]];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            UIWindowScene *scene = nil;
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]] &&
                    s.activationState == UISceneActivationStateForegroundActive) {
                    scene = (UIWindowScene *)s;
                    break;
                }
            }
            if (scene) {
                floatingButton = [[NovaFloatingButton alloc] initWithWindowScene:scene];
                NovaLog(@"INIT", @"Mod Menu chargé ✓");
            } else {
                NovaLog(@"WARN", @"Aucune scène active, menu non chargé");
            }
        } @catch (NSException *e) {
            NovaLog(@"ERR", @"Crash menu: %@", e.reason);
        }
    });
}
