// Copyright (c) 2025 Project Nova LLC

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define API_URL @"http://127.0.0.1:3551"
#define EPIC_GAMES_URL @"ol.epicgames.com"

@interface CustomURLProtocol : NSURLProtocol
@end

@implementation CustomURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request 
{  
    NSString *absoluteURLString = [[request URL] absoluteString];
    if ([absoluteURLString containsString:EPIC_GAMES_URL] && ![absoluteURLString containsString:@"/CloudDir/"]) {
        if ([NSURLProtocol propertyForKey:@"Handled" inRequest:request]) {
            return NO;
        }
        return YES;
    }
    return NO;
}

+ (NSURLRequest*)canonicalRequestForRequest:(NSURLRequest*)request
{
    return request;
}

- (void)startLoading
{
    NSMutableURLRequest* modifiedRequest = [[self request] mutableCopy];

    NSString* originalURL = [[self request].URL absoluteString];
    NSString* method = [self request].HTTPMethod;
    
    // ✅ Log de la requête originale
    NSLog(@"[NOVA] %@ %@", method, originalURL);
    
    // Log du body si POST
    if ([self request].HTTPBody) {
        NSString* body = [[NSString alloc] initWithData:[self request].HTTPBody encoding:NSUTF8StringEncoding];
        NSLog(@"[NOVA] BODY: %@", body);
    }
    
    // Log des headers
    [[self request].allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSString* value, BOOL* stop) {
        NSLog(@"[NOVA] HEADER: %@: %@", key, value);
    }];

    NSString* originalPath = [modifiedRequest.URL path];
    NSString* newBaseURLString = API_URL;

    NSURLComponents* components = [NSURLComponents componentsWithString:newBaseURLString];
    components.path = originalPath;

    NSURLComponents *originalComponents = [NSURLComponents componentsWithURL:modifiedRequest.URL resolvingAgainstBaseURL:NO];
    if (originalComponents.queryItems.count > 0) {
        NSMutableArray<NSURLQueryItem *> *cleanItems = [NSMutableArray array];
        for (NSURLQueryItem *item in originalComponents.queryItems) {
            NSString *decodedValue = item.value ? [item.value stringByRemovingPercentEncoding] : nil;
            [cleanItems addObject:[NSURLQueryItem queryItemWithName:item.name value:decodedValue]];
        }
        components.queryItems = cleanItems;
    }

    [modifiedRequest setURL:components.URL];
    
    // ✅ Log de la requête redirigée
    NSLog(@"[NOVA] → Redirigé vers: %@", components.URL.absoluteString);
    
    [NSURLProtocol setProperty:@YES forKey:@"Handled" inRequest:modifiedRequest];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    [[self client] URLProtocol:self
        wasRedirectedToRequest:modifiedRequest
              redirectResponse:nil];
#pragma clang diagnostic pop
}

- (void)stopLoading
{
}
@end

__attribute__((constructor)) void entry()
{
    NSLog(@"[NOVA] Hook chargé - Redirection vers %@", API_URL);
    [NSURLProtocol registerClass:[CustomURLProtocol class]];
}
