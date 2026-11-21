// 把 TMDb 的 SVG 标志转成 PNG，供屏保直接使用
// 用法: svg2png <in.svg> <out.png> [maxWidth]
#import <Cocoa/Cocoa.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: svg2png <in.svg> <out.png> [maxWidth]\n");
            return 1;
        }
        NSString *inPath = [NSString stringWithUTF8String:argv[1]];
        NSString *outPath = [NSString stringWithUTF8String:argv[2]];
        CGFloat maxW = argc > 3 ? atof(argv[3]) : 1200;

        NSImage *img = [[NSImage alloc] initWithContentsOfFile:inPath];
        if (!img || img.size.width < 1 || img.size.height < 1) {
            fprintf(stderr, "cannot decode %s\n", inPath.UTF8String);
            return 2;
        }

        CGFloat scale = MIN(1.0, maxW / img.size.width);
        NSInteger pw = MAX(1, (NSInteger)lround(img.size.width * scale));
        NSInteger ph = MAX(1, (NSInteger)lround(img.size.height * scale));

        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                        pixelsWide:pw
                                                                        pixelsHigh:ph
                                                                     bitsPerSample:8
                                                                   samplesPerPixel:4
                                                                          hasAlpha:YES
                                                                          isPlanar:NO
                                                                    colorSpaceName:NSCalibratedRGBColorSpace
                                                                       bytesPerRow:0
                                                                      bitsPerPixel:0];
        if (!rep) return 3;

        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
        [img drawInRect:NSMakeRect(0, 0, pw, ph)
               fromRect:NSZeroRect
              operation:NSCompositingOperationSourceOver
               fraction:1.0];
        [NSGraphicsContext restoreGraphicsState];

        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (!png || ![png writeToFile:outPath atomically:YES]) return 4;
        printf("%ldx%ld\n", (long)pw, (long)ph);
    }
    return 0;
}
