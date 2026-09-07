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

    SSLProtocol negotiatedProtocol = kSSLProtocolUnknown;
    OSStatus negotiatedStatus =
        SSLGetNegotiatedProtocolVersion(context, &negotiatedProtocol);

    NSLog(@"[AppStoreFix] SecureTransport min=%d max=%d handshake=%d negotiated=%d read=%d",
          (int)minStatus,
          (int)maxStatus,
          (int)handshakeStatus,
          (int)negotiatedProtocol,
          (int)negotiatedStatus);

    return handshakeStatus;
}

%ctor {
    [ASFXBootstrapBridge install];
    MSHookFunction((void *)SSLHandshake,
                   (void *)ASFXSSLHandshake,
                   (void **)&ASFXOriginalSSLHandshake);
    NSLog(@"[AppStoreFix] Store compatibility loaded");
}

%hook ISURLOperation

- (id)newRequestWithURL:(NSURL *)url {
    NSURL *rewritten = ASFXStoreURLForRequest(url);
    NSMutableURLRequest *request = %orig(rewritten);
    NSString *absolute = [[request URL] absoluteString];
    if ([absolute isEqualToString:@"https://p23-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate"]) {
        request = ASFXPrepareLoginRequest(request);
    }
    return request;
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
    NSLog(@"[AppStoreFix] trust evaluation status=%d result=%d accepted=%d",
          (int)status, (int)result, accepted ? 1 : 0);
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

%hook ISLoadURLBagOperation

- (void)operation:(id)operation finishedWithOutput:(NSDictionary *)outputBag {
    NSDictionary *preparedBag = ASFXPrepareStoreURLBag(outputBag);
    %orig(operation, preparedBag);
}

%end
