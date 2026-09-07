#import "ASFXBootstrapBridge.h"


static NSString * const ASFXRelayMarker = @"com.victorlobe.appstorefix.storefront-relay";

static BOOL ASFXIsStorefrontHost(NSString *host) {
    return [host isEqualToString:@"itunes.apple.com"] ||
           [host hasSuffix:@".itunes.apple.com"] ||
           [host isEqualToString:@"apps.apple.com"] ||
           [host hasSuffix:@".apps.apple.com"];
}

static BOOL ASFXNeedsStorefrontScriptPatch(NSURL *url) {
    NSString *leaf = [[url path] lastPathComponent];
    return [leaf isEqualToString:@"p2-storefront-base.js"] ||
           [leaf isEqualToString:@"k2-storefront-base.js"];
}

static NSData *ASFXPatchStorefrontScript(NSData *data) {
    NSString *script = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (script == nil)
        return data;

    NSString *patched = [script stringByReplacingOccurrencesOfString:
        @"if(t)if(typeof t==\"string\")if(r)e.innerHTML=t;"
        withString:@"if(t)if(typeof t==\"string\")if(true)e.innerHTML=t;"];
    NSData *result = [patched dataUsingEncoding:NSUTF8StringEncoding];
    return result ?: data;
}


static NSString *ASFXStorefrontLeafReplacement(NSURL *url) {
    NSString *host = [[url host] lowercaseString];
    BOOL isStoreHost = ASFXIsStorefrontHost(host);
    if (!isStoreHost || [host isEqualToString:@"search.itunes.apple.com"])
        return nil;

    NSString *leaf = [[url path] lastPathComponent];
    if ([leaf isEqualToString:@"dv6-storefront-p6bootstrap.js"]) {
        return @"dv7-storefront-p7bootstrap.js";
    }
    if ([leaf isEqualToString:@"dv6-storefront-k6bootstrap.js"]) {
        return @"dv7-storefront-k7bootstrap.js";
    }

    return nil; 
}

static NSURL *ASFXStorefrontURL(NSURL *url) {
    NSString *replacement = ASFXStorefrontLeafReplacement(url);
    if (!replacement)
        return nil;

    NSString *absolute = [url absoluteString];
    NSString *leaf = [[url path] lastPathComponent];
    NSRange range = [absolute rangeOfString:leaf options:NSBackwardsSearch];
    if (range.location == NSNotFound)
        return nil;

    NSString *rewritten = [absolute stringByReplacingCharactersInRange:range
                                                               withString:replacement];
    return [NSURL URLWithString:rewritten];
}

@class ASFXStorefrontRelay;

@interface ASFXBootstrapBridge ()

@property(nonatomic, strong) ASFXStorefrontRelay *relay;

@end

@interface ASFXStorefrontRelay : NSObject <NSURLConnectionDataDelegate>

@property(nonatomic, weak) ASFXBootstrapBridge *owner;
@property(nonatomic, retain) NSURL *originalURL;
@property(nonatomic, retain) NSURLConnection *connection;
@property(nonatomic, assign) BOOL patchScript;

- (id)initWithOwner:(ASFXBootstrapBridge *)owner originalURL:(NSURL *)url patchScript:(BOOL)patchScript;
- (void)cancel;
 
@end

@implementation ASFXStorefrontRelay

- (id)initWithOwner:(ASFXBootstrapBridge *)owner originalURL:(NSURL *)url patchScript:(BOOL)patchScript {
    self = [super init];
    if (self) {
        _owner = owner;
        _originalURL = url;
        _patchScript = patchScript;
    }
    return self;
}

- (void)cancel {
    [self.connection cancel];
    self.connection = nil;
}

- (NSURLRequest *)connection:(NSURLConnection *)connection
          willSendRequest:(NSURLRequest *)request
         redirectResponse:(NSURLResponse *)redirectResponse {
    NSURL *alternate = ASFXStorefrontURL(request.URL);
    NSMutableURLRequest *forwarded = [request mutableCopy];
    if (alternate)
        forwarded.URL = alternate;
    [NSURLProtocol setProperty:@YES forKey:ASFXRelayMarker inRequest:forwarded];
    return forwarded;
}

- (void)connection:(NSURLConnection *)connection
 didReceiveResponse:(NSURLResponse *)response {
    NSURLResponse *visibleResponse = response;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        visibleResponse = [[NSHTTPURLResponse alloc]
            initWithURL:self.originalURL
            statusCode:[http statusCode]
            HTTPVersion:@"HTTP/1.1"
            headerFields:[http allHeaderFields]];
    }

    [[self.owner client] URLProtocol:self.owner
                  didReceiveResponse:visibleResponse
                  cacheStoragePolicy:NSURLCacheStorageNotAllowed];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    if (self.patchScript) {
        data = ASFXPatchStorefrontScript(data);
    }
    [[self.owner client] URLProtocol:self.owner didLoadData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [[self.owner client] URLProtocolDidFinishLoading:self.owner];
    self.connection = nil;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [[self.owner client] URLProtocol:self.owner didFailWithError:error];
    self.connection = nil;
}

@end

@implementation ASFXBootstrapBridge

+ (void)install {
    static BOOL installed = NO;
    if (installed)
        return;

    installed = YES;
    [NSURLProtocol registerClass:self];
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:ASFXRelayMarker inRequest:request]) {
        return NO;
    }

    return ASFXStorefrontURL(request.URL) != nil || ASFXNeedsStorefrontScriptPatch(request.URL);
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSURL *sourceURL = self.request.URL;
    NSURL *alternateURL = ASFXStorefrontURL(sourceURL);
    BOOL patchScript = ASFXNeedsStorefrontScriptPatch(sourceURL);
    if (!alternateURL && !patchScript) {
        NSError *error = [NSError errorWithDomain:@"AppStoreFix"
                                             code:1001
                                         userInfo:@{
                                             NSLocalizedDescriptionKey:
                                                 @"Could not construct storefront bootstrap URL"
                                         }];
        [[self client] URLProtocol:self didFailWithError:error];
        return;
    }

    NSLog(@"[AppStoreFix] storefront resource relay: %@%@",
          sourceURL, alternateURL ? [NSString stringWithFormat:@" -> %@", alternateURL] : @" (script patch)");

    NSMutableURLRequest *forwarded = [self.request mutableCopy];
    if (alternateURL)
        forwarded.URL = alternateURL;
    [NSURLProtocol setProperty:@YES forKey:ASFXRelayMarker inRequest:forwarded];

    ASFXStorefrontRelay *relay = [[ASFXStorefrontRelay alloc] initWithOwner:self
                                                                 originalURL:sourceURL
                                                                 patchScript:patchScript];
    self.relay = relay;
    relay.connection = [[NSURLConnection alloc] initWithRequest:forwarded
                                                        delegate:relay
                                                startImmediately:YES];
}

- (void)stopLoading {
    [self.relay cancel];
    self.relay = nil;
}

@end
