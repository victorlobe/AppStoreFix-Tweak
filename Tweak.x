#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <Security/SecureTransport.h>
#import <substrate.h>
#import "ASFXBootstrapBridge.h"
#import "ASFXStoreCompatibility.h"


static OSStatus (*ASFXOriginalSSLHandshake)(SSLContextRef context);

static OSStatus ASFXSSLHandshake(SSLContextRef context) {
    OSStatus minStatus = SSLSetProtocolVersionMin(context, kTLSProtocol1);
    OSStatus maxStatus = SSLSetProtocolVersionMax(context, kTLSProtocol12);
    OSStatus handshakeStatus = ASFXOriginalSSLHandshake(context);
	
	
    if (handshakeStatus == noErr ||
        handshakeStatus == errSSLWouldBlock ||
        handshakeStatus == errSSLServerAuthCompleted) {
        return handshakeStatus;
    }

    SSLProtocol negotiatedProtocol = kSSLProtocolUnknown;
    OSStatus negotiatedStatus =
        SSLGetNegotiatedProtocolVersion(context, &negotiatedProtocol);

    char peer[256] = {0};
    size_t peerLength = sizeof(peer) - 1;
    if (SSLGetPeerDomainName(context, peer, &peerLength) != noErr) {
        peerLength = 0;
    }
    peer[peerLength] = '\0';

    NSLog(@"[AppStoreFix] SecureTransport failed host=%s min=%d max=%d handshake=%d negotiated=%d read=%d",
          peer,
          (int)minStatus,
          (int)maxStatus,
          (int)handshakeStatus,
          (int)negotiatedProtocol,
          (int)negotiatedStatus);

    return handshakeStatus;
}

static NSURLRequest *ASFXFinalRewrite(NSURLRequest *request) {
    NSString *absolute = [[request URL] absoluteString];
    if ([absolute hasPrefix:@"https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/freeProductCodeWizard"]) {
        NSMutableURLRequest *newReq = [request mutableCopy];
        [newReq setValue:@"iTunes/12.6.2 (Macintosh; OS X 10.9.5) AppleWebKit/625.2.8.11.9.1" forHTTPHeaderField:@"User-Agent"];
        NSLog(@"[AppStoreFix] User-Agent set for freeProductCodeWizard");
        return newReq;
    }
    if ([[[request URL] path] rangeOfString:@"/WebObjects/MZFinance.woa/wa/authenticate"].location == NSNotFound) return request;
    return ASFXRewriteAuthenticateRequest([request mutableCopy]);
}

%ctor {
    [ASFXBootstrapBridge install];
    MSHookFunction((void *)SSLHandshake,
                   (void *)ASFXSSLHandshake,
                   (void **)&ASFXOriginalSSLHandshake);
    NSLog(@"[AppStoreFix] Store compatibility loaded");
}

// Bag patch for the login URL taken from Pod's NewerStoreLoginFix. Thank you Pod
// https://github.com/Epixx512/NewerStoreLoginFix
%hook ISURLBag

- (id)valueForKey:(NSString *)key {
	id value = %orig;
	if (ASFXDefaultStoreFront() == nil) {
		ASFXRememberBagStoreFront([key isEqualToString:@"storeFrontId"] ? value : %orig(@"storeFrontId"));
	}
	if ([key isEqualToString:@"authenticateAccount"] && [value isKindOfClass:[NSString class]] && ![value hasSuffix:@"/"]) {
		return [value stringByAppendingString:@"/"];
	}
	return value;
}

- (NSURL *)urlForKey:(NSString *)key {
	if ([key isEqualToString:@"authenticateAccount"]) {
		id value = [(id)self valueForKey:key];
		return [value isKindOfClass:[NSString class]] ? [NSURL URLWithString:value] : nil;
	}
	return %orig;
}

%end

%hook ISURLOperation

- (id)newRequestWithURL:(NSURL *)url {
    NSURL *rewritten = ASFXStoreURLForRequest(url);
    return %orig(rewritten);
}

- (BOOL)_runRequestWithURL:(NSURL *)url {
    NSURL *rewritten = ASFXStoreURLForRequest(url);
    return %orig(rewritten);
}

- (BOOL)_isTrustExtendedValidation:(SecTrustRef)trust {
    if (!trust) {
        return NO;
    }

    SecTrustResultType result = kSecTrustResultInvalid;
    OSStatus status = SecTrustEvaluate(trust, &result);
    BOOL accepted = NO;
    if (status == errSecSuccess) {
        accepted = result == kSecTrustResultProceed || result == kSecTrustResultUnspecified;
    }
    if (!accepted) {
        NSLog(@"[AppStoreFix] trust evaluation rejected status=%d result=%d", (int)status, (int)result);
    }
    return accepted;
}

%end

%hook ISStoreURLOperation

- (id)newRequestWithURL:(NSURL *)url {
    return ASFXPrepareStoreRequest(%orig(url));
}

%end

%hook ISCertificate

- (BOOL)checkData:(id)data againstSignature:(id)signature {
    if (ASFXLooksLikeStoreURLBagData(data)) {
        NSLog(@"[AppStoreFix] accepted Store URL bag signature");
        return YES;
    }

    return %orig;
}

%end

%hook SUSectionsResponse

- (id)_newSectionsFromDictionary:(NSDictionary *)dictionary {
    return %orig(ASFXPrepareStoreSectionsDictionary(dictionary));
}

%end

%hook SSAccount

- (NSString *)storeFrontIdentifier {
    NSString *storeFront = %orig;
    return ASFXRepairStoreFront(storeFront);
}

- (void)setStoreFrontIdentifier:(NSString *)storeFront {
    %orig(ASFXRepairStoreFront(storeFront));
}

%end

%hook SSDevice

- (NSString *)storeFrontIdentifier {
    NSString *storeFront = %orig;
    if (storeFront == nil) {
        storeFront = ASFXDefaultStoreFront();
    }
    return ASFXRepairStoreFront(storeFront);
}

%end

%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if ([field caseInsensitiveCompare:@"X-Apple-Store-Front"] == NSOrderedSame) {
        value = ASFXRepairStoreFront(value);
    }
    %orig(value, field);
}

- (void)addValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if ([field caseInsensitiveCompare:@"X-Apple-Store-Front"] == NSOrderedSame) {
        value = ASFXRepairStoreFront(value);
    }
    %orig(value, field);
}

%end

%hook NSURLConnection

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate startImmediately:(BOOL)start {
    return %orig(ASFXFinalRewrite(request), delegate, start);
}

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    return %orig(ASFXFinalRewrite(request), delegate);
}

%end
