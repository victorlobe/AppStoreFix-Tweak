#import "ASFXBootstrapBridge.h"


static NSString * const ASFXRelayMarker = @"com.victorlobe.appstorefix.storefront-relay";
static const double ASFXCoreFoundationVersionIOS7 = 847.20;


static BOOL ASFXIsStorefrontHost(NSString *host) {
    return [host isEqualToString:@"itunes.apple.com"] ||
           [host hasSuffix:@".itunes.apple.com"] ||
           [host isEqualToString:@"apps.apple.com"] ||
           [host hasSuffix:@".apps.apple.com"] ||
           [host isEqualToString:@"music.apple.com"] ||
           [host isEqualToString:@"books.apple.com"] ||
           [host isEqualToString:@"podcasts.apple.com"];
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

        //Fix GET button implementation
    NSData *prefix = [@",function(_asfxModernBuyButton){"
                       "typeof inner==\"undefined\"&&(window.inner=null);"
                       "function _asfxLog(m){try{its.client.log(\"[AppStoreFix] \"+m)}catch(x){}}"
                       "function _asfxColor(c){return String(c&&c.getColor?c.getColor():c)}"
                       "function _asfxLegacyPalette(p){"
                         "if(!p||p.buttonGradientStart)return p;"
                         "if(!p.buttonBg)return null;"
                         "var t=_asfxColor(p.buttonBgTrack||p.buttonBg),"
                           "c=_asfxColor(p.buttonBgTrackTransparent||p.buttonBgTransparent||t),"
                           "l={buttonGradientStart:t,buttonGradientEnd:c,buttonStroke:_asfxColor(p.buttonBg),"
                             "buttonShadow:t,buttonText:_asfxColor(p.buttonText),"
                             "buttonTextDisabled:_asfxColor(p.buttonTextDisabled||p.buttonText),"
                             "buttonDisabledBg:_asfxColor(p.buttonBgTransparent||c)},k;"
                         "for(k in l)if(/undefined|null|object/.test(l[k]))return null;"
                         "return l"
                       "}"
        dataUsingEncoding:NSUTF8StringEncoding];


    NSData *suffix = [@";(function(_asfxLegacy){"
                         "var p=_asfxLegacy.prototype,k,s;"
                         "for(k in p)p.hasOwnProperty(k)&&typeof p[k]==\"function\"&&(p[k]=function(k,f){return function(){"
                           "if(this._asfxFailed)return;"
                           "try{return f.apply(this,arguments)}catch(x){"
                             "if(this._asfxBuilding)throw x;"
                             "_asfxLog(\"legacy buy button \"+k+\" failed: \"+x)"
                           "}"
                         "}}(k,p[k]));"
                         "iTSBuyButton=function(e,t,n){"
                           "this._asfxBuilding=!0;"
                           "try{_asfxLegacy.call(this,e,t,n),this._asfxBuilding=!1}catch(x){"
                             "this._asfxBuilding=!1,this._asfxFailed=!0;"
                             "_asfxLog(\"legacy buy button failed, using the modern one: \"+x);"
                             "this.canvas&&this.canvas.parentNode&&this.canvas.parentNode.removeChild(this.canvas);"
                             "return new _asfxModernBuyButton(e,t,n)"
                           "}"
                         "};"
                         "iTSBuyButton.prototype=p;"
                         "for(s in _asfxLegacy)_asfxLegacy.hasOwnProperty(s)&&(iTSBuyButton[s]=_asfxLegacy[s])"
                       "})(iTSBuyButton);"
                       "for(var _asfxKey in _asfxModernBuyButton)"
                       "_asfxKey in iTSBuyButton||(iTSBuyButton[_asfxKey]=_asfxModernBuyButton[_asfxKey])"
                       "}(iTSBuyButton)"
        dataUsingEncoding:NSUTF8StringEncoding];

    NSData *legacyClass = [legacyScript subdataWithRange:legacyClassRange];
    NSString *legacyClassSource = [[NSString alloc] initWithData:legacyClass encoding:NSUTF8StringEncoding];
    NSString *paletteAssignment = @"this.buttonPalette=this.componentContext.buyButtonUberPalette";
    if ([legacyClassSource rangeOfString:paletteAssignment].location != NSNotFound) {
        legacyClassSource = [legacyClassSource stringByReplacingOccurrencesOfString:paletteAssignment
            withString:@"this.buttonPalette=_asfxLegacyPalette(this.componentContext.buyButtonUberPalette)"];
        legacyClass = [legacyClassSource dataUsingEncoding:NSUTF8StringEncoding] ?: legacyClass;
    }
    

    NSUInteger insertion = NSMaxRange(classRange);
    NSMutableData *merged = [NSMutableData dataWithCapacity:
        [script length] + [prefix length] + [legacyClass length] + [suffix length]];
    [merged appendData:[script subdataWithRange:NSMakeRange(0, insertion)]];
    [merged appendData:prefix];
    [merged appendData:legacyClass];
    [merged appendData:suffix];
    [merged appendData:[script subdataWithRange:NSMakeRange(insertion, [script length] - insertion)]];
    return merged;
}



//Info string for dead pages
static NSData *ASFXScriptWithEmptyPageNotice(NSData *script) {
    NSData *notice = [@";(function(){"
                       "var d=window.its&&its.serverData&&its.serverData.pageData;"
                       "if(!d)return;"
                       "var g=d.groupingData,c=d.chartData;"
                       "if(!(d.pageComponent==\"grouping_page\"&&g&&g.stack&&!g.stack.length||"
                         "d.pageComponent==\"charts_page\"&&c&&c.charts&&!c.charts.length))return;"
                       "function s(){"
                         "if(!document.body||document.getElementById(\"asfx-empty-page\"))return;"
                         "var e=document.createElement(\"div\");"
                         "e.id=\"asfx-empty-page\";"
                         "e.style.cssText=\"padding:140px 30px 0;text-align:center;"
                           "font:bold 17px Helvetica,sans-serif;color:#7f7f7f;text-shadow:0 1px 0 #fff\";"
                         "e.appendChild(document.createTextNode("
                           "\"Apple no longer provides this content for older iOS versions.\"));"
                         "document.body.appendChild(e)"
                       "}"
                       "document.addEventListener(\"DOMContentLoaded\",s,!1);"
                       "window.addEventListener(\"load\",s,!1);"
                       "setTimeout(s,1500);setTimeout(s,4000)"
                       "})();"
        dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableData *result = [NSMutableData dataWithData:script];
    [result appendData:notice];
    return result;
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
    body = ASFXScriptWithEmptyPageNotice(body);

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
