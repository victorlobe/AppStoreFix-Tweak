#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSURL *ASFXStoreURLForRequest(NSURL *url);
FOUNDATION_EXPORT id ASFXPrepareStoreURLBagValue(NSString *key, id value);
FOUNDATION_EXPORT NSString *ASFXRepairStoreFront(NSString *storeFront);
FOUNDATION_EXPORT NSMutableURLRequest *ASFXPrepareStoreRequest(NSMutableURLRequest *request);
FOUNDATION_EXPORT NSDictionary *ASFXPrepareStoreSectionsDictionary(NSDictionary *dictionary);
FOUNDATION_EXPORT BOOL ASFXLooksLikeStoreURLBagData(id data);
