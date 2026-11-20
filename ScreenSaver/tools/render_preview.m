// 离线渲染屏保画面，用于验证与出效果图。
// 用法: render_preview <saver路径> <输出png> [mode 0/1] [宽] [高] [等待秒]
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <ScreenSaver/ScreenSaver.h>
#import <ImageIO/ImageIO.h>


// 离线渲染不会播放 CALayer 动画，这里把 presentationLayer 的当前值同步回模型，
// 这样出图才能反映动画进行到哪一步。
static void ASSyncAnimations(CALayer *l) {
    if (!l) return;
    CALayer *pres = l.presentationLayer;
    NSArray *keys = [l animationKeys];
    if (pres && [keys count] > 0) {
        l.opacity = pres.opacity;
        l.transform = pres.transform;
    }
    for (CALayer *sub in l.sublayers) ASSyncAnimations(sub);
}



int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

        if (argc < 3) { fprintf(stderr, "usage: render_preview <saver> <out.png> [mode] [w] [h] [wait]\n"); return 1; }
        NSString *bundlePath = [NSString stringWithUTF8String:argv[1]];
        NSString *outPath = [NSString stringWithUTF8String:argv[2]];
        int mode = argc > 3 ? atoi(argv[3]) : 0;
        CGFloat W = argc > 4 ? atof(argv[4]) : 1600;
        CGFloat H = argc > 5 ? atof(argv[5]) : 1000;
        double wait = argc > 6 ? atof(argv[6]) : 1.0;
        int cols = argc > 7 ? atoi(argv[7]) : 0;
        int rows = argc > 8 ? atoi(argv[8]) : 0;

        ScreenSaverDefaults *d = [ScreenSaverDefaults defaultsForModuleWithName:@"com.davidhua.anishelfCovers"];
        [d setInteger:mode forKey:@"mode"];
        [d setInteger:0 forKey:@"scope"];
        [d setBool:YES forKey:@"caption"];
        [d setInteger:cols forKey:@"cols"];
        [d setInteger:rows forKey:@"rows"];
        [d setInteger:(argc > 9 ? atoi(argv[9]) : -1) forKey:@"index"];
        [d synchronize];

        NSError *err = nil;
        NSBundle *b = [NSBundle bundleWithPath:bundlePath];
        if (![b loadAndReturnError:&err]) { fprintf(stderr, "bundle load failed: %s\n", err.localizedDescription.UTF8String); return 2; }
        Class cls = b.principalClass;
        if (!cls) { fprintf(stderr, "no principal class\n"); return 3; }

        NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, W, H)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
        [win setReleasedWhenClosed:NO];
        // AS_START_SMALL=1 模拟屏保启动时窗口先小后大
        BOOL startSmall = getenv("AS_START_SMALL") != NULL;
        CGFloat startW = startSmall ? W * 0.45 : W, startH = startSmall ? H * 0.45 : H;
        ScreenSaverView *v = [[cls alloc] initWithFrame:NSMakeRect(0, 0, startW, startH) isPreview:NO];
        win.contentView = v;
        [v setFrame:NSMakeRect(0, 0, startW, startH)];
        [v startAnimation];
        [v displayIfNeeded];

        // AS_DRIVE_FRAMES=1 时自己驱动逐帧回调，方便截取切换动画的中间状态
        if (getenv("AS_DRIVE_FRAMES")) {
            // 挪到屏幕外并置前，CoreAnimation 才会真正推进时间
            [win setFrameOrigin:NSMakePoint(-W - 400, -400)];
            [win orderFront:nil];
            if (startSmall) {
                [win setContentSize:NSMakeSize(W, H)];
                [v setFrame:NSMakeRect(0, 0, W, H)];
                [v layout];
            }
            CFTimeInterval until = CACurrentMediaTime() + wait;
            int __n = 0;
            const char *rz = getenv("AS_RESIZE_AT");
            double resizeAt = rz ? atof(rz) : -1;
            CFTimeInterval t0 = CACurrentMediaTime();
            while (CACurrentMediaTime() < until) {
                // 模拟屏保启动时窗口尺寸变化（会触发 layout 重建）
                if (resizeAt > 0 && CACurrentMediaTime() - t0 > resizeAt && resizeAt < 1000) {
                    [v setFrame:NSMakeRect(0, 0, W * 1.02, H * 1.02)];
                    [v layout];
                    resizeAt = -2;
                }
                [v animateOneFrame];
                if (++__n % 20 == 0) fprintf(stderr, "[drive] frame %d\n", __n);
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.033]];
            }
        } else {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:wait]];
        }

        CALayer *layer = v.layer;
        if (!layer) { fprintf(stderr, "no layer\n"); return 4; }
        ASSyncAnimations(layer);
        ASSyncAnimations(layer);
        [layer displayIfNeeded];

        __block void (^dump)(CALayer *, int);
        dump = ^(CALayer *l, int depth) {
            NSMutableString *pad = [NSMutableString string];
            for (int i = 0; i < depth; i++) [pad appendString:@"  "];
            NSString *extra = @"";
            if ([l isKindOfClass:[CATextLayer class]]) {
                CATextLayer *t = (CATextLayer *)l;
                extra = [NSString stringWithFormat:@" string=%@ fontSize=%.1f", t.string, t.fontSize];
            }
            fprintf(stderr, "%s%s frame=(%.0f,%.0f,%.0f,%.0f) op=%.2f%s\n",
                    pad.UTF8String, NSStringFromClass([l class]).UTF8String,
                    l.frame.origin.x, l.frame.origin.y, l.frame.size.width, l.frame.size.height,
                    l.opacity, extra.UTF8String);
            for (CALayer *sub in l.sublayers) { if (depth < 3) dump(sub, depth + 1); }
        };
        dump(layer, 0);

        CGFloat scale = 2.0;
        size_t pxW = (size_t)(W * scale), pxH = (size_t)(H * scale);
        CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef ctx = CGBitmapContextCreate(NULL, pxW, pxH, 8, pxW * 4, cs,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(cs);
        if (!ctx) { fprintf(stderr, "no ctx\n"); return 5; }
        CGContextScaleCTM(ctx, scale, scale);
        [layer renderInContext:ctx];

        CGImageRef img = CGBitmapContextCreateImage(ctx);
        CGContextRelease(ctx);
        NSURL *url = [NSURL fileURLWithPath:outPath];
        CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.png"), 1, NULL);
        CGImageDestinationAddImage(dest, img, NULL);
        CGImageDestinationFinalize(dest);
        CFRelease(dest);
        CGImageRelease(img);
        printf("wrote %s (%zux%zu)\n", outPath.UTF8String, pxW, pxH);
    }
    return 0;
}
