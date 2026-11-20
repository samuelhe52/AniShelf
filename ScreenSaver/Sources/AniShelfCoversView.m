//
//  AniShelfCoversView.m
//  用 AniShelf 资料库的封面做一块屏保：漂移封面墙 / 堆叠牌堆两种样式。
//  数据来源: ~/Library/Application Support/AniShelfCovers/library.json
//

#import <ScreenSaver/ScreenSaver.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import <CoreText/CoreText.h>
#import <pwd.h>
#import <ImageIO/ImageIO.h>
#import <ImageIO/ImageIO.h>

static NSString *const kModuleID = @"com.davidhua.anishelfCovers";
static NSString *const kPrefMode = @"mode";        // 0 = 墙, 1 = 堆叠
static NSString *const kPrefScope = @"scope";      // 0 = 全部, 1 = 收藏, 2 = 看过
static NSString *const kPrefCaption = @"caption";  // 1 = 显示片名
static NSString *const kPrefCols = @"cols";        // 0 = 自动，否则每屏列数
static NSString *const kPrefBigInterval = @"bigInterval";    // 秒
static NSString *const kPrefBigTransition = @"bigTransition"; // 0 淡入淡出 / 1 平移
static NSString *const kPrefShowWatch = @"showWatch";   // 大剧照显示观看状态
static NSString *const kPrefLang = @"lang";              // 0 跟随应用 / 1 中文 / 2 英文 / 3 日文
static NSString *const kPrefBigAlign = @"bigAlign";        // 0 左对齐 / 1 居中 / 2 随机
static NSString *const kPrefIndex = @"index";      // 仅调试：固定显示第 N 条
static NSString *const kPrefDrift = @"drift";      // 0 横向 / 1 斜向 / 2 呼吸 / 3 静止

static void ASLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    static NSString *logPath;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        logPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"anishelf-saver.log"];
    });
    FILE *fp = fopen(logPath.UTF8String, "a");
    if (fp) {
        fprintf(fp, "%s\n", line.UTF8String);
        fclose(fp);
    }
}

static CGImageRef ASCreateThumbnail(NSURL *url, CGFloat maxPixel) {
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!src) return NULL;
    NSDictionary *opts = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform : @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize : @(maxPixel),
    };
    CGImageRef img = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    CFRelease(src);
    return img;
}

// 沙盒里 NSHomeDirectory() 指向容器目录，用 passwd 拿真实家目录
static NSString *ASRealHome(void) {
    struct passwd *pw = getpwuid(getuid());
    if (pw && pw->pw_dir) {
        NSString *h = [NSString stringWithUTF8String:pw->pw_dir];
        if (h.length) return h;
    }
    return NSHomeDirectory();
}

static NSArray<NSNumber *> *ASColValues(void) {
    return @[@0, @4, @5, @6, @7, @8, @10, @12, @14];
}

static NSArray<NSString *> *ASColTitles(void) {
    return @[ @"自动（推荐）", @"4 列（大卡）", @"5 列", @"6 列", @"7 列", @"8 列", @"10 列", @"12 列", @"14 列（密）" ];
}

static NSInteger ASInt(id v) {
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
}

static NSString *ASStr(id v) {
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

// TMDb 的 logo 三种情况：透明底的彩色字、透明底的暗色字、整块不透明的牌匾。
// 透明且偏暗的统一刷白，其余保留原样，避免把牌匾刷成白方块。
static CGImageRef ASCreateWhiteLogo(CGImageRef src) {
    size_t w = CGImageGetWidth(src), h = CGImageGetHeight(src);
    if (w == 0 || h == 0) return NULL;
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) return NULL;
    CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
    CGContextSetBlendMode(ctx, kCGBlendModeDestinationIn);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), src);
    CGImageRef out = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return out;
}

static CGImageRef ASCreateLogoForDarkBg(CGImageRef src, BOOL *outGlow) {
    if (outGlow) *outGlow = NO;
    if (!src) return NULL;
    const size_t n = 48;
    uint8_t *buf = calloc(n * n * 4, 1);
    if (!buf) return CGImageRetain(src);
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(buf, n, n, 8, n * 4, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) { free(buf); return CGImageRetain(src); }
    CGContextDrawImage(ctx, CGRectMake(0, 0, n, n), src);
    CGContextRelease(ctx);

    size_t transparent = 0, visible = 0, bright = 0;
    double lumSum = 0, satSum = 0;
    for (size_t i = 0; i < n * n; i++) {
        uint8_t a = buf[i * 4 + 3];
        if (a < 40) { transparent++; continue; }
        visible++;
        // 位图是预乘 alpha 的，必须先还原真实颜色再判断
        double af = a / 255.0;
        double r = MIN(1.0, buf[i * 4] / 255.0 / af);
        double g = MIN(1.0, buf[i * 4 + 1] / 255.0 / af);
        double b = MIN(1.0, buf[i * 4 + 2] / 255.0 / af);
        double mx = fmax(r, fmax(g, b)), mn = fmin(r, fmin(g, b));
        satSum += (mx > 0.01) ? (mx - mn) / mx : 0.0;
        double l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        lumSum += l;
        if (l > 0.7) bright++;
    }
    free(buf);

    double transparentRatio = (double)transparent / (double)(n * n);
    double brightRatio = visible ? (double)bright / (double)visible : 0.0;
    double lum = visible ? lumSum / (double)visible : 0.0;
    double sat = visible ? satSum / (double)visible : 0.0;

    // 1) 不透明牌匾：原样
    if (transparentRatio < 0.35) return CGImageRetain(src);
    // 2) 自带亮部（白字、描边）：原样，刷白会把描边一起吃掉
    if (brightRatio > 0.22) return CGImageRetain(src);
    // 3) 有彩色：保留原色（是否加辉光由背景亮度决定）
    if (sat > 0.18) {
        if (outGlow) *outGlow = (lum < 0.55);
        return CGImageRetain(src);
    }
    // 4) 无彩色剪影（纯黑字）：刷白才读得出来
    return ASCreateWhiteLogo(src);
}

static BOOL ASHasKana(NSString *s) {
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= 0x3040 && c <= 0x30FF) return YES;
    }
    return NO;
}

// 中文用宋体、日文用明朝体，都是最接近「题字」的衬线字
static NSString *ASSerifFontName(NSString *text) {
    NSArray *cands = ASHasKana(text) ? @[ @"HiraMinProN-W6", @"HiraMinProN-W3" ]
                                     : @[ @"STSongti-SC-Black", @"STSongti-SC-Bold", @"STSong" ];
    for (NSString *n in cands) {
        if ([NSFont fontWithName:n size:12]) return n;
    }
    return @"PingFangSC-Regular";
}


// CATextLayer 对属性字符串里的字体支持不可靠，这里直接用 CoreText 画成图片，
// 字形、描边、投影都可控。
static CGImageRef ASCreateTaglineImage(NSString *text, CGFloat fontSize, CGFloat maxWidth) {
    if (text.length == 0 || maxWidth < 40) return NULL;

    NSString *fontName = ASSerifFontName(text);
    CTFontRef font = CTFontCreateWithName((__bridge CFStringRef)fontName, fontSize, NULL);
    if (!font) return NULL;

    CTTextAlignment align = kCTTextAlignmentLeft;
    CTParagraphStyleSetting setting = { kCTParagraphStyleSpecifierAlignment, sizeof(align), &align };
    CTParagraphStyleRef para = CTParagraphStyleCreate(&setting, 1);

    NSDictionary *attrs = @{
        (id)kCTFontAttributeName : (__bridge id)font,
        (id)kCTKernAttributeName : @1.2,
        (id)kCTParagraphStyleAttributeName : (__bridge id)para,
    };

    // 超宽逐字截断
    NSString *shown = text;
    CGFloat textW = 0;
    for (NSInteger cut = 0; cut < 40; cut++) {
        NSAttributedString *a = [[NSAttributedString alloc] initWithString:shown attributes:attrs];
        CTLineRef probe = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)a);
        textW = CTLineGetTypographicBounds(probe, NULL, NULL, NULL);
        CFRelease(probe);
        if (textW <= maxWidth || shown.length <= 2) break;
        shown = [[shown substringToIndex:shown.length - 2] stringByAppendingString:@"…"];
    }

    CGFloat pad = fontSize * 0.55;
    CGFloat w = ceil(textW) + pad * 2;
    CGFloat h = ceil(fontSize * 1.55) + pad * 2;

    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)(w * 2), (size_t)(h * 2), 8, 0, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) { CFRelease(para); CFRelease(font); return NULL; }
    CGContextScaleCTM(ctx, 2.0, 2.0);

    // 颜色写进属性里，不依赖上下文状态（否则第二次绘制可能沿用上一次的颜色）
    NSMutableDictionary *attrsBlack = [attrs mutableCopy];
    attrsBlack[(id)kCTForegroundColorAttributeName] = (__bridge id)[NSColor colorWithWhite:0 alpha:0.92].CGColor;
    NSMutableDictionary *attrsWhite = [attrs mutableCopy];
    attrsWhite[(id)kCTForegroundColorAttributeName] = (__bridge id)[NSColor colorWithWhite:1 alpha:1].CGColor;

    NSAttributedString *sBlack = [[NSAttributedString alloc] initWithString:shown attributes:attrsBlack];
    NSAttributedString *sWhite = [[NSAttributedString alloc] initWithString:shown attributes:attrsWhite];
    CTLineRef lineBlack = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)sBlack);
    CTLineRef lineWhite = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)sWhite);

    CGContextTranslateCTM(ctx, pad, pad + fontSize * 0.24);
    CGContextConcatCTM(ctx, CGAffineTransformMake(1, 0, 0.14, 1, 0, 0));

    // 1) 四周描黑，形成一圈实边
    CGFloat rim = MAX(0.9, fontSize * 0.042);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, -1.5), fontSize * 0.18,
                                [NSColor colorWithWhite:0 alpha:0.85].CGColor);
    CGPoint offs[8] = {
        {-rim, 0}, {rim, 0}, {0, -rim}, {0, rim},
        {-rim * 0.7, -rim * 0.7}, {rim * 0.7, -rim * 0.7},
        {-rim * 0.7, rim * 0.7}, {rim * 0.7, rim * 0.7},
    };
    for (int i = 0; i < 8; i++) {
        CGContextSetTextPosition(ctx, offs[i].x, offs[i].y);
        CTLineDraw(lineBlack, ctx);
    }

    // 2) 白色实心字压在上面
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
    CGContextSetTextPosition(ctx, 0, 0);
    CTLineDraw(lineWhite, ctx);

    CFRelease(lineBlack);
    CFRelease(lineWhite);
    CGImageRef out = CGBitmapContextCreateImage(ctx);
    if (getenv("AS_DUMP_TAG")) {
        CGImageDestinationRef dst = CGImageDestinationCreateWithURL(
            (__bridge CFURLRef)[NSURL fileURLWithPath:@"/tmp/tag_dump.png"], CFSTR("public.png"), 1, NULL);
        if (dst) { CGImageDestinationAddImage(dst, out, NULL); CGImageDestinationFinalize(dst); CFRelease(dst); }
    }
    if (getenv("AS_DUMP_TAG")) {
        CGImageDestinationRef dst = CGImageDestinationCreateWithURL(
            (__bridge CFURLRef)[NSURL fileURLWithPath:@"/tmp/tag_dump.png"], CFSTR("public.png"), 1, NULL);
        if (dst) { CGImageDestinationAddImage(dst, out, NULL); CGImageDestinationFinalize(dst); CFRelease(dst); }
    }
    CGContextRelease(ctx);
    CFRelease(para);
    CFRelease(font);
    return out;
}

// 把海报放大铺满、重度模糊，当作整屏背景
static CGImageRef ASBlurredBackgroundWithRadius(CGImageRef src, CGSize size, CIContext *ctx, CGFloat radiusFactor) {
    if (!src || size.width < 20 || !ctx) return NULL;
    CIImage *ci = [CIImage imageWithCGImage:src];
    CGFloat sw = ci.extent.size.width, sh = ci.extent.size.height;
    if (sw < 1 || sh < 1) return NULL;
    CGFloat scale = MAX(size.width / sw, size.height / sh);
    CIImage *scaled = [ci imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    CGRect ext = scaled.extent;
    CGFloat tx = (ext.size.width - size.width) / 2.0 + ext.origin.x;
    CGFloat ty = (ext.size.height - size.height) / 2.0 + ext.origin.y;
    CIImage *centered = [scaled imageByApplyingTransform:CGAffineTransformMakeTranslation(-tx, -ty)];
    CGRect rect = CGRectMake(0, 0, size.width, size.height);
    CIImage *filled = [[centered imageByClampingToExtent] imageByCroppingToRect:rect];

    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:filled forKey:kCIInputImageKey];
    [blur setValue:@(MAX(18.0, size.width * radiusFactor)) forKey:kCIInputRadiusKey];
    CIImage *out = [[blur.outputImage imageByClampingToExtent] imageByCroppingToRect:rect];
    return [ctx createCGImage:out fromRect:rect];
}


// 多行段落用 CoreText 直接排版成图片：CATextLayer 对属性字符串的字号支持不可靠
static CGImageRef ASCreateParagraphImage(NSString *text, NSString *fontName, CGFloat fontSize,
                                         CGFloat maxWidth, NSInteger maxLines) {
    if (text.length == 0 || maxWidth < 40) return NULL;
    NSFont *font = [NSFont fontWithName:fontName size:fontSize] ?: [NSFont systemFontOfSize:fontSize];
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.lineSpacing = fontSize * 0.42;
    ps.paragraphSpacing = 0;
    ps.lineBreakMode = NSLineBreakByWordWrapping;   // 关键：不能用 TruncatingTail，那会把每段压成一行

    NSString *body = [text stringByReplacingOccurrencesOfString:@"\n\n" withString:@"\n"];
    body = [body stringByReplacingOccurrencesOfString:@"\r" withString:@""];

    NSDictionary *richAttrs = @{
        NSFontAttributeName : font,
        NSForegroundColorAttributeName : [NSColor colorWithWhite:1 alpha:0.72],
        NSParagraphStyleAttributeName : ps,
    };
    NSAttributedString *rich = [[NSAttributedString alloc] initWithString:body attributes:richAttrs];

    CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)rich);
    if (!fs) return NULL;
    CGSize fit = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRangeMake(0, 0), NULL,
                                                              CGSizeMake(maxWidth, CGFLOAT_MAX), NULL);
    CTLineRef probe = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)rich);
    CGFloat asc = 0, desc = 0;
    CTLineGetTypographicBounds(probe, &asc, &desc, NULL);
    CFRelease(probe);
    CGFloat lineH = ceil(asc + desc + fontSize * 0.52 + 2);
    CGFloat h = MIN(lineH * maxLines, ceil(fit.height) + 2);
    if (ceil(fit.height) > h + 1) {   // 被截断就补一个省略号，避免半句断掉
        rich = [[NSAttributedString alloc] initWithString:[body stringByAppendingString:@"…"]
                                               attributes:richAttrs];
        CFRelease(fs);
        fs = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)rich);
    }
    CGRect rect = CGRectMake(0, 0, maxWidth, h);
    CGPathRef path = CGPathCreateWithRect(rect, NULL);
    CTFrameRef frame = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, NULL);

    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)(maxWidth * 2), (size_t)(h * 2), 8, 0, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) { CFRelease(frame); CGPathRelease(path); CFRelease(fs); return NULL; }
    CGContextScaleCTM(ctx, 2.0, 2.0);
    CTFrameDraw(frame, ctx);

    CGImageRef out = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    CFRelease(frame);
    CGPathRelease(path);
    CFRelease(fs);
    return out;
}


static CGImageRef ASCreateTextImage(NSString *text, NSString *fontName, CGFloat fontSize,
                                    CGFloat alpha, CGFloat kern) {
    if (text.length == 0) return NULL;
    CTFontRef font = CTFontCreateWithName((__bridge CFStringRef)fontName, fontSize, NULL);
    if (!font) return NULL;
    NSDictionary *attrs = @{
        (id)kCTFontAttributeName : (__bridge id)font,
        (id)kCTForegroundColorAttributeName : (__bridge id)[NSColor colorWithWhite:1 alpha:alpha].CGColor,
        (id)kCTKernAttributeName : @(kern),
    };
    NSAttributedString *rich = [[NSAttributedString alloc] initWithString:text attributes:attrs];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)rich);
    CGFloat w = CTLineGetTypographicBounds(line, NULL, NULL, NULL);

    CGFloat pad = fontSize * 0.3;
    CGFloat cw = ceil(w) + pad * 2, ch = ceil(fontSize * 1.5) + pad * 2;
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)(cw * 2), (size_t)(ch * 2), 8, 0, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) { CFRelease(line); CFRelease(font); return NULL; }
    CGContextScaleCTM(ctx, 2.0, 2.0);
    CGContextSetTextPosition(ctx, pad, pad + fontSize * 0.22);
    CTLineDraw(line, ctx);
    CGImageRef out = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    CFRelease(line);
    CFRelease(font);
    return out;
}


// 元数据语言：0 跟随 AniShelf 导出时的语言，1 中文，2 英文，3 日文
static NSString *ASLangCode(NSDictionary *item, NSInteger pref) {
    if (pref == 1) return @"zh";
    if (pref == 2) return @"en";
    if (pref == 3) return @"ja";
    NSString *app = ASStr(item[@"taglineLang"]);
    return app.length ? app : @"zh";
}

static NSString *ASLocalized(NSDictionary *item, NSString *key, NSInteger pref) {
    id i18n = item[@"i18n"];
    if ([i18n isKindOfClass:[NSDictionary class]]) {
        id bag = i18n[ASLangCode(item, pref)];
        if ([bag isKindOfClass:[NSDictionary class]]) {
            id v = bag[key];
            if ([v isKindOfClass:[NSString class]] && [v length]) return v;
        }
    }
    return ASStr(item[key]);
}

// 标语只有抓取时那一种语言，语言不匹配就不显示
static NSString *ASTagline(NSDictionary *item, NSInteger pref) {
    NSString *fetched = ASStr(item[@"taglineLang"]);
    if (fetched.length && ![fetched isEqualToString:ASLangCode(item, pref)]) return @"";
    return ASStr(item[@"tagline"]);
}



// TMDb 类型 ID → 名称（16 动画已排除，动画库没必要标"动画"）
static NSString *ASGenreName(NSNumber *gid, NSString *lang) {
    static NSDictionary<NSNumber *, NSArray<NSString *> *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @10759 : @[ @"动作冒险", @"Action & Adventure", @"アクション&アドベンチャー" ],
            @35    : @[ @"喜剧", @"Comedy", @"コメディ" ],
            @18    : @[ @"剧情", @"Drama", @"ドラマ" ],
            @10751 : @[ @"家庭", @"Family", @"ファミリー" ],
            @10765 : @[ @"奇幻科幻", @"Sci-Fi & Fantasy", @"SF&ファンタジー" ],
            @9648  : @[ @"悬疑", @"Mystery", @"ミステリー" ],
            @10749 : @[ @"爱情", @"Romance", @"ロマンス" ],
            @14    : @[ @"奇幻", @"Fantasy", @"ファンタジー" ],
            @878   : @[ @"科幻", @"Science Fiction", @"SF" ],
            @28    : @[ @"动作", @"Action", @"アクション" ],
            @12    : @[ @"冒险", @"Adventure", @"アドベンチャー" ],
            @80    : @[ @"犯罪", @"Crime", @"クライム" ],
            @27    : @[ @"恐怖", @"Horror", @"ホラー" ],
            @99    : @[ @"纪录", @"Documentary", @"ドキュメンタリー" ],
            @10762 : @[ @"儿童", @"Kids", @"キッズ" ],
            @10764 : @[ @"真人秀", @"Reality", @"リアリティ" ],
            @36    : @[ @"历史", @"History", @"歴史" ],
            @10752 : @[ @"战争", @"War", @"戦争" ],
            @10768 : @[ @"战争政治", @"War & Politics", @"戦争&政治" ],
            @37    : @[ @"西部", @"Western", @"西部劇" ],
            @10402 : @[ @"音乐", @"Music", @"音楽" ],
            @10770 : @[ @"电视电影", @"TV Movie", @"TVムービー" ],
            @53    : @[ @"惊悚", @"Thriller", @"スリラー" ],
        };
    });
    NSArray<NSString *> *names = table[gid];
    if (!names) return nil;
    if ([lang isEqualToString:@"en"]) return names[1];
    if ([lang isEqualToString:@"ja"]) return names[2];
    return names[0];
}

static NSString *ASAirStatusName(NSString *code, NSString *lang) {
    BOOL en = [lang isEqualToString:@"en"], ja = [lang isEqualToString:@"ja"];
    if ([code isEqualToString:@"returning"]) return en ? @"Airing" : (ja ? @"放送中" : @"连载中");
    if ([code isEqualToString:@"production"]) return en ? @"In production" : (ja ? @"制作中" : @"制作中");
    if ([code isEqualToString:@"ended"]) return en ? @"Completed" : (ja ? @"完結" : @"完结");
    return nil;
}

static NSString *ASWatchName(NSString *code, NSString *lang) {
    BOOL en = [lang isEqualToString:@"en"], ja = [lang isEqualToString:@"ja"];
    if ([code isEqualToString:@"watching"]) return en ? @"Watching" : (ja ? @"視聴中" : @"在看");
    if ([code isEqualToString:@"watched"]) return en ? @"Watched" : (ja ? @"視聴済" : @"看完");
    if ([code isEqualToString:@"planned"]) return en ? @"Planned" : (ja ? @"視聴予定" : @"想看");
    if ([code isEqualToString:@"dropped"]) return en ? @"Dropped" : (ja ? @"中断" : @"搁置");
    return nil;
}


// 把「横向羽化」直接烘进像素：CALayer.mask 在离屏渲染里不可靠，
// 烘进图里既能所见即所得，也不依赖合成器。
static CGImageRef ASFadeHorizontal(CGImageRef src, BOOL onLeft,
                                   const CGFloat *alphas, const CGFloat *locs, int count) {
    if (!src || count < 2) return CGImageRetain(src);
    size_t w = CGImageGetWidth(src), h = CGImageGetHeight(src);
    if (w == 0 || h == 0) return CGImageRetain(src);
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) return CGImageRetain(src);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), src);

    CGFloat comps[4 * 8];
    CGFloat stops[8];
    for (int i = 0; i < count && i < 8; i++) {
        comps[i * 4 + 0] = 1.0;
        comps[i * 4 + 1] = 1.0;
        comps[i * 4 + 2] = 1.0;
        comps[i * 4 + 3] = alphas[i];
        stops[i] = locs[i];
    }
    CGColorSpaceRef rgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGGradientRef g = CGGradientCreateWithColorComponents(rgb, comps, stops, count);
    CGColorSpaceRelease(rgb);

    CGContextSetBlendMode(ctx, kCGBlendModeDestinationIn);
    CGPoint from = CGPointMake(onLeft ? 0 : w, 0);
    CGPoint to = CGPointMake(onLeft ? w : 0, 0);
    CGContextDrawLinearGradient(ctx, g, from, to, 0);
    CGGradientRelease(g);

    CGImageRef out = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return out;
}


static CGImageRef ASBlurredBackground(CGImageRef src, CGSize size, CIContext *ctx) {
    return ASBlurredBackgroundWithRadius(src, size, ctx, 0.05);
}

static double ASLuminanceInRegion(CGImageRef img, CGRect unitRect) {
    if (!img) return 0.0;
    const size_t n = 40;
    uint8_t *buf = calloc(n * n * 4, 1);
    if (!buf) return 0.0;
    CGContextRef ctx = CGBitmapContextCreate(buf, n, n, 8, n * 4,
                                             CGColorSpaceCreateDeviceRGB(), kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (!ctx) { free(buf); return 0.0; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, n, n), img);
    CGContextRelease(ctx);

    size_t x0 = (size_t)(unitRect.origin.x * n), x1 = MIN(n, (size_t)(CGRectGetMaxX(unitRect) * n));
    size_t y0 = (size_t)(unitRect.origin.y * n), y1 = MIN(n, (size_t)(CGRectGetMaxY(unitRect) * n));
    double sum = 0; size_t cnt = 0;
    for (size_t y = y0; y < y1; y++) {
        for (size_t x = x0; x < x1; x++) {
            size_t i = (y * n + x) * 4;
            sum += (0.2126 * buf[i] + 0.7152 * buf[i + 1] + 0.0722 * buf[i + 2]) / 255.0;
            cnt++;
        }
    }
    free(buf);
    return cnt ? sum / (double)cnt : 0.0;
}

static CALayer *ASFindSublayer(CALayer *parent, NSString *name) {
    for (CALayer *l in parent.sublayers) {
        if ([l.name isEqualToString:name]) return l;
    }
    return nil;
}

static CATextLayer *ASMakeLabel(CGFloat size, CGFloat weight, CGColorRef color) {
    CATextLayer *l = [CATextLayer layer];
    l.contentsScale = 2.0;
    l.fontSize = size;
    l.foregroundColor = color;
    l.alignmentMode = kCAAlignmentLeft;
    l.truncationMode = kCATruncationEnd;
    l.wrapped = NO;
    CFStringRef name = weight >= 0.6 ? CFSTR("PingFangSC-Semibold") : CFSTR("PingFangSC-Regular");
    l.font = name;
    return l;
}

@interface AniShelfCoversView : ScreenSaverView
@property (nonatomic, strong) NSArray<NSDictionary *> *library;
@property (nonatomic, copy) NSString *dataDir;
@property (nonatomic, assign) NSInteger mode;
@property (nonatomic, assign) NSInteger scope;
@property (nonatomic, assign) BOOL showsCaption;
@property (nonatomic, assign) NSInteger colsPref;
@property (nonatomic, assign) NSInteger drift;
@property (nonatomic, assign) NSInteger debugIndex;
@property (nonatomic, assign) NSInteger bigInterval;
@property (nonatomic, assign) NSInteger bigTransition;
@property (nonatomic, assign) NSInteger bigAlign;
@property (nonatomic, assign) NSInteger langPref;
@property (nonatomic, assign) BOOL showsWatch;

@property (nonatomic, strong) CALayer *stage;
@property (nonatomic, strong) CALayer *backdrop;
@property (nonatomic, strong) CALayer *vignette;
@property (nonatomic, strong) CATextLayer *captionTitle;
@property (nonatomic, strong) CATextLayer *captionMeta;

@property (nonatomic, strong) NSMutableArray<CALayer *> *wallCards;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *deckItems;
@property (nonatomic, strong) NSMutableArray<CALayer *> *deckLayers;
@property (nonatomic, strong) NSArray<NSDictionary *> *bigItems;
@property (nonatomic, assign) NSInteger bigIndex;
@property (nonatomic, strong) CALayer *bigScene;
@property (nonatomic, assign) CFTimeInterval nextBig;
@property (nonatomic, strong) CALayer *deckContainer;
@property (nonatomic, assign) NSInteger deckHead;
@property (nonatomic, assign) NSInteger slotCount;
@property (nonatomic, assign) CGSize cardSize;

@property (nonatomic, strong) NSWindow *configSheet;
@property (nonatomic, strong) NSPopUpButton *modePopup;
@property (nonatomic, strong) NSPopUpButton *scopePopup;
@property (nonatomic, strong) NSPopUpButton *colsPopup;
@property (nonatomic, strong) NSPopUpButton *driftPopup;
@property (nonatomic, strong) NSPopUpButton *intervalPopup;
@property (nonatomic, strong) NSPopUpButton *transPopup;
@property (nonatomic, strong) NSPopUpButton *alignPopup;
@property (nonatomic, strong) NSPopUpButton *langPopup;
@property (nonatomic, strong) NSTextField *gridLabel;
@property (nonatomic, strong) NSButton *captionCheck;
@property (nonatomic, strong) NSButton *watchCheck;

@property (nonatomic, assign) CFTimeInterval nextCaption;
@property (nonatomic, assign) CFTimeInterval nextDeck;
@property (nonatomic, assign) NSInteger captionIndex;
@property (nonatomic, assign) CGSize layoutSize;
- (void)fillLayer:(CALayer *)img withPath:(NSString *)path maxPixel:(CGFloat)maxPixel;
@end

@implementation AniShelfCoversView {
    CIContext *_ciContext;
    NSMutableArray<NSString *> *_captions;
}

#pragma mark - 生命周期

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        self.wantsLayer = YES;
        self.layer.masksToBounds = YES;
        self.animationTimeInterval = 0.1;
        ASLog(@"[init] preview=%d frame=%.0fx%.0f", isPreview, NSWidth(frame), NSHeight(frame));
        _ciContext = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer : @NO}];
        _captions = [NSMutableArray array];
        [self loadPreferences];
        [self loadLibrary];
    }
    return self;
}

- (BOOL)isOpaque { return YES; }

- (void)loadPreferences {
    ScreenSaverDefaults *d = [ScreenSaverDefaults defaultsForModuleWithName:kModuleID];
    [d registerDefaults:@{kPrefMode : @0, kPrefScope : @0, kPrefCaption : @1,
                          kPrefCols : @0, kPrefDrift : @0, kPrefIndex : @(-1),
                          kPrefBigInterval : @9, kPrefBigTransition : @0, kPrefBigAlign : @0, kPrefLang : @0, kPrefShowWatch : @NO}];
    self.mode = [d integerForKey:kPrefMode];
    self.scope = [d integerForKey:kPrefScope];
    self.showsCaption = [d boolForKey:kPrefCaption];
    self.colsPref = [d integerForKey:kPrefCols];
    self.drift = [d integerForKey:kPrefDrift];
    self.debugIndex = [d integerForKey:kPrefIndex];
    self.bigInterval = MAX(3, [d integerForKey:kPrefBigInterval]);
    self.bigTransition = [d integerForKey:kPrefBigTransition];
    self.bigAlign = [d integerForKey:kPrefBigAlign];
    self.langPref = [d integerForKey:kPrefLang];
    self.showsWatch = [d boolForKey:kPrefShowWatch];
}

- (void)loadLibrary {
    NSString *realHome = ASRealHome();
    NSString *bundleRes = [[NSBundle bundleForClass:[self class]] resourcePath] ?: @"";
    NSArray *candidates = @[
        bundleRes,                                                                   // 包内资源，最稳
        [realHome stringByAppendingPathComponent:@"Library/Application Support/AniShelfCovers"],
        [realHome stringByAppendingPathComponent:@"Pictures/AniShelfCovers"],
        [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"] stringByAppendingPathComponent:@"AniShelfCovers"],
        [realHome stringByAppendingPathComponent:@"Library/Screen Savers/AniShelfCovers.saver/Contents/Resources"],
    ];

    ASLog(@"[AniShelfCovers] NSHomeDirectory=%@ realHome=%@", NSHomeDirectory(), realHome);

    NSString *base = nil;
    NSData *data = nil;
    for (NSString *dir in candidates) {
        if (dir.length == 0) continue;
        NSString *path = [dir stringByAppendingPathComponent:@"library.json"];
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path];
        NSData *d = exists ? [NSData dataWithContentsOfFile:path] : nil;
        ASLog(@"[AniShelfCovers] 尝试 %@ -> exists=%d readable=%d", path, exists, d.length > 0);
        if (d.length > 0 && !data) { base = dir; data = d; }
    }
    if (!data) {
        ASLog(@"[AniShelfCovers] 全部路径均不可读");
        self.library = @[];
        self.dataDir = nil;
        return;
    }

    NSError *err = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *raw in json[@"items"]) {
        NSString *rel = raw[@"cover"];
        if (![rel isKindOfClass:[NSString class]]) continue;
        NSString *path = [base stringByAppendingPathComponent:rel];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;
        NSMutableDictionary *m = [raw mutableCopy];
        m[@"path"] = path;
        NSString *bd = raw[@"backdrop"];
        if ([bd isKindOfClass:[NSString class]]) {
            NSString *p = [base stringByAppendingPathComponent:bd];
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) m[@"backdropPath"] = p;
        }
        NSString *lg = raw[@"logo"];
        if ([lg isKindOfClass:[NSString class]]) {
            NSString *p = [base stringByAppendingPathComponent:lg];
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) m[@"logoPath"] = p;
        }
        [items addObject:m];
    }
    self.library = items;
    self.dataDir = base;
    ASLog(@"[AniShelfCovers] 载入 %lu 条封面 (base=%@)", (unsigned long)items.count, base);
}

- (NSArray<NSDictionary *> *)selectedItems {
    NSInteger scope = self.scope;
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *it in self.library) {
        NSString *status = it[@"status"];
        if (scope == 1 && ![it[@"favorite"] boolValue]) continue;
        if (scope == 2 && ![status isEqualToString:@"watched"]) continue;
        [out addObject:it];
    }
    if (out.count < 6) out = [self.library mutableCopy];
    // 洗牌，保证每次进入屏保的组合不同
    for (NSUInteger i = out.count; i > 1; i--) {
        [out exchangeObjectAtIndex:i - 1 withObjectAtIndex:arc4random_uniform((uint32_t)i)];
    }
    return out;
}

#pragma mark - 场景搭建

- (void)startAnimation {
    [super startAnimation];
    [self buildScene];
}

- (void)stopAnimation {
    [super stopAnimation];
    [self.stage removeFromSuperlayer];
    self.stage = nil;
}

- (void)layout {
    [super layout];
    if (!CGSizeEqualToSize(self.layoutSize, self.bounds.size)) {
        [self buildScene];
    }
}

// 后台解码，主线程贴图：首帧不再被 70 多张封面卡住
- (void)fillLayer:(CALayer *)img withPath:(NSString *)path maxPixel:(CGFloat)maxPixel {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CGImageRef cg = ASCreateThumbnail([NSURL fileURLWithPath:path], maxPixel);
        if (!cg) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (img.superlayer) img.contents = (__bridge id)cg;
            CGImageRelease(cg);
        });
    });
}

- (void)buildScene {
    CFTimeInterval sceneT0 = CACurrentMediaTime();
    self.layoutSize = self.bounds.size;
    [self.stage removeFromSuperlayer];
    self.wallCards = [NSMutableArray array];
    self.deckLayers = [NSMutableArray array];

    CGFloat w = NSWidth(self.bounds), h = NSHeight(self.bounds);
    if (w < 40 || h < 40) return;

    CALayer *stage = [CALayer layer];
    stage.frame = self.bounds;
    stage.backgroundColor = [NSColor colorWithCalibratedRed:0.035 green:0.035 blue:0.045 alpha:1].CGColor;
    [self.layer addSublayer:stage];
    self.stage = stage;

    CALayer *backdrop = [CALayer layer];
    backdrop.frame = self.bounds;
    backdrop.contentsGravity = kCAGravityResizeAspectFill;
    backdrop.opacity = 0.0f;
    [stage addSublayer:backdrop];
    self.backdrop = backdrop;

    NSArray *pool = [self selectedItems];

    // 设置面板里的预览只出一张静态底图：不建几十个图层、不跑动画，避免拖住 Options 面板
    if (self.isPreview) {
        NSDictionary *first = pool.firstObject;
        NSString *path = first[@"backdropPath"] ?: first[@"path"];
        if (path) {
            CALayer *snap = [CALayer layer];
            snap.frame = self.bounds;
            snap.contentsGravity = kCAGravityResizeAspectFill;
            CGImageRef img = ASCreateThumbnail([NSURL fileURLWithPath:path], NSWidth(self.bounds) * 1.2);
            if (img) {
                snap.contents = (__bridge id)img;
                CGImageRelease(img);
            }
            [stage addSublayer:snap];
        }
        return;
    }

    // 设置面板里的预览只出一张静态底图：不建几十个图层、不跑动画，避免拖住 Options 面板
    if (self.isPreview) {
        NSDictionary *first = pool.firstObject;
        NSString *path = first[@"backdropPath"] ?: first[@"path"];
        if (path) {
            CALayer *snap = [CALayer layer];
            snap.frame = self.bounds;
            snap.contentsGravity = kCAGravityResizeAspectFill;
            CGImageRef img = ASCreateThumbnail([NSURL fileURLWithPath:path], NSWidth(self.bounds) * 1.2);
            if (img) {
                snap.contents = (__bridge id)img;
                CGImageRelease(img);
            }
            [stage addSublayer:snap];
        }
        return;
    }
    if (pool.count == 0) {
        CATextLayer *empty = ASMakeLabel(22, 0.4, [NSColor colorWithWhite:1 alpha:0.55].CGColor);
        empty.string = @"未找到 AniShelf 封面缓存\n请先运行 refresh.sh 重新安装";
        empty.frame = CGRectMake(0, h / 2 - 40, w, 80);
        empty.alignmentMode = kCAAlignmentCenter;
        empty.wrapped = YES;
        [stage addSublayer:empty];
        return;
    }

    if (self.mode >= 2) {
        [self buildBigStillWith:pool];
    } else if (self.mode == 1) {
        [self buildDeckWith:pool];
    } else {
        [self buildWallWith:pool];
    }

    // 只有堆叠模式需要压暗底部来衬片名；封面墙保持纯画面
    if (self.mode == 1) {
        CAGradientLayer *scrim = [CAGradientLayer layer];
        scrim.frame = CGRectMake(0, 0, w, h * 0.42);
        scrim.type = kCAGradientLayerAxial;
        scrim.startPoint = CGPointMake(0.5, 0.0);
        scrim.endPoint = CGPointMake(0.5, 1.0);
        scrim.colors = @[
            (id)[NSColor colorWithWhite:0.02 alpha:0.78].CGColor,
            (id)[NSColor colorWithWhite:0.02 alpha:0.34].CGColor,
            (id)[NSColor colorWithWhite:0.02 alpha:0.0].CGColor,
        ];
        scrim.locations = @[@0.0, @0.45, @1.0];
        [stage addSublayer:scrim];
        self.vignette = scrim;

        [self buildCaptionsWith:pool size:CGSizeMake(w, h)];
    }
    ASLog(@"[scene] mode=%ld preview=%d items=%lu in %.0f ms", (long)self.mode, self.isPreview, (unsigned long)pool.count, (CACurrentMediaTime()-sceneT0)*1000);
}

#pragma mark 封面墙

- (void)buildWallWith:(NSArray *)pool {
    CGFloat w = NSWidth(self.bounds), h = NSHeight(self.bounds);
    BOOL wide = w >= h;
    CGFloat gapRatio = 0.085;

    // 列数决定卡片宽度；2:3 竖版卡片下，行数由屏幕高度唯一确定
    NSInteger pc = self.colsPref;
    CGFloat cardW = pc > 0 ? w / (pc + gapRatio * (pc - 1))
                           : (wide ? h / 6.2 : w / 5.0);
    cardW = MAX(48.0, MIN(cardW, MAX(w, h) / 2.2));

    CGFloat cardH = cardW * 1.5;
    CGFloat gap = cardW * gapRatio;
    NSInteger rows = (NSInteger)llround((h + gap) / (cardH + gap));
    rows = MAX(rows, 1);
    cardH = (h - (rows - 1) * gap) / rows;   // 反算高度，屏幕高度正好分完
    cardW = cardH / 1.5;
    gap = cardW * gapRatio;
    CGFloat stepX = cardW + gap, stepY = cardH + gap;

    NSInteger drift = self.drift;
    BOOL diagonal = (drift == 1);
    BOOL kenBurns = (drift == 2);
    BOOL still = (drift == 3);
    NSInteger totalRows = rows + (diagonal ? 2 : 0);
    NSInteger cols = (NSInteger)ceil(w / stepX) + 2;

    CGFloat worldW = cols * stepX;
    CGFloat worldH = totalRows * stepY;
    CALayer *world = [CALayer layer];
    world.bounds = CGRectMake(0, 0, worldW, worldH);
    [self.stage addSublayer:world];

    for (NSInteger i = 0; i < cols * totalRows; i++) {
        NSDictionary *item = pool[i % pool.count];
        NSInteger col = i % cols, row = i / cols;

        CALayer *wrap = [CALayer layer];
        wrap.bounds = CGRectMake(0, 0, cardW, cardH);
        // 严格网格：统一尺寸、统一基线，不做随机位移与旋转
        wrap.position = CGPointMake(col * stepX + cardW / 2,
                                    worldH - (row * stepY + cardH / 2));
        wrap.cornerRadius = cardW * 0.055;
        wrap.shadowColor = [NSColor blackColor].CGColor;
        wrap.shadowOpacity = 0.42;
        wrap.shadowRadius = cardW * 0.07;
        wrap.shadowOffset = CGSizeMake(0, -cardW * 0.025);

        CALayer *img = [CALayer layer];
        img.frame = wrap.bounds;
        img.cornerRadius = wrap.cornerRadius;
        img.masksToBounds = YES;
        img.contentsGravity = kCAGravityResizeAspectFill;
        img.backgroundColor = [NSColor colorWithWhite:0.12 alpha:1].CGColor;
        [wrap addSublayer:img];
        [self fillLayer:img withPath:item[@"path"] maxPixel:cardW * 1.35];

        CALayer *edge = [CALayer layer];
        edge.frame = wrap.bounds;
        edge.cornerRadius = wrap.cornerRadius;
        edge.borderWidth = 0.6;
        edge.borderColor = [NSColor colorWithWhite:1 alpha:0.10].CGColor;
        [wrap addSublayer:edge];

        [world addSublayer:wrap];
        [self.wallCards addObject:wrap];
    }

    if (kenBurns) {
        // 呼吸推拉：整面墙缓慢放大再回落，构图始终不变形
        world.anchorPoint = CGPointMake(0.5, 0.5);
        world.position = CGPointMake(w / 2, h / 2);
        CABasicAnimation *zoom = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        zoom.fromValue = @1.0;
        zoom.toValue = @1.07;
        zoom.duration = 45.0;
        zoom.autoreverses = YES;
        zoom.repeatCount = HUGE_VALF;
        zoom.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [world addAnimation:zoom forKey:@"zoom"];
    } else {
        world.anchorPoint = CGPointMake(0, 0);
        world.position = CGPointMake(0, h - worldH);

        // 按速度算周期，保证「看得见在动」：横向约 9pt/s，斜向约 5pt/s
        CGFloat travelX = worldW - w;
        if (!still && travelX > 1) {
            CFTimeInterval d = MIN(600.0, MAX(35.0, travelX / 12.0));
            [self panWorld:world axis:@"position.x" from:0 to:-travelX duration:d];
        }
        if (!still && diagonal && worldH > h + 1) {
            CGFloat travelY = worldH - h;
            CFTimeInterval d = MIN(600.0, MAX(50.0, travelY / 7.0));
            [self panWorld:world axis:@"position.y" from:(h - worldH) to:0 duration:d];
        }
    }

    self.backdrop.opacity = 0.35f;
    CGImageRef bg = ASCreateThumbnail([NSURL fileURLWithPath:pool.firstObject[@"path"]], 640);
    if (bg) {
        self.backdrop.contents = (__bridge id)bg;
        CGImageRelease(bg);
    }
}

- (void)panWorld:(CALayer *)layer axis:(NSString *)key from:(CGFloat)a to:(CGFloat)b duration:(CFTimeInterval)d {
    CABasicAnimation *a1 = [CABasicAnimation animationWithKeyPath:key];
    a1.fromValue = @(a);
    a1.toValue = @(b);
    a1.duration = d;
    a1.autoreverses = YES;
    a1.repeatCount = HUGE_VALF;
    a1.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [layer addAnimation:a1 forKey:key];
}

#pragma mark 堆叠牌堆

- (void)refreshDeckBackdrop {
    CALayer *img = ASFindSublayer(self.deckLayers.firstObject, @"img");
    CGImageRef src = (__bridge CGImageRef)img.contents;
    if (src) [self setBackdropWithImage:src];
}

- (void)buildDeckWith:(NSArray *)pool {
    CGFloat w = NSWidth(self.bounds), h = NSHeight(self.bounds);
    CGFloat cardW = MIN(w * 0.30, h * 0.58 / 1.5);
    CGFloat cardH = cardW * 1.5;

    CALayer *deck = [CALayer layer];
    deck.frame = self.bounds;
    [self.stage addSublayer:deck];
    self.deckContainer = deck;

    NSInteger slots = MIN((NSInteger)pool.count, 7);
    self.slotCount = slots;
    self.cardSize = CGSizeMake(cardW, cardH);
    self.deckItems = [pool mutableCopy];
    for (NSInteger i = slots - 1; i >= 0; i--) {
        NSDictionary *item = pool[i];
        CALayer *wrap = [CALayer layer];
        wrap.bounds = CGRectMake(0, 0, cardW, cardH);
        wrap.cornerRadius = 14;
        wrap.shadowColor = [NSColor blackColor].CGColor;
        wrap.shadowOpacity = 0.7;
        wrap.shadowRadius = 34;
        wrap.shadowOffset = CGSizeMake(0, -18);

        CALayer *img = [CALayer layer];
        img.name = @"img";
        img.frame = wrap.bounds;
        img.cornerRadius = 14;
        img.masksToBounds = YES;
        img.contentsGravity = kCAGravityResizeAspectFill;
        img.backgroundColor = [NSColor colorWithWhite:0.12 alpha:1].CGColor;
        [wrap addSublayer:img];
        [self fillLayer:img withPath:item[@"path"] maxPixel:cardW * 1.35];

        // 细描边
        CALayer *edge = [CALayer layer];
        edge.frame = wrap.bounds;
        edge.cornerRadius = 14;
        edge.borderWidth = 1.0;
        edge.borderColor = [NSColor colorWithWhite:1 alpha:0.14].CGColor;
        [wrap addSublayer:edge];

        [deck addSublayer:wrap];
        [self.deckLayers addObject:wrap];
        [self.deckItems addObject:item];
    }

    // 统一成 slot 0 = 最前面的顺序
    self.deckLayers = [[[self.deckLayers reverseObjectEnumerator] allObjects] mutableCopy];
    self.deckHead = 0;
    for (NSInteger i = 0; i < (NSInteger)self.deckLayers.count; i++) {
        [self applySlot:i toLayer:self.deckLayers[i] size:CGSizeMake(cardW, cardH) animated:NO];
    }
    CGImageRef first = ASCreateThumbnail([NSURL fileURLWithPath:pool.firstObject[@"path"]], cardW * 1.35);
    if (first) {
        [self setBackdropWithImage:first];
        CGImageRelease(first);
    }
    self.nextDeck = CACurrentMediaTime() + 5.0;
}

- (void)applySlot:(NSInteger)slot toLayer:(CALayer *)layer size:(CGSize)size animated:(BOOL)animated {
    CGFloat w = NSWidth(self.bounds), h = NSHeight(self.bounds);
    NSInteger count = MAX((NSInteger)1, self.slotCount);

    if (slot >= count) {  // 藏在堆底
        slot = count - 1;
    }

    CGFloat mid = (count - 1) / 2.0;
    CGFloat step = size.height * 0.048;
    CGFloat scale = 1.0 - slot * 0.028;
    CGFloat dx = (slot - mid) * size.width * 0.026;
    CGFloat dy = (slot - mid) * step;
    CGFloat rot = (slot - mid) * 0.75 * M_PI / 180.0;
    CGFloat alpha = MAX(0.8, 1.0 - slot * 0.018);

    void (^changes)(void) = ^{
        layer.position = CGPointMake(w / 2 + dx, h / 2 + dy);
        layer.transform = CATransform3DMakeRotation(rot, 0, 0, 1);
        layer.transform = CATransform3DScale(layer.transform, scale, scale, 1);
        layer.opacity = alpha;
        layer.zPosition = -slot * 1.0;
        layer.shadowOpacity = slot == 0 ? 0.75 : 0.25;
    };

    if (animated) {
        [CATransaction begin];
        [CATransaction setAnimationDuration:1.15];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
        changes();
        [CATransaction commit];
    } else {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        changes();
        [CATransaction commit];
    }
}

- (void)advanceDeck {
    if (self.deckLayers.count < 3) return;
    CALayer *top = self.deckLayers[0];

    // 顶牌飞出
    CABasicAnimation *fly = [CABasicAnimation animationWithKeyPath:@"transform"];
    CATransform3D startT = top.transform;
    CATransform3D endT = CATransform3DScale(CATransform3DMakeRotation(-0.16, 0, 0, 1), 1.18, 1.18, 1);
    endT = CATransform3DTranslate(endT, -NSWidth(self.bounds) * 0.22, NSHeight(self.bounds) * 0.18, 0);
    fly.fromValue = [NSValue valueWithCATransform3D:startT];
    fly.toValue = [NSValue valueWithCATransform3D:endT];
    fly.duration = 0.9;
    fly.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    [top addAnimation:fly forKey:@"fly"];

    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @1.0;
    fade.toValue = @0.0;
    fade.duration = 0.85;
    [top addAnimation:fade forKey:@"flyfade"];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    top.opacity = 0;
    [CATransaction commit];

    // 其余向前递补
    [self.deckLayers removeObjectAtIndex:0];
    for (NSInteger i = 0; i < (NSInteger)self.deckLayers.count; i++) {
        [self applySlot:i toLayer:self.deckLayers[i] size:self.cardSize animated:YES];
    }

    // 空出来的牌补到堆底，换一张新封面
    CGSize size = self.cardSize;
    self.deckHead = (self.deckHead + 1) % MAX((NSInteger)1, (NSInteger)self.deckItems.count);
    NSDictionary *next = self.deckItems[self.deckHead % self.deckItems.count];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.95 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        top.opacity = 0;
        [CATransaction commit];
        // 放回子层最底部，保证任何渲染路径下都在最下层
        [top removeFromSuperlayer];
        [self.deckContainer insertSublayer:top atIndex:0];
        [self applySlot:self.slotCount - 1 toLayer:top size:size animated:NO];
        CALayer *img = ASFindSublayer(top, @"img");
        [self fillLayer:img withPath:next[@"path"] maxPixel:size.width * 1.35];
        [self.deckLayers addObject:top];
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.5];
        top.opacity = MAX(0.8, 1.0 - (self.slotCount - 1) * 0.018);
        [CATransaction commit];
    });

    [self refreshDeckBackdrop];

    if (self.showsCaption) {
        [self setCaptionForItem:self.deckItems[self.deckHead % self.deckItems.count]];
    }
}

- (void)setBackdropWithImage:(CGImageRef)src {
    if (!src) return;
    CIImage *ci = [CIImage imageWithCGImage:src];
    CGAffineTransform t = CGAffineTransformMakeScale(3.0, 3.0);
    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:[ci imageByApplyingTransform:t] forKey:kCIInputImageKey];
    [blur setValue:@80 forKey:kCIInputRadiusKey];
    CIImage *out = blur.outputImage;
    CGImageRef blurred = [_ciContext createCGImage:out fromRect:[ci imageByApplyingTransform:t].extent];
    if (blurred) {
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.9];
        self.backdrop.contents = (__bridge id)blurred;
        self.backdrop.opacity = 0.62;
        self.backdrop.contentsGravity = kCAGravityResizeAspectFill;
        [CATransaction commit];
        CGImageRelease(blurred);
    }
}

#pragma mark 大剧照

- (void)buildBigStillWith:(NSArray *)pool {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *it in pool) {
        if (self.mode >= 3 || it[@"backdropPath"]) [items addObject:it];
    }
    if (items.count == 0) {
        CATextLayer *empty = ASMakeLabel(20, 0.4, [NSColor colorWithWhite:1 alpha:0.5].CGColor);
        empty.string = @"没有可用的剧照，请先运行 refresh.sh";
        empty.frame = CGRectMake(0, NSHeight(self.bounds) / 2, NSWidth(self.bounds), 40);
        empty.alignmentMode = kCAAlignmentCenter;
        [self.stage addSublayer:empty];
        return;
    }
    if (self.debugIndex >= 0 && self.debugIndex < (NSInteger)self.library.count) {
        NSDictionary *pick = self.library[self.debugIndex];
        NSUInteger at = [items indexOfObjectIdenticalTo:pick];
        if (at != NSNotFound) {
            [items removeObjectAtIndex:at];
            [items insertObject:pick atIndex:0];
        }
    }
    self.bigItems = items;
    self.bigIndex = 0;
    CALayer *scene = [self bigSceneForItem:items[0] size:self.bounds.size];
    [self.stage addSublayer:scene];
    self.bigScene = scene;
    self.nextBig = CACurrentMediaTime() + self.bigInterval;
}

- (void)advanceBigStill {
    if (self.bigItems.count < 2) return;
    NSInteger next = (self.bigIndex + 1) % self.bigItems.count;
    CALayer *scene = [self bigSceneForItem:self.bigItems[next] size:self.bounds.size];
    CALayer *old = self.bigScene;
    CGFloat w = NSWidth(self.bounds), h = NSHeight(self.bounds);
    BOOL slide = (self.bigTransition == 1);
    CFTimeInterval dur = slide ? 0.85 : 1.05;

    if (slide) {
        scene.position = CGPointMake(w * 1.5, h / 2);   // 从右侧进画
        [self.stage addSublayer:scene];
        [CATransaction begin];
        [CATransaction setAnimationDuration:dur];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
        scene.position = CGPointMake(w / 2, h / 2);
        old.position = CGPointMake(-w / 2, h / 2);
        [CATransaction commit];
    } else {
        scene.opacity = 0.0;
        [self.stage addSublayer:scene];
        [CATransaction begin];
        [CATransaction setAnimationDuration:dur];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
        scene.opacity = 1.0;
        old.opacity = 0.0;
        [CATransaction commit];
    }

    self.bigScene = scene;
    self.bigIndex = next;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((dur + 0.2) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [old removeFromSuperlayer];
    });
}

- (CALayer *)bigSceneForItem:(NSDictionary *)item size:(CGSize)size {
    if (self.mode == 4) return [self fusionSceneForItem:item size:size];
    if (self.mode == 4) return [self fusionSceneForItem:item size:size];
    if (self.mode == 3) return [self leanSceneForItem:item size:size];
    CGFloat w = size.width, h = size.height;
    NSColor *bg = [NSColor colorWithCalibratedRed:0.031 green:0.031 blue:0.037 alpha:1];

    CALayer *scene = [CALayer layer];
    scene.frame = CGRectMake(0, 0, w, h);
    scene.backgroundColor = bg.CGColor;

    // 全屏剧照
    CALayer *photo = [CALayer layer];
    photo.frame = CGRectMake(0, 0, w, h);
    photo.contentsGravity = kCAGravityResizeAspectFill;
    photo.masksToBounds = YES;
    photo.backgroundColor = [NSColor colorWithWhite:0.08 alpha:1].CGColor;
    CGImageRef img = ASCreateThumbnail([NSURL fileURLWithPath:item[@"backdropPath"]], w * 1.25);
    double bottomLum = ASLuminanceInRegion(img, CGRectMake(0, 0, 0.46, 0.42));
    if (img) {
        photo.contents = (__bridge id)img;
        CGImageRelease(img);
    }
    // 画面越亮，底部阴影越重，保证文字与标志始终有对比
    CGFloat a0 = bottomLum > 0.58 ? 0.90 : (bottomLum > 0.34 ? 0.80 : 0.68);
    BOOL brightBg = (bottomLum > 0.55);
    CABasicAnimation *zoom = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    zoom.fromValue = @1.0;
    zoom.toValue = @1.045;
    zoom.duration = 16.0;
    zoom.autoreverses = YES;
    zoom.repeatCount = HUGE_VALF;
    zoom.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [photo addAnimation:zoom forKey:@"zoom"];
    [scene addSublayer:photo];

    // 底部一层阴影，只为托住文字，不抢画面
    CAGradientLayer *fade = [CAGradientLayer layer];
    fade.frame = CGRectMake(0, 0, w, h * 0.48);
    fade.type = kCAGradientLayerAxial;
    fade.startPoint = CGPointMake(0.5, 0.0);
    fade.endPoint = CGPointMake(0.5, 1.0);
    fade.colors = @[
        (id)[NSColor colorWithWhite:0 alpha:a0].CGColor,
        (id)[NSColor colorWithWhite:0 alpha:a0 * 0.52].CGColor,
        (id)[NSColor colorWithWhite:0 alpha:a0 * 0.18].CGColor,
        (id)[NSColor colorWithWhite:0 alpha:0.0].CGColor,
    ];
    fade.locations = @[@0.0, @0.34, @0.66, @1.0];
    [scene addSublayer:fade];

    // 左下角信息块
    CGFloat marginX = w * 0.070;
    CGFloat maxW = w - marginX * 2;
    CGFloat metaSize = MAX(15.0, h * 0.0205);

    // 0 左对齐 / 1 居中 / 2 随机（每次换片重新掷）
    BOOL centered = (self.bigAlign == 1) || (self.bigAlign == 2 && arc4random_uniform(2) == 0);

    // 标语：默认左上；居中模式放到正上方中间
    NSString *tagline = ASTagline(item, self.langPref);
    if (tagline.length) {
        // 顶部一层淡阴影，给字压出一个安静的底
        CAGradientLayer *top = [CAGradientLayer layer];
        top.frame = CGRectMake(0, h * 0.74, w, h * 0.26);
        top.type = kCAGradientLayerAxial;
        top.startPoint = CGPointMake(0.5, 0.0);
        top.endPoint = CGPointMake(0.5, 1.0);
        top.colors = @[
            (id)[NSColor colorWithWhite:0 alpha:0.0].CGColor,
            (id)[NSColor colorWithWhite:0 alpha:a0 * 0.42].CGColor,
            (id)[NSColor colorWithWhite:0 alpha:a0 * 0.62].CGColor,
        ];
        top.locations = @[@0.0, @0.62, @1.0];
        [scene addSublayer:top];

        CGFloat tagSize = MAX(24.0, h * 0.042);
        CGImageRef tagImg = ASCreateTaglineImage(tagline, tagSize, maxW * 0.86);
        if (tagImg) {
            CGFloat iw = CGImageGetWidth(tagImg) / 2.0, ih = CGImageGetHeight(tagImg) / 2.0;
            CALayer *tag = [CALayer layer];
            tag.contents = (__bridge id)tagImg;
            tag.contentsGravity = kCAGravityResize;
            tag.frame = CGRectMake(centered ? (w - iw) / 2.0 : marginX - tagSize * 0.45,
                                   h - h * 0.135 - ih, iw, ih);
            [scene addSublayer:tag];
            CGImageRelease(tagImg);
        }
    }

    CGFloat metaY = h * 0.106;
    CGFloat genreY = h * 0.062;
    CGFloat logoH = h * 0.125;
    CGFloat logoBottom = metaY + metaSize * 2.2;

    CALayer *mark = nil;
    if (item[@"logoPath"]) {
        CGImageRef raw = ASCreateThumbnail([NSURL fileURLWithPath:item[@"logoPath"]], logoH * 3);
        BOOL needsGlow = NO;
        CGImageRef lg = ASCreateLogoForDarkBg(raw, &needsGlow);
        (void)needsGlow;
        if (raw) CGImageRelease(raw);
        if (lg) {
            CGFloat ar = (CGFloat)CGImageGetWidth(lg) / MAX(1.0, (CGFloat)CGImageGetHeight(lg));
            CGFloat lw = MIN(logoH * ar, maxW * 0.82);
            CALayer *l = [CALayer layer];
            l.contentsGravity = kCAGravityResizeAspect;
            l.contents = (__bridge id)lg;
            if (brightBg) {
                l.shadowColor = [NSColor blackColor].CGColor;
                l.shadowOpacity = 0.62;
                l.shadowRadius = 18;
                l.shadowOffset = CGSizeMake(0, -2);
            } else {
                l.shadowColor = [NSColor whiteColor].CGColor;
                l.shadowOpacity = 0.38;
                l.shadowRadius = 16;
                l.shadowOffset = CGSizeZero;
            }
            if (brightBg) {
                l.shadowColor = [NSColor blackColor].CGColor;
                l.shadowOpacity = 0.62;
                l.shadowRadius = 18;
                l.shadowOffset = CGSizeMake(0, -2);
            } else {
                l.shadowColor = [NSColor whiteColor].CGColor;
                l.shadowOpacity = 0.38;
                l.shadowRadius = 16;
                l.shadowOffset = CGSizeZero;
            }
            l.frame = CGRectMake(centered ? (w - lw) / 2.0 : marginX, logoBottom, lw, logoH);
            CGImageRelease(lg);
            mark = l;
        }
    }
    if (!mark) {
        CATextLayer *t = ASMakeLabel(MAX(30.0, h * 0.050), 0.7, [NSColor colorWithWhite:1 alpha:0.95].CGColor);
        t.string = ASLocalized(item, @"title", self.langPref);
        t.frame = CGRectMake(marginX, logoBottom + logoH * 0.18, maxW, logoH);
        t.alignmentMode = centered ? kCAAlignmentCenter : kCAAlignmentLeft;
        t.alignmentMode = centered ? kCAAlignmentCenter : kCAAlignmentLeft;
        t.shadowColor = (brightBg ? [NSColor blackColor] : [NSColor whiteColor]).CGColor;
        t.shadowOpacity = brightBg ? 0.7 : 0.45;
        t.shadowRadius = 14;
        t.shadowOffset = CGSizeMake(0, -2);
        mark = t;
    }
    [scene addSublayer:mark];

    // 国家 · 年份 · 评分
    NSMutableArray *parts = [NSMutableArray array];
    NSString *country = ASLocalized(item, @"country", self.langPref);
    if (country.length) [parts addObject:country];
    NSInteger year = ASInt(item[@"year"]);
    if (year > 0) [parts addObject:[NSString stringWithFormat:@"%ld", (long)year]];

    // 类型单独成行；连载状态 → 观看状态 留在主行
    NSString *langCode = ASLangCode(item, self.langPref);
    id genreList = item[@"genres"];
    NSMutableArray *genreNames = [NSMutableArray array];
    if ([genreList isKindOfClass:[NSArray class]]) {
        for (id g in (NSArray *)genreList) {
            if (genreNames.count >= 3) break;
            NSString *n = ASGenreName(@([g integerValue]), langCode);
            if (n.length) [genreNames addObject:n];
        }
    }
    NSString *air = ASAirStatusName(ASStr(item[@"airStatus"]), langCode);
    if (air.length) [parts addObject:air];
    if (self.showsWatch) {
        NSString *watch = ASWatchName(ASStr(item[@"watch"]), langCode);
        if (watch.length) [parts addObject:watch];
    }

    NSString *head = [parts componentsJoinedByString:@"  ·  "];
    double vote = [item[@"vote"] doubleValue];

    NSString *scoreText = nil;
    if (vote > 0) {
        scoreText = [NSString stringWithFormat:@"TMDB %.1f", vote];
    } else if (ASInt(item[@"score"]) > 0) {
        scoreText = [NSString stringWithFormat:@"我的评分 %ld/5", (long)ASInt(item[@"score"])];
    }
    NSString *metaText = head;
    if (scoreText.length) {
        metaText = head.length ? [NSString stringWithFormat:@"%@  ·  %@", head, scoreText] : scoreText;
    }

    CGImageRef metaImg = ASCreateTextImage(metaText, @"PingFangSC-Regular", metaSize, 0.74, 1.0);
    if (metaImg) {
        CGFloat mw = CGImageGetWidth(metaImg) / 2.0, mh = CGImageGetHeight(metaImg) / 2.0;
        CGFloat fit = MIN(1.0, maxW / MAX(1.0, mw));   // 太长就整体缩一点，别被屏幕裁掉
        mw *= fit;
        mh *= fit;
        CALayer *meta = [CALayer layer];
        meta.contents = (__bridge id)metaImg;
        meta.contentsGravity = kCAGravityResize;
        meta.frame = CGRectMake(centered ? (w - mw) / 2.0 : marginX - metaSize * 0.3,
                                metaY - mh * 0.12, mw, mh);
        [scene addSublayer:meta];
        CGImageRelease(metaImg);
    }

    // 类型另起一行
    if (genreNames.count) {
        CGFloat genreSize = MAX(13.0, h * 0.0178);
        NSString *genreText = [genreNames componentsJoinedByString:@"  /  "];
        CGImageRef gImg = ASCreateTextImage(genreText, @"PingFangSC-Regular", genreSize, 0.64, 0.8);
        if (gImg) {
            CGFloat gw = CGImageGetWidth(gImg) / 2.0, gh = CGImageGetHeight(gImg) / 2.0;
            CGFloat fit = MIN(1.0, maxW / MAX(1.0, gw));
            gw *= fit;
            gh *= fit;
            CALayer *gl = [CALayer layer];
            gl.contents = (__bridge id)gImg;
            gl.contentsGravity = kCAGravityResize;
            gl.frame = CGRectMake(centered ? (w - gw) / 2.0 : marginX - genreSize * 0.3,
                                  genreY - gh * 0.12, gw, gh);
            [scene addSublayer:gl];
            CGImageRelease(gImg);
        }
    }

    return scene;
}

#pragma mark 海报聚焦

- (CALayer *)leanSceneForItem:(NSDictionary *)item size:(CGSize)size {
    CGFloat w = size.width, h = size.height;
    NSColor *bg = [NSColor colorWithCalibratedRed:0.014 green:0.014 blue:0.018 alpha:1];

    CALayer *scene = [CALayer layer];
    scene.frame = CGRectMake(0, 0, w, h);
    scene.backgroundColor = bg.CGColor;

    CGImageRef poster = ASCreateThumbnail([NSURL fileURLWithPath:item[@"path"]], w * 0.9);
    if (!poster) return scene;

    // 背景：同一张海报放大铺满 + 重度模糊
    CGImageRef bgImg = ASBlurredBackground(poster, CGSizeMake(w * 0.5, h * 0.5), _ciContext);
    CALayer *blur = [CALayer layer];
    blur.frame = CGRectMake(0, 0, w, h);
    blur.contentsGravity = kCAGravityResizeAspectFill;
    if (bgImg) {
        blur.contents = (__bridge id)bgImg;
        CGImageRelease(bgImg);
    }
    [scene addSublayer:blur];

    // 横向渐变：左边留一点海报的色，右边压暗托住文字
    CAGradientLayer *shade = [CAGradientLayer layer];
    shade.frame = CGRectMake(0, 0, w, h);
    shade.type = kCAGradientLayerAxial;
    shade.startPoint = CGPointMake(0.0, 0.5);
    shade.endPoint = CGPointMake(1.0, 0.5);
    shade.colors = @[
        (id)[NSColor colorWithWhite:0 alpha:0.14].CGColor,
        (id)[NSColor colorWithWhite:0 alpha:0.40].CGColor,
        (id)[NSColor colorWithWhite:0 alpha:0.74].CGColor,
    ];
    shade.locations = @[@0.0, @0.5, @1.0];
    [scene addSublayer:shade];

    // 左侧海报卡片
    CGFloat cardH = h * 0.62;
    CGFloat cardW = cardH * 2.0 / 3.0;
    CGFloat marginX = w * 0.055;
    CALayer *card = [CALayer layer];
    card.frame = CGRectMake(marginX, (h - cardH) / 2.0, cardW, cardH);
    card.cornerRadius = h * 0.010;
    card.shadowColor = [NSColor blackColor].CGColor;
    card.shadowOpacity = 0.65;
    card.shadowRadius = h * 0.055;
    card.shadowOffset = CGSizeMake(0, -h * 0.018);

    CALayer *art = [CALayer layer];
    art.frame = card.bounds;
    art.cornerRadius = card.cornerRadius;
    art.masksToBounds = YES;
    art.contentsGravity = kCAGravityResizeAspectFill;
    art.contents = (__bridge id)poster;
    [card addSublayer:art];
    [scene addSublayer:card];
    CGImageRelease(poster);

    // 右侧文字列：先算总高度再整体居中
    CGFloat textX = marginX + cardW + w * 0.045;
    CGFloat textW = w - textX - w * 0.050;
    CGFloat titleSize = h * 0.046;
    CGFloat tagSize = MAX(16.0, h * 0.022);
    CGFloat metaSize = MAX(14.0, h * 0.0185);
    CGFloat ovSize = MAX(16.0, h * 0.0245);
    CGFloat ovLine = ovSize * 1.80;
    CGFloat ovH = ovLine * 6;

    NSString *tagline = ASTagline(item, self.langPref);
    NSString *overview = ASLocalized(item, @"overview", self.langPref);
    CGFloat tagH = tagline.length ? (tagSize * 1.55 + tagSize * 0.9) : 0;
    CGFloat gap1 = h * 0.020, gap2 = h * 0.010, gap3 = h * 0.020;
    CGFloat total = titleSize * 1.35 + gap1 + tagH + gap2 + metaSize * 1.6
                  + (overview.length ? gap3 + ovH : 0);

    CGFloat cursor = h * 0.5 + total / 2.0;
    CGFloat titleH = titleSize * 1.35;

    CATextLayer *title = ASMakeLabel(titleSize, 0.7, [NSColor colorWithWhite:1 alpha:0.97].CGColor);
    title.fontSize = titleSize;
    title.string = ASLocalized(item, @"title", self.langPref);
    title.truncationMode = kCATruncationEnd;
    title.wrapped = NO;
    title.frame = CGRectMake(textX, cursor - titleH, textW, titleH);
    title.shadowColor = [NSColor blackColor].CGColor;
    title.shadowOpacity = 0.6;
    title.shadowRadius = 14;
    title.shadowOffset = CGSizeMake(0, -2);
    [scene addSublayer:title];
    cursor -= titleH + gap1;

    if (tagline.length) {
        CGImageRef tagImg = ASCreateTaglineImage(tagline, tagSize, textW * 0.95);
        if (tagImg) {
            CGFloat iw = CGImageGetWidth(tagImg) / 2.0, ih = CGImageGetHeight(tagImg) / 2.0;
            CALayer *tag = [CALayer layer];
            tag.contents = (__bridge id)tagImg;
            tag.contentsGravity = kCAGravityResize;
            tag.frame = CGRectMake(textX - tagSize * 0.45, cursor - ih + tagSize * 0.55, iw, ih);
            [scene addSublayer:tag];
            CGImageRelease(tagImg);
        }
        cursor -= tagH + gap2;
    }

    NSMutableArray *parts = [NSMutableArray array];
    NSString *country = ASLocalized(item, @"country", self.langPref);
    if (country.length) [parts addObject:country];
    NSInteger year = ASInt(item[@"year"]);
    if (year > 0) [parts addObject:[NSString stringWithFormat:@"%ld", (long)year]];
    NSString *airF = ASAirStatusName(ASStr(item[@"airStatus"]), ASLangCode(item, self.langPref));
    if (airF.length) [parts addObject:airF];
    if (self.showsWatch) {
        NSString *watchF = ASWatchName(ASStr(item[@"watch"]), ASLangCode(item, self.langPref));
        if (watchF.length) [parts addObject:watchF];
    }
    double vote = [item[@"vote"] doubleValue];
    if (vote > 0) [parts addObject:[NSString stringWithFormat:@"TMDB %.1f", vote]];
    NSString *metaText = [parts componentsJoinedByString:@"  ·  "];

    CATextLayer *meta = ASMakeLabel(metaSize, 0.4, [NSColor colorWithWhite:1 alpha:0.55].CGColor);
    meta.fontSize = metaSize;
    meta.string = metaText;
    meta.frame = CGRectMake(textX, cursor - metaSize * 1.6, textW, metaSize * 1.6);
    [scene addSublayer:meta];
    cursor -= metaSize * 1.6 + gap3;

    if (overview.length) {
        NSString *fontName = @"PingFangSC-Regular";
        CGImageRef ovImg = ASCreateParagraphImage(overview, fontName, ovSize, textW, 6);
        if (ovImg) {
            CGFloat iw = CGImageGetWidth(ovImg) / 2.0, ih = CGImageGetHeight(ovImg) / 2.0;
            CALayer *ov = [CALayer layer];
            ov.contents = (__bridge id)ovImg;
            ov.contentsGravity = kCAGravityResize;
            ov.frame = CGRectMake(textX, cursor - ih, iw, ih);
            [scene addSublayer:ov];
            CGImageRelease(ovImg);
        }
    }

    return scene;
}

#pragma mark 封面融合

- (CALayer *)fusionSceneForItem:(NSDictionary *)item size:(CGSize)size {
    CGFloat w = size.width, h = size.height;
    BOOL onLeft = (arc4random_uniform(2) == 0);
    const char *forceSide = getenv("AS_SIDE");
    if (forceSide) onLeft = (strcmp(forceSide, "right") != 0);
    NSColor *bg = [NSColor colorWithCalibratedRed:0.012 green:0.012 blue:0.016 alpha:1];

    CALayer *scene = [CALayer layer];
    scene.frame = CGRectMake(0, 0, w, h);
    scene.backgroundColor = bg.CGColor;

    CGImageRef posterRef = ASCreateThumbnail([NSURL fileURLWithPath:item[@"path"]], h * 1.1);
    if (!posterRef) return scene;

    // 背景：同一张海报重模糊铺满，作为「延伸出去的颜色」
    CGImageRef bgImg = ASBlurredBackground(posterRef, CGSizeMake(w * 0.45, h * 0.45), _ciContext);
    CALayer *wash = [CALayer layer];
    wash.frame = CGRectMake(0, 0, w, h);
    wash.contentsGravity = kCAGravityResizeAspectFill;
    if (bgImg) {
        wash.contents = (__bridge id)bgImg;
        CGImageRelease(bgImg);
    }
    [scene addSublayer:wash];

    // 海报：与屏幕等高，靠一侧，边缘用蒙版羽化融进背景
    CGFloat imgH = h;
    CGFloat imgW = imgH * 2.0 / 3.0;
    CGFloat cardX = onLeft ? -imgW * 0.05 : w - imgW * 0.95;
    // 三层：重模糊背景 → 边缘浮现的中等模糊 → 主体清晰（羽化烘进像素）
    CGFloat imgH2 = imgH, imgW2 = imgW;
    CGImageRef softBlur = ASBlurredBackgroundWithRadius(posterRef, CGSizeMake(imgW2 * 0.45, imgH2 * 0.45), _ciContext, 0.10);

    static const CGFloat sharpA[5] = { 1.0, 1.0, 0.88, 0.45, 0.0 };
    static const CGFloat sharpL[5] = { 0.0, 0.72, 0.86, 0.95, 1.0 };
    static const CGFloat softA[5]  = { 0.0, 0.0, 0.75, 0.40, 0.0 };
    static const CGFloat softL[5]  = { 0.0, 0.62, 0.86, 0.95, 1.0 };

    CGImageRef sharpImg = ASFadeHorizontal(posterRef, onLeft, sharpA, sharpL, 5);
    CGImageRelease(posterRef);
    CGImageRef softImgF = softBlur ? ASFadeHorizontal(softBlur, onLeft, softA, softL, 5) : NULL;
    if (softBlur) CGImageRelease(softBlur);

    CALayer *card = [CALayer layer];
    card.frame = CGRectMake(cardX, 0, imgW, imgH);
    card.contentsGravity = kCAGravityResizeAspectFill;

    if (softImgF) {
        CALayer *soft = [CALayer layer];
        soft.frame = card.frame;
        soft.contentsGravity = kCAGravityResizeAspectFill;
        soft.contents = (__bridge id)softImgF;
        [scene addSublayer:soft];
        CGImageRelease(softImgF);
    }

    if (sharpImg) {
        card.contents = (__bridge id)sharpImg;
        CGImageRelease(sharpImg);
    }
    [scene addSublayer:card];

    // 文字列放在另一侧
    CGFloat gapSide = w * 0.025;
    CGFloat textX = onLeft ? (cardX + imgW * 0.97 + gapSide) : (w * 0.045);
    CGFloat textW = onLeft ? (w - textX - w * 0.05)
                           : (cardX + imgW * 0.12 - textX - w * 0.02);

    CGFloat titleSize = h * 0.046;
    CGFloat tagSize = MAX(16.0, h * 0.022);
    CGFloat metaSize = MAX(14.0, h * 0.0185);
    CGFloat ovSize = MAX(16.0, h * 0.0245);
    CGFloat ovLine = ovSize * 1.80;
    CGFloat ovH = ovLine * 6;

    NSString *tagline = ASTagline(item, self.langPref);
    NSString *overview = ASLocalized(item, @"overview", self.langPref);
    CGFloat tagH = tagline.length ? (tagSize * 1.55 + tagSize * 0.9) : 0;
    CGFloat gap1 = h * 0.020, gap2 = h * 0.010, gap3 = h * 0.020;
    id genreListF = item[@"genres"];
    NSMutableArray *genreNamesF = [NSMutableArray array];
    if ([genreListF isKindOfClass:[NSArray class]]) {
        for (id g in (NSArray *)genreListF) {
            if (genreNamesF.count >= 3) break;
            NSString *n = ASGenreName(@([g integerValue]), ASLangCode(item, self.langPref));
            if (n.length) [genreNamesF addObject:n];
        }
    }
    CGFloat genreSize = MAX(13.0, h * 0.0172);
    CGFloat genreH = genreNamesF.count ? genreSize * 1.55 : 0;
    CGFloat total = titleSize * 1.35 + gap1 + tagH + gap2 + metaSize * 1.6
                  + (genreH > 0 ? h * 0.006 + genreH : 0)
                  + (overview.length ? gap3 + ovH : 0);
    CGFloat cursor = h * 0.5 + total / 2.0;
    CGFloat titleH = titleSize * 1.35;

    CATextLayer *title = ASMakeLabel(titleSize, 0.7, [NSColor colorWithWhite:1 alpha:0.97].CGColor);
    title.fontSize = titleSize;
    title.string = ASLocalized(item, @"title", self.langPref);
    title.truncationMode = kCATruncationEnd;
    title.wrapped = NO;
    title.frame = CGRectMake(textX, cursor - titleH, textW, titleH);
    title.shadowColor = [NSColor blackColor].CGColor;
    title.shadowOpacity = 0.55;
    title.shadowRadius = 12;
    [scene addSublayer:title];
    cursor -= titleH + gap1;

    if (tagline.length) {
        CGImageRef tagImg = ASCreateTaglineImage(tagline, tagSize, textW * 0.95);
        if (tagImg) {
            CGFloat iw = CGImageGetWidth(tagImg) / 2.0, ih = CGImageGetHeight(tagImg) / 2.0;
            CALayer *tag = [CALayer layer];
            tag.contents = (__bridge id)tagImg;
            tag.contentsGravity = kCAGravityResize;
            tag.frame = CGRectMake(textX - tagSize * 0.45, cursor - ih + tagSize * 0.55, iw, ih);
            [scene addSublayer:tag];
            CGImageRelease(tagImg);
        }
        cursor -= tagH + gap2;
    }

    NSMutableArray *parts = [NSMutableArray array];
    NSString *country = ASLocalized(item, @"country", self.langPref);
    if (country.length) [parts addObject:country];
    NSInteger year = ASInt(item[@"year"]);
    if (year > 0) [parts addObject:[NSString stringWithFormat:@"%ld", (long)year]];
    NSString *airF = ASAirStatusName(ASStr(item[@"airStatus"]), ASLangCode(item, self.langPref));
    if (airF.length) [parts addObject:airF];
    if (self.showsWatch) {
        NSString *watchF = ASWatchName(ASStr(item[@"watch"]), ASLangCode(item, self.langPref));
        if (watchF.length) [parts addObject:watchF];
    }
    double vote = [item[@"vote"] doubleValue];
    if (vote > 0) [parts addObject:[NSString stringWithFormat:@"TMDB %.1f", vote]];

    CATextLayer *meta = ASMakeLabel(metaSize, 0.4, [NSColor colorWithWhite:1 alpha:0.55].CGColor);
    meta.fontSize = metaSize;
    meta.string = [parts componentsJoinedByString:@"  ·  "];
    meta.frame = CGRectMake(textX, cursor - metaSize * 1.6, textW, metaSize * 1.6);
    [scene addSublayer:meta];
    cursor -= metaSize * 1.6 + gap3;

    if (genreNamesF.count) {
        NSString *gText = [genreNamesF componentsJoinedByString:@"  /  "];
        CGImageRef gImg = ASCreateTextImage(gText, @"PingFangSC-Regular", genreSize, 0.62, 0.7);
        if (gImg) {
            CGFloat gw = CGImageGetWidth(gImg) / 2.0, gh = CGImageGetHeight(gImg) / 2.0;
            CGFloat fitW = MIN(1.0, textW / MAX(1.0, gw));
            gw *= fitW;
            gh *= fitW;
            CGFloat gy = cursor - h * 0.006 - gh * 0.55;
            CALayer *gl = [CALayer layer];
            gl.contents = (__bridge id)gImg;
            gl.contentsGravity = kCAGravityResize;
            gl.frame = CGRectMake(textX - genreSize * 0.3, gy, gw, gh);
            [scene addSublayer:gl];
            CGImageRelease(gImg);
        }
        cursor -= h * 0.006 + genreH + h * 0.012;
    }


    if (overview.length) {
        CGImageRef ovImg = ASCreateParagraphImage(overview, @"PingFangSC-Regular", ovSize, textW, 6);
        if (ovImg) {
            CGFloat iw = CGImageGetWidth(ovImg) / 2.0, ih = CGImageGetHeight(ovImg) / 2.0;
            CALayer *ov = [CALayer layer];
            ov.contents = (__bridge id)ovImg;
            ov.contentsGravity = kCAGravityResize;
            ov.frame = CGRectMake(textX, cursor - ih, iw, ih);
            [scene addSublayer:ov];
            CGImageRelease(ovImg);
        }
    }

    return scene;
}

#pragma mark 封面融合

#pragma mark - 文字


- (void)applyTextShadow:(CALayer *)layer {
    layer.shadowColor = [NSColor blackColor].CGColor;
    layer.shadowOpacity = 0.85;
    layer.shadowRadius = 10;
    layer.shadowOffset = CGSizeMake(0, -1);
}

- (void)buildCaptionsWith:(NSArray *)pool size:(CGSize)size {
    if (self.mode != 1) return;   // 封面墙不显示任何文字
    CGFloat margin = MAX(48.0, size.width * 0.045);
    CGFloat baseY = self.mode == 1 ? size.height * 0.10 : margin * 0.9;

    self.captionTitle = ASMakeLabel(26, 0.7, [NSColor colorWithWhite:1 alpha:0.94].CGColor);
    self.captionTitle.frame = CGRectMake(margin, baseY + 26, size.width - margin * 2, 36);
    [self applyTextShadow:self.captionTitle];
    [self.stage addSublayer:self.captionTitle];

    self.captionMeta = ASMakeLabel(12.5, 0.4, [NSColor colorWithWhite:1 alpha:0.46].CGColor);
    self.captionMeta.frame = CGRectMake(margin, baseY + 6, size.width - margin * 2, 20);
    [self applyTextShadow:self.captionMeta];
    [self.stage addSublayer:self.captionMeta];

    NSString *unit = self.mode == 1 ? @"部作品在堆叠" : @"张封面在漂移";
    self.captionMeta.string = [NSString stringWithFormat:@"AniShelf · %lu %@", (unsigned long)self.library.count, unit];

    if (self.mode == 1) {
        [self setCaptionForItem:pool.firstObject];
    } else {
        [self rotateCaption];
        self.nextCaption = CACurrentMediaTime() + 7.0;
    }
}

- (void)setCaptionForItem:(NSDictionary *)item {
    if (!item) return;
    NSString *title = ASLocalized(item, @"title", self.langPref);
    NSInteger season = ASInt(item[@"season"]);
    BOOL titleHasSeason = [title containsString:@"季"];
    NSString *text = (season > 0 && !titleHasSeason)
        ? [NSString stringWithFormat:@"%@  ·  第 %ld 季", title, (long)season]
        : title;

    [CATransaction begin];
    [CATransaction setAnimationDuration:0.6];
    self.captionTitle.string = text;
    NSInteger score = ASInt(item[@"score"]);
    NSString *meta = score > 0 ? [NSString stringWithFormat:@"我的评分 %ld / 5", (long)score]
                               : ([item[@"favorite"] boolValue] ? @"收藏" : @"");
    if (meta.length) self.captionMeta.string = meta;
    [CATransaction commit];
}

- (void)rotateCaption {
    if (self.library.count == 0 || self.mode == 1) return;
    self.captionIndex = (self.captionIndex + 1) % self.library.count;
    [self setCaptionForItem:self.library[self.captionIndex]];
}

#pragma mark - 每帧

- (void)animateOneFrame {
    if (self.isPreview) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (self.mode == 1 && now >= self.nextDeck) {
        [self advanceDeck];
        self.nextDeck = now + 5.5;
    }
    if (self.mode >= 2 && now >= self.nextBig) {
        [self advanceBigStill];
        self.nextBig = now + self.bigInterval;
    }
}

#pragma mark - 配置面板

- (BOOL)hasConfigureSheet { return YES; }

- (NSString *)gridSummaryForCols:(NSInteger)pc {
    NSScreen *screen = [NSScreen mainScreen];
    CGFloat w = NSWidth(screen.frame), h = NSHeight(screen.frame);
    if (w < 100 || h < 100) { w = NSWidth(self.bounds); h = NSHeight(self.bounds); }
    CGFloat gapRatio = 0.085;
    CGFloat cardW = pc > 0 ? w / (pc + gapRatio * (pc - 1)) : (w >= h ? h / 6.2 : w / 5.0);
    cardW = MAX(48.0, MIN(cardW, MAX(w, h) / 2.2));
    CGFloat cardH = cardW * 1.5;
    CGFloat gap = cardW * gapRatio;
    NSInteger rows = (NSInteger)llround((h + gap) / (cardH + gap));
    rows = MAX(rows, 1);
    cardH = (h - (rows - 1) * gap) / rows;
    cardW = cardH / 1.5;
    NSInteger cols = (NSInteger)floor(w / (cardW * (1 + gapRatio)));
    cols = MAX(cols, 1);
    return [NSString stringWithFormat:@"当前屏幕约 %ld 列 × %ld 行 · 共 %ld 张", (long)cols, (long)rows, (long)(cols * rows)];
}

- (void)colsChanged:(id)sender {
    NSArray<NSNumber *> *colVals = ASColValues();
    NSInteger pc = colVals[self.colsPopup.indexOfSelectedItem].integerValue;
    self.gridLabel.stringValue = [self gridSummaryForCols:pc];
}

- (void)modeChanged:(id)sender {
    NSInteger m = self.modePopup.indexOfSelectedItem;
    BOOL isWall = (m == 0), isStill = (m == 2), isSlideshow = (m >= 2);
    self.driftPopup.enabled = isWall;
    self.colsPopup.enabled = isWall;
    self.intervalPopup.enabled = isSlideshow;
    self.transPopup.enabled = isSlideshow;
    self.alignPopup.enabled = isStill;
    self.gridLabel.textColor = isWall ? [NSColor secondaryLabelColor] : [NSColor tertiaryLabelColor];
}

- (NSWindow *)configureSheet {
    CFTimeInterval t0 = CACurrentMediaTime();
    ASLog(@"[sheet] begin preview=%d cached=%d", self.isPreview, self.configSheet != nil);
    if (self.configSheet) return self.configSheet;

    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 450, 502)
                                               styleMask:NSWindowStyleMaskTitled
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    win.title = @"AniShelf 封面屏保";
    NSView *cv = win.contentView;

    CGFloat labelX = 28, fieldX = 118, fieldW = 300;
    CGFloat y = 396;

    void (^addLabel)(NSString *, CGFloat) = ^(NSString *text, CGFloat top) {
        NSTextField *l = [NSTextField labelWithString:text];
        l.frame = NSMakeRect(labelX, top, 92, 20);
        [cv addSubview:l];
    };

    addLabel(@"样式", y);
    NSPopUpButton *mode = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y - 4, fieldW, 26) pullsDown:NO];
    [mode addItemsWithTitles:@[ @"漂移封面墙", @"堆叠牌堆", @"大剧照", @"海报聚焦", @"封面融合" ]];
    mode.target = self;
    mode.action = @selector(modeChanged:);
    [cv addSubview:mode];
    self.modePopup = mode;

    y -= 32; addLabel(@"语言", y);
    NSPopUpButton *lang = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y - 4, 170, 26) pullsDown:NO];
    [lang addItemsWithTitles:@[ @"跟随 AniShelf", @"中文", @"English", @"日本語" ]];
    [cv addSubview:lang];
    self.langPopup = lang;

    y -= 32; addLabel(@"漂移方式", y);
    NSPopUpButton *drift = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y - 4, 170, 26) pullsDown:NO];
    [drift addItemsWithTitles:@[ @"横向平移", @"斜向漂移", @"呼吸推拉", @"静止不动" ]];
    [cv addSubview:drift];
    self.driftPopup = drift;

    y -= 32; addLabel(@"每屏列数", y);
    NSPopUpButton *cols = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y - 4, 170, 26) pullsDown:NO];
    [cols addItemsWithTitles:ASColTitles()];
    cols.target = self;
    cols.action = @selector(colsChanged:);
    [cv addSubview:cols];
    self.colsPopup = cols;

    y -= 26;
    NSTextField *grid = [NSTextField labelWithString:@""];
    grid.font = [NSFont systemFontOfSize:11];
    grid.textColor = [NSColor secondaryLabelColor];
    grid.frame = NSMakeRect(fieldX, y, 310, 18);
    [cv addSubview:grid];
    self.gridLabel = grid;

    y -= 24;
    NSTextField *hint = [NSTextField labelWithString:@"卡片按 2:3 排布，行数由屏幕比例自动补足，不会出现半张卡。"];
    hint.font = [NSFont systemFontOfSize:11];
    hint.textColor = [NSColor secondaryLabelColor];
    hint.frame = NSMakeRect(fieldX, y, 320, 18);
    [cv addSubview:hint];

    y -= 34; addLabel(@"切换间隔", y);
    NSPopUpButton *interval = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y - 4, 170, 26) pullsDown:NO];
    [interval addItemsWithTitles:@[ @"6 秒", @"9 秒", @"12 秒", @"20 秒", @"30 秒" ]];
    [cv addSubview:interval];
    self.intervalPopup = interval;

    y -= 32; addLabel(@"切换特效", y);
    NSPopUpButton *trans = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y - 4, 170, 26) pullsDown:NO];
    [trans addItemsWithTitles:@[ @"淡入淡出", @"平移" ]];
    [cv addSubview:trans];
    self.transPopup = trans;

    y -= 32; addLabel(@"大剧照布局", y);
    NSPopUpButton *align = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y - 4, 170, 26) pullsDown:NO];
    [align addItemsWithTitles:@[ @"左对齐", @"居中", @"随机（每张换）" ]];
    [cv addSubview:align];
    self.alignPopup = align;

    y -= 34; addLabel(@"范围", y);
    NSPopUpButton *scope = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y - 4, 170, 26) pullsDown:NO];
    [scope addItemsWithTitles:@[ @"全部作品", @"仅收藏", @"仅看完" ]];
    [cv addSubview:scope];
    self.scopePopup = scope;

    y -= 42;
    NSButton *cap = [NSButton checkboxWithTitle:@"堆叠模式显示片名与评分" target:nil action:nil];
    cap.frame = NSMakeRect(fieldX, y, 300, 20);
    [cv addSubview:cap];
    self.captionCheck = cap;

    y -= 26;
    NSButton *watch = [NSButton checkboxWithTitle:@"大剧照显示观看状态（在看 / 看完 / 想看 / 搁置）" target:nil action:nil];
    watch.frame = NSMakeRect(fieldX, y, 330, 20);
    [cv addSubview:watch];
    self.watchCheck = watch;

    NSButton *ok = [NSButton buttonWithTitle:@"完成" target:self action:@selector(confirmConfig:)];
    ok.frame = NSMakeRect(330, 18, 92, 30);
    ok.keyEquivalent = @"\r";
    [cv addSubview:ok];

    NSButton *cancel = [NSButton buttonWithTitle:@"取消" target:self action:@selector(cancelConfig:)];
    cancel.frame = NSMakeRect(238, 18, 84, 30);
    [cv addSubview:cancel];

    ScreenSaverDefaults *d = [ScreenSaverDefaults defaultsForModuleWithName:kModuleID];
    [mode selectItemAtIndex:[d integerForKey:kPrefMode]];
    [drift selectItemAtIndex:[d integerForKey:kPrefDrift]];

    NSArray<NSNumber *> *colVals = ASColValues();
    NSInteger ci = [colVals indexOfObject:@([d integerForKey:kPrefCols])];
    [cols selectItemAtIndex:(ci == NSNotFound ? 0 : ci)];

    NSArray<NSNumber *> *intVals = @[@6, @9, @12, @20, @30];
    NSInteger ii = [intVals indexOfObject:@([d integerForKey:kPrefBigInterval])];
    [interval selectItemAtIndex:(ii == NSNotFound ? 1 : ii)];
    [trans selectItemAtIndex:[d integerForKey:kPrefBigTransition]];
    [align selectItemAtIndex:MIN(2, MAX(0, [d integerForKey:kPrefBigAlign]))];
    [lang selectItemAtIndex:MIN(3, MAX(0, [d integerForKey:kPrefLang]))];

    [scope selectItemAtIndex:[d integerForKey:kPrefScope]];
    cap.state = [d boolForKey:kPrefCaption] ? NSControlStateValueOn : NSControlStateValueOff;
    watch.state = [d boolForKey:kPrefShowWatch] ? NSControlStateValueOn : NSControlStateValueOff;
    watch.state = [d boolForKey:kPrefShowWatch] ? NSControlStateValueOn : NSControlStateValueOff;
    grid.stringValue = [self gridSummaryForCols:colVals[cols.indexOfSelectedItem].integerValue];

    self.configSheet = win;
    win.releasedWhenClosed = NO;
    [self modeChanged:nil];
    ASLog(@"[sheet] end in %.0f ms", (CACurrentMediaTime() - t0) * 1000);
    return win;
}

- (void)confirmConfig:(id)sender {
    NSArray<NSNumber *> *colVals = ASColValues();
    NSArray<NSNumber *> *intVals = @[@6, @9, @12, @20, @30];

    ScreenSaverDefaults *d = [ScreenSaverDefaults defaultsForModuleWithName:kModuleID];
    [d setInteger:self.modePopup.indexOfSelectedItem forKey:kPrefMode];
    [d setInteger:self.driftPopup.indexOfSelectedItem forKey:kPrefDrift];
    [d setInteger:colVals[self.colsPopup.indexOfSelectedItem].integerValue forKey:kPrefCols];
    [d setInteger:intVals[self.intervalPopup.indexOfSelectedItem].integerValue forKey:kPrefBigInterval];
    [d setInteger:self.transPopup.indexOfSelectedItem forKey:kPrefBigTransition];
    [d setInteger:self.alignPopup.indexOfSelectedItem forKey:kPrefBigAlign];
    [d setInteger:self.langPopup.indexOfSelectedItem forKey:kPrefLang];
    [d setInteger:self.scopePopup.indexOfSelectedItem forKey:kPrefScope];
    [d setBool:self.captionCheck.state == NSControlStateValueOn forKey:kPrefCaption];
    [d setBool:self.watchCheck.state == NSControlStateValueOn forKey:kPrefShowWatch];
    [d setBool:self.watchCheck.state == NSControlStateValueOn forKey:kPrefShowWatch];
    [d synchronize];

    self.mode = self.modePopup.indexOfSelectedItem;
    self.drift = self.driftPopup.indexOfSelectedItem;
    self.colsPref = colVals[self.colsPopup.indexOfSelectedItem].integerValue;
    self.bigInterval = intVals[self.intervalPopup.indexOfSelectedItem].integerValue;
    self.bigTransition = self.transPopup.indexOfSelectedItem;
    self.bigAlign = self.alignPopup.indexOfSelectedItem;
    self.langPref = self.langPopup.indexOfSelectedItem;
    self.scope = self.scopePopup.indexOfSelectedItem;
    self.showsCaption = self.captionCheck.state == NSControlStateValueOn;
    self.showsWatch = self.watchCheck.state == NSControlStateValueOn;
    self.showsWatch = self.watchCheck.state == NSControlStateValueOn;
    [self buildScene];

    [NSApp endSheet:self.configSheet];
    [self.configSheet orderOut:nil];
}

- (void)cancelConfig:(id)sender {
    [NSApp endSheet:self.configSheet];
    [self.configSheet orderOut:nil];
}

@end
