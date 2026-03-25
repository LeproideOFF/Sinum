// Copyright (c) 2025 Project Nova LLC
// Hook Fortnite 9.41 - Version complète

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

#define API_URL @"http://127.0.0.1:3551"
#define EPIC_GAMES_URL @"ol.epicgames.com"
#define LOG_SERVER @"http://127.0.0.1:3551/nova/log"
#define HOOK_VERSION @"2.0.0"

// ─────────────────────────────────────────
// MARK: - Logger centralisé
// ─────────────────────────────────────────

void NovaLog(NSString *level, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[NOVA][%@] %@", level, msg);

    // Envoie aussi le log au serveur Node.js
    NSString *encoded = [msg stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *urlStr = [NSString stringWithFormat:@"%@?level=%@&msg=%@", LOG_SERVER, level, encoded];
    NSURLSession *s = [NSURLSession sharedSession];
    [[s dataTaskWithURL:[NSURL URLWithString:urlStr]] resume];
}

// ─────────────────────────────────────────
// MARK: - CustomURLProtocol
// ─────────────────────────────────────────

@interface CustomURLProtocol : NSURLProtocol <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, assign) CFAbsoluteTime startTime;
@end

@implementation CustomURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    NSString *url = request.URL.absoluteString;
    if ([url containsString:EPIC_GAMES_URL] && ![url containsString:@"/CloudDir/"]) {
        if ([NSURLProtocol propertyForKey:@"Handled" inRequest:request]) return NO;
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (void)startLoading
{
    self.startTime = CFAbsoluteTimeGetCurrent();
    self.buffer = [NSMutableData data];

    NSMutableURLRequest *req = [self.request mutableCopy];
    NSString *originalURL = req.URL.absoluteString;
    NSString *method = req.HTTPMethod ?: @"GET";

    NovaLog(@"REQ", @"%@ %@", method, originalURL);

    // Log headers
    [req.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        NovaLog(@"HDR", @"%@: %@", k, v);
    }];

    // Log body
    if (req.HTTPBody) {
        NSString *body = [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding];
        if (body) NovaLog(@"BODY", @"%@", body);
    }

    // Construire URL locale
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

    NSURL *localURL = components.URL;
    NovaLog(@"→", @"%@", localURL.absoluteString);

    [req setURL:localURL];
    [NSURLProtocol setProperty:@YES forKey:@"Handled" inRequest:req];

    // Ajouter header custom pour identifier les requêtes redirigées
    [req setValue:@"NovaHook/2.0" forHTTPHeaderField:@"X-Nova-Hook"];
    [req setValue:HOOK_VERSION forHTTPHeaderField:@"X-Nova-Version"];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 30;
    config.timeoutIntervalForResource = 60;

    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    self.task = [session dataTaskWithRequest:req];
    [self.task resume];
}

- (void)stopLoading
{
    [self.task cancel];
    NovaLog(@"STOP", @"Requête annulée");
}

// Réponse HTTP reçue
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    NovaLog(@"RES", @"%ld %@", (long)http.statusCode, dataTask.currentRequest.URL.path);

    // Log response headers
    [http.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        NovaLog(@"RHDR", @"%@: %@", k, v);
    }];

    [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    completionHandler(NSURLSessionResponseAllow);
}

// Data reçue — bufferiser
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    [self.buffer appendData:data];
    [[self client] URLProtocol:self didLoadData:data];
}

// Fin de requête
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    CFAbsoluteTime elapsed = (CFAbsoluteTimeGetCurrent() - self.startTime) * 1000;

    if (error) {
        NovaLog(@"ERR", @"%@ (%.0fms)", error.localizedDescription, elapsed);
        [[self client] URLProtocol:self didFailWithError:error];
    } else {
        NSString *responseStr = [[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding];
        if (responseStr) NovaLog(@"DATA", @"%.0fms → %@", elapsed, responseStr);
        [[self client] URLProtocolDidFinishLoading:self];
    }
}

// Redirect handling
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler
{
    NovaLog(@"REDIRECT", @"→ %@", request.URL.absoluteString);
    completionHandler(request);
}

// Auth challenge (ignore SSL si besoin)
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler
{
    NovaLog(@"AUTH", @"Challenge: %@", challenge.protectionSpace.authenticationMethod);
    completionHandler(NSURLSessionAuthChallengeUseCredential,
                      [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
}

@end

// ─────────────────────────────────────────
// MARK: - Swizzle NSUserDefaults (région, langue)
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
    // Force la langue en anglais pour éviter les crashs de localisation
    if ([key isEqualToString:@"AppleLanguages"]) return @"en";
    if ([key isEqualToString:@"AppleLocale"]) return @"en_US";
    return [self nova_stringForKey:key];
}

@end

// ─────────────────────────────────────────
// MARK: - Entry point
// ─────────────────────────────────────────

__attribute__((constructor)) void entry()
{
    NovaLog(@"INIT", @"Hook v%@ chargé", HOOK_VERSION);
    NovaLog(@"INIT", @"Redirection → %@", API_URL);
    NovaLog(@"INIT", @"Logs → %@", LOG_SERVER);

    [NSURLProtocol registerClass:[CustomURLProtocol class]];

    NovaLog(@"INIT", @"NSURLProtocol enregistré ✓");
}
