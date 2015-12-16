# SyncEngine
The SyncEngine provides iOS platform to sync data from local to online server or vice-versa.

### Installation

1. Download zip file or do `git clone https://github.com/immortalsantee/SyncEngine.git` using terminal.

2. Double click `SyncEngine` folder and select all files. Drag it into your xcode project. Dont forget to check `Copy items if needed` as destination.

3. Select targets you want to use syncEngine.

4. Click Finish.

5. Click `Create Bridging Header`.

6. Now click on `projectName-Bridging-Header.h` file and paste following header files.

```
#import "SDsyncEngine.h"
#import "SDCoredataController.h"
#import "SDAFParseAPIClient.h"
#import "NSManagedObject+JSON.h"
#import "NSString+URLBYCLASS.h"
#import "AFHTTPRequestOperation.h"
#import "AFHTTPRequestOperationManager.h"
#import "AFHTTPSessionManager.h"
#import "AFNetworking.h"
#import "AFNetworkReachabilityManager.h"
#import "AFSecurityPolicy.h"
#import "AFURLConnectionOperation.h"
#import "AFURLRequestSerialization.h"
#import "AFURLResponseSerialization.h"
#import "AFURLSessionManager.h"
```

Remaining documenation coming soon.
