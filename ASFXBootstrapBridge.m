#import "ASFXBootstrapBridge.h"


static NSString * const ASFXRelayMarker = @"com.victorlobe.appstorefix.storefront-relay";
static const double ASFXCoreFoundationVersionIOS7 = 847.20;

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

// iOS 7+
static BOOL ASFXUsesLegacyBuyButton(void) {
    return kCFCoreFoundationVersionNumber < ASFXCoreFoundationVersionIOS7;
}

static NSRange ASFXBuyButtonClassRange(NSData *script) {
    NSData *start = [@"iTSBuyButton=function(e,t,n){" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *end = [@",DV6CanvasUtil=function(){}" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange startRange = [script rangeOfData:start options:0 range:NSMakeRange(0, [script length])];
    if (startRange.location == NSNotFound)
        return startRange;

    NSRange tail = NSMakeRange(startRange.location, [script length] - startRange.location);
    NSRange endRange = [script rangeOfData:end options:0 range:tail];
    if (endRange.location == NSNotFound)
        return endRange;

    return NSMakeRange(startRange.location, endRange.location - startRange.location);
}


static NSData *ASFXScriptWithLegacyBuyButton(NSData *script, NSData *legacyScript) {
    NSRange classRange = ASFXBuyButtonClassRange(script);
    NSRange legacyClassRange = ASFXBuyButtonClassRange(legacyScript);
    if (classRange.location == NSNotFound || legacyClassRange.location == NSNotFound)
        return nil;

    NSData *prefix = [@",function(_asfxModernBuyButton){"
                       "typeof inner==\"undefined\"&&(window.inner=null);"
        dataUsingEncoding:NSUTF8StringEncoding];
    NSData *suffix = [@";for(var _asfxKey in _asfxModernBuyButton)"
                       "_asfxKey in iTSBuyButton||(iTSBuyButton[_asfxKey]=_asfxModernBuyButton[_asfxKey])"
                       "}(iTSBuyButton)"
        dataUsingEncoding:NSUTF8StringEncoding];

    NSUInteger insertion = NSMaxRange(classRange);
    NSMutableData *merged = [NSMutableData dataWithCapacity:
        [script length] + [prefix length] + legacyClassRange.length + [suffix length]];
    [merged appendData:[script subdataWithRange:NSMakeRange(0, insertion)]];
    [merged appendData:prefix];
    [merged appendData:[legacyScript subdataWithRange:legacyClassRange]];
    [merged appendData:suffix];
    [merged appendData:[script subdataWithRange:NSMakeRange(insertion, [script length] - insertion)]];
    return merged;
}

static NSURLResponse *ASFXResponseWithBodyLength(NSURLResponse *response, NSUInteger length) {
    if (![response isKindOfClass:[NSHTTPURLResponse class]])
        return response;

    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    [[http allHeaderFields] enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        NSString *name = [key lowercaseString];
        if (![name isEqualToString:@"content-length"] && ![name isEqualToString:@"content-encoding"])
            [headers setObject:value forKey:key];
    }];
    [headers setObject:[NSString stringWithFormat:@"%lu", (unsigned long)length]
                forKey:@"Content-Length"];

    return [[NSHTTPURLResponse alloc] initWithURL:[http URL]
                                       statusCode:[http statusCode]
                                      HTTPVersion:@"HTTP/1.1"
                                     headerFields:headers];
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
@property(nonatomic, retain) NSURLConnection *legacyConnection;
@property(nonatomic, retain) NSURLResponse *response;
@property(nonatomic, retain) NSMutableData *script;
@property(nonatomic, retain) NSMutableData *legacyScript;
@property(nonatomic, assign) BOOL scriptFinished;
@property(nonatomic, assign) BOOL legacyScriptFinished;

- (id)initWithOwner:(ASFXBootstrapBridge *)owner originalURL:(NSURL *)url patchScript:(BOOL)patchScript;
- (void)loadLegacyBuyButtonWithRequest:(NSURLRequest *)request;
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

- (void)loadLegacyBuyButtonWithRequest:(NSURLRequest *)request {
    self.script = [NSMutableData data];
    self.legacyScript = [NSMutableData data];
    self.legacyConnection = [[NSURLConnection alloc] initWithRequest:request
                                                             delegate:self
                                                     startImmediately:NO];
    [self.legacyConnection start];
}

- (void)cancel {
    [self.connection cancel];
    self.connection = nil;
    [self.legacyConnection cancel];
    self.legacyConnection = nil;
}

- (void)legacyScriptDidFail {
    [self.legacyConnection cancel];
    self.legacyConnection = nil;
    self.legacyScript = nil;
    self.legacyScriptFinished = YES;
    [self deliverScriptIfComplete];
}

- (void)deliverScriptIfComplete {
    if (!self.scriptFinished || !self.legacyScriptFinished)
        return;

    NSData *body = self.script;
    NSData *merged = self.legacyScript ? ASFXScriptWithLegacyBuyButton(self.script, self.legacyScript) : nil;
    if (merged) {
        body = merged;
        NSLog(@"[AppStoreFix] iOS 6 buy button restored for %@", self.originalURL);
    } else {
        NSLog(@"[AppStoreFix] iOS 6 buy button unavailable for %@", self.originalURL);
    }

    id<NSURLProtocolClient> client = [self.owner client];
    [client URLProtocol:self.owner
     didReceiveResponse:ASFXResponseWithBodyLength(self.response, [body length])
     cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [client URLProtocol:self.owner didLoadData:body];
    [client URLProtocolDidFinishLoading:self.owner];

    self.response = nil;
    self.script = nil;
    self.legacyScript = nil;
}

- (NSURLRequest *)connection:(NSURLConnection *)connection
          willSendRequest:(NSURLRequest *)request
         redirectResponse:(NSURLResponse *)redirectResponse {
    NSURL *alternate = connection == self.legacyConnection ? nil : ASFXStorefrontURL(request.URL);
    NSMutableURLRequest *forwarded = [request mutableCopy];
    if (alternate)
        forwarded.URL = alternate;
    [NSURLProtocol setProperty:@YES forKey:ASFXRelayMarker inRequest:forwarded];
    return forwarded;
}

- (void)connection:(NSURLConnection *)connection
 didReceiveResponse:(NSURLResponse *)response {
    if (connection == self.legacyConnection) {
        if ([response isKindOfClass:[NSHTTPURLResponse class]] &&
            [(NSHTTPURLResponse *)response statusCode] != 200) {
            [self legacyScriptDidFail];
        }
        return;
    }

    NSURLResponse *visibleResponse = response;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        visibleResponse = [[NSHTTPURLResponse alloc]
            initWithURL:self.originalURL
            statusCode:[http statusCode]
            HTTPVersion:@"HTTP/1.1"
            headerFields:[http allHeaderFields]];
    }

    if (self.script) {
        [self.script setLength:0];
        self.response = visibleResponse;
        return;
    }

    [[self.owner client] URLProtocol:self.owner
                  didReceiveResponse:visibleResponse
                  cacheStoragePolicy:NSURLCacheStorageNotAllowed];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    if (connection == self.legacyConnection) {
        [self.legacyScript appendData:data];
        return;
    }

    if (self.patchScript) {
        data = ASFXPatchStorefrontScript(data);
    }
    if (self.script) {
        [self.script appendData:data];
        return;
    }
    [[self.owner client] URLProtocol:self.owner didLoadData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if (connection == self.legacyConnection) {
        self.legacyConnection = nil;
        self.legacyScriptFinished = YES;
        [self deliverScriptIfComplete];
        return;
    }

    if (self.script) {
        self.connection = nil;
        self.scriptFinished = YES;
        [self deliverScriptIfComplete];
        return;
    }

    [[self.owner client] URLProtocolDidFinishLoading:self.owner];
    self.connection = nil;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    if (connection == self.legacyConnection) {
        NSLog(@"[AppStoreFix] iOS 6 storefront script failed: %@", error);
        [self legacyScriptDidFail];
        return;
    }

    [self.legacyConnection cancel];
    self.legacyConnection = nil;
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
    if (alternateURL && ASFXUsesLegacyBuyButton()) {
        NSMutableURLRequest *legacy = [self.request mutableCopy];
        [NSURLProtocol setProperty:@YES forKey:ASFXRelayMarker inRequest:legacy];
        [relay loadLegacyBuyButtonWithRequest:legacy];
    }
    relay.connection = [[NSURLConnection alloc] initWithRequest:forwarded
                                                        delegate:relay
                                                startImmediately:YES];
}

- (void)stopLoading {
    [self.relay cancel];
    self.relay = nil;
}

@end
