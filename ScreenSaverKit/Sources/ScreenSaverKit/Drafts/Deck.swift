//
//  Deck.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import QuartzCore

/// Settings every draft director starts from.
struct ScreenSaverDraftContext: Sendable {
    let entries: [ScreenSaverManifest.Entry]
    let settings: ScreenSaverManifest.Settings
    let draft: ScreenSaverDraft
    let size: CGSize
    let scale: CGFloat
    let seed: UInt64

    var details: Set<ScreenSaverManifest.Detail> { Set(settings.details) }
    var interval: TimeInterval { settings.interval.isFinite ? min(max(settings.interval, 1), 3_600) : 12 }
    var unit: CGFloat { min(size.width, size.height) }

    func makeDirector(_ layout: ScreenSaverDraftLayout) -> (any ScreenSaverStageDirector)? {
        guard !entries.isEmpty else { return nil }
        return switch layout {
        case .deckFan: DeckDirector(self, style: .fan)
        case .deckPile: DeckDirector(self, style: .pile)
        case .flipWall: FlipWallDirector(self)
        case .seasonTimeline: TimelineDirector(self)
        case .depthDrift: DepthDriftDirector(self)
        case .coverFusion, .editorialCover: nil
        }
    }
}

// MARK: - Director

enum DeckStyle: Sendable { case fan, pile }

struct DeckCard: Sendable {
    let entry: ScreenSaverManifest.Entry
    let poster: CGImage
    /// The poster's colour in each cell of a 3 × 3 grid, for the wash.
    let samples: [ScreenSaverColor]
}

enum DeckStep: ScreenSaverStageStep {
    case open(DeckStyle, [DeckCard], details: Set<ScreenSaverManifest.Detail>, total: Int)
    /// The front card leaves; `incoming` joins at the back.
    case deal(incoming: DeckCard)

    @MainActor func makeStage(size: CGSize, scale: CGFloat, wash: ScreenSaverWash) -> (any ScreenSaverStage)? {
        guard case .open(let style, let cards, let details, let total) = self else { return nil }
        return DeckStage(
            style: style, cards: cards, details: details, total: total, size: size, scale: scale, wash: wash)
    }
}

struct DeckDirector: ScreenSaverStageDirector {
    private let style: DeckStyle
    private let entries: [ScreenSaverManifest.Entry]
    private let details: Set<ScreenSaverManifest.Detail>
    private let depth: Int
    private let interval: TimeInterval
    private let pixelSize: Int
    private var cycle: ScreenSaverEntryCycle
    private var opened = false

    init(_ context: ScreenSaverDraftContext, style: DeckStyle) {
        self.style = style
        entries = context.entries
        details = context.details
        // A small library shows fewer cards rather than the same poster twice in one deck.
        let requested = style == .pile ? context.draft.pileDepth : context.draft.deckDepth
        depth = min(ScreenSaverDraft.deckDepthRange.clamp(requested), context.entries.count)
        interval = context.interval
        pixelSize = ScreenSaverSceneLoader.pixelLimit(context.size.height * 0.62 * context.scale, 1_500)
        cycle = ScreenSaverEntryCycle(count: context.entries.count, spacing: depth, seed: context.seed)
    }

    mutating func next(image: ScreenSaverImageLoader) -> (step: any ScreenSaverStageStep, duration: TimeInterval)? {
        let size = pixelSize
        func card() -> DeckCard? {
            guard let drawn = cycle.nextLoaded(entries, load: { image($0.poster, size) }) else { return nil }
            return DeckCard(
                entry: entries[drawn.index], poster: drawn.image,
                samples: ScreenSaverArt.samples(of: drawn.image, columns: 3, rows: 3))
        }
        if opened {
            return card().map { (DeckStep.deal(incoming: $0), interval) }
        }
        var cards: [DeckCard] = []
        while cards.count < depth, let next = card() { cards.append(next) }
        guard !cards.isEmpty else { return nil }
        opened = true
        return (DeckStep.open(style, cards, details: details, total: entries.count), interval)
    }
}

// MARK: - Stage

@MainActor
final class DeckStage: ScreenSaverStage {
    let usesWash = true
    private struct Pose {
        var transform: CATransform3D
        var shade: Float
        var shadow: Float = 0.5
    }

    private enum FanDeal {
        static let duration: TimeInterval = 0.95
        // The outgoing card has cleared the new front enough to fade and hand off the caption.
        static let reveal: TimeInterval = 0.60
    }

    private enum PileDeal {
        static let duration: TimeInterval = 0.95
        static let reveal: TimeInterval = 0.59
        static let advanceDelay: TimeInterval = 0.12
        static let advanceDuration: TimeInterval = 0.70
    }

    let layer = CALayer()
    private let style: DeckStyle
    private let details: Set<ScreenSaverManifest.Detail>
    private let total: Int
    private let depth: Int
    private let layouts: ScreenSaverLayouts
    private let size: CGSize
    private let cardSize: CGSize
    private let stack = CALayer()
    private var cards: [(card: DeckCard, layer: CALayer)] = []
    private let wash: ScreenSaverWash
    private var caption: CALayer?
    private var dealt = 0

    private var unit: CGFloat { min(size.width, size.height) }
    private var portrait: Bool { size.height > size.width }

    init(
        style: DeckStyle, cards: [DeckCard], details: Set<ScreenSaverManifest.Detail>, total: Int, size: CGSize,
        scale: CGFloat, wash: ScreenSaverWash
    ) {
        self.style = style
        self.wash = wash
        self.details = details.subtracting([.overview])
        self.total = total
        self.size = size
        depth = cards.count
        layouts = ScreenSaverLayouts(size: size, scale: scale)

        let height: CGFloat =
            switch (style, size.height > size.width) {
            case (.fan, false): min(size.height * 0.56, size.width * 0.45)
            // The fan spreads to about twice the card width.
            case (.fan, true): min(size.height * 0.38, size.width * 0.62)
            case (.pile, false): min(size.height * 0.58, size.width * 0.45)
            case (.pile, true): min(size.height * 0.4, size.width * 0.8)
            }
        cardSize = CGSize(width: height * 2 / 3, height: height)

        // No ground: the renderer's wash flows behind the deck.
        layer.frame = CGRect(origin: .zero, size: size)
        layer.masksToBounds = true

        // The stack's anchor is where the front card sits; perspective converges there.
        stack.bounds = layer.bounds
        stack.anchorPoint = CGPoint(x: anchor.x / size.width, y: anchor.y / size.height)
        stack.position = anchor
        if style == .pile {
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / (size.width * 0.8)
            stack.sublayerTransform = perspective
        }
        layer.addSublayer(stack)

        for (slot, card) in cards.enumerated() {
            let cardLayer = makeCard(card)
            apply(pose(slot), to: cardLayer)
            stack.insertSublayer(cardLayer, at: 0)
            self.cards.append((card, cardLayer))
        }
        updateWash()
        updateCaption(animated: false)
    }

    func apply(_ step: any ScreenSaverStageStep) {
        guard case .deal(let incoming) = step as? DeckStep, !cards.isEmpty else { return }
        let leaving = cards.removeFirst()
        let direction: CGFloat = dealt.isMultiple(of: 2) ? 1 : -1
        dealt += 1
        leave(leaving.layer, direction: direction)

        for (slot, card) in cards.enumerated() {
            let delay = style == .pile ? PileDeal.advanceDelay : 0.09 + Double(slot) * 0.018
            move(card.layer, to: pose(slot), delay: delay)
        }

        let newcomer = makeCard(incoming)
        let rearPose = pose(cards.count)
        newcomer.opacity = 0
        stack.insertSublayer(newcomer, at: 0)
        if style == .fan {
            var tucked = rearPose
            // Start behind the hand and slide out on the side of the rear slot.
            tucked.transform.m41 *= 0.65
            tucked.transform.m42 -= cardSize.height * 0.055
            apply(tucked, to: newcomer)
            newcomer.animate("transform", to: rearPose.transform, duration: 0.64, delay: 0.24)
            newcomer.animate("opacity", to: 1, duration: 0.32, delay: 0.24)
        } else {
            // Enter from one slot deeper, keeping the same spacing as the moving pile.
            apply(pose(cards.count + 1), to: newcomer)
            move(newcomer, to: rearPose, delay: PileDeal.advanceDelay)
            newcomer.animate("opacity", to: 1, duration: 0.42, delay: PileDeal.advanceDelay)
        }
        cards.append((incoming, newcomer))

        updateWash()
        updateCaption(animated: true)
    }

    // MARK: Geometry

    /// The front card's centre.
    private var anchor: CGPoint {
        switch (style, portrait) {
        case (.fan, _):
            // The deck and its caption form one block centred on the screen.
            let block = cardSize.height + unit * 0.05 + unit * 0.17
            return CGPoint(x: size.width / 2, y: size.height / 2 + block / 2 - cardSize.height / 2)
        // The pile's middle card sits at the centre of the screen.
        case (.pile, false):
            return CGPoint(x: size.width / 2, y: size.height / 2)
        case (.pile, true):
            return CGPoint(x: size.width / 2, y: size.height * 0.55)
        }
    }

    private func pose(_ slot: Int) -> Pose {
        let width = cardSize.width
        let height = cardSize.height
        let s = CGFloat(slot)
        var transform = CATransform3DIdentity
        switch style {
        case .fan:
            // Alternate sides, each pair fanned a little wider and lower.
            let pair = CGFloat((slot + 1) / 2)
            let side: CGFloat = slot.isMultiple(of: 2) ? -1 : 1
            let x = slot == 0 ? 0 : side * pair * width * 0.23
            let y = slot == 0 ? 0 : (pair == 1 ? height * 0.012 : -(pair - 1) * height * 0.03)
            let scale = 1 - pair * 0.03
            transform = CATransform3DTranslate(transform, x, y, 0)
            transform = CATransform3DRotate(transform, -side * pair * 6 * .pi / 180, 0, 0, 1)
            transform = CATransform3DScale(transform, scale, scale, 1)
            return Pose(transform: transform, shade: Float(min(pair * 0.14, 0.6)))
        case .pile:
            // From PR #28: the pile is centred on its middle card. Each deeper card sits a little up
            // and to the right, a little smaller, and turned a little further counter-clockwise, so
            // the front card leans one way and the back card the other.
            let mid = CGFloat(depth - 1) / 2
            let scale = 1 - 0.028 * s
            transform = CATransform3DTranslate(
                transform, (s - mid) * width * 0.026, (s - mid) * height * 0.048, 0)
            transform = CATransform3DRotate(transform, (s - mid) * 0.75 * .pi / 180, 0, 0, 1)
            transform = CATransform3DScale(transform, scale, scale, 1)
            return Pose(transform: transform, shade: Float(min(s * 0.018, 0.2)), shadow: s == 0 ? 0.75 : 0.25)
        }
    }

    private func apply(_ pose: Pose, to card: CALayer) {
        card.transform = pose.transform
        card.shadowOpacity = pose.shadow
        card.sublayers?.last?.opacity = pose.shade
    }

    private func move(_ card: CALayer, to pose: Pose, delay: TimeInterval) {
        let duration = style == .pile ? PileDeal.advanceDuration : 0.70
        card.animate("transform", to: pose.transform, duration: duration, delay: delay)
        if card.shadowOpacity != pose.shadow {
            card.animate("shadowOpacity", to: pose.shadow, duration: duration, delay: delay)
        }
        card.sublayers?.last?.animate("opacity", to: pose.shade, duration: duration, delay: delay)
    }

    private func leave(_ card: CALayer, direction: CGFloat) {
        // Lift the card above the deck for its exit.
        card.removeAllAnimations()
        card.removeFromSuperlayer()
        stack.addSublayer(card)
        let group = CAAnimationGroup()
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        switch style {
        case .fan:
            // Sweep upward and outward along one curve, without a stop between lift and throw.
            let start = card.position
            let width = direction * cardSize.width
            let height = cardSize.height
            let end = CGPoint(x: start.x + 1.62 * width, y: start.y + 0.02 * height)
            let path = CGMutablePath()
            path.move(to: start)
            path.addCurve(
                to: end,
                control1: CGPoint(x: start.x + 0.38 * width, y: start.y + 0.23 * height),
                control2: CGPoint(x: start.x + 1.13 * width, y: start.y + 0.08 * height))
            let timing = CAMediaTimingFunction(controlPoints: 0.35, 0, 0.57, 1)
            let motion = CAKeyframeAnimation(keyPath: "position")
            motion.path = path
            motion.duration = FanDeal.duration
            motion.timingFunction = timing

            let angle = -direction * 24 * .pi / 180
            let tilt = CABasicAnimation(keyPath: "transform.rotation.z")
            tilt.fromValue = 0
            tilt.toValue = angle
            tilt.duration = FanDeal.duration
            tilt.timingFunction = timing

            fade.keyTimes = [0, NSNumber(value: FanDeal.reveal / FanDeal.duration), 1]
            fade.values = [1, 1, 0]
            group.animations = [motion, tilt, fade]
            group.duration = FanDeal.duration
            card.position = end
            card.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        case .pile:
            // One toss: translate up-left, grow and turn continuously from the front pose.
            let start = card.transform
            var end = start
            end.m41 -= cardSize.width * 1.36
            end.m42 += cardSize.height * 0.42
            end = CATransform3DRotate(end, -10 * .pi / 180, 0, 0, 1)
            end = CATransform3DScale(end, 1.13, 1.13, 1)
            let motion = CABasicAnimation(keyPath: "transform")
            motion.fromValue = NSValue(caTransform3D: start)
            motion.toValue = NSValue(caTransform3D: end)
            motion.duration = PileDeal.duration
            motion.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 0.06, 0.54, 1)
            fade.keyTimes = [0, NSNumber(value: PileDeal.reveal / PileDeal.duration), 1]
            fade.values = [1, 1, 0]
            group.animations = [motion, fade]
            group.duration = PileDeal.duration
            card.transform = end
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock { card.removeFromSuperlayer() }
        card.opacity = 0
        card.add(group, forKey: "leave")
        CATransaction.commit()
    }

    private func makeCard(_ card: DeckCard) -> CALayer {
        let radius = cardSize.width * 0.035
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: cardSize)
        layer.position = stack.convert(anchor, from: self.layer)
        layer.shadowColor = CGColor(gray: 0, alpha: 1)
        layer.shadowOpacity = 0.5
        layer.shadowRadius = unit * (style == .pile ? 0.035 : 0.022)
        layer.shadowOffset = CGSize(width: 0, height: -unit * (style == .pile ? 0.018 : 0.012))
        layer.shadowPath = CGPath(
            roundedRect: layer.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)

        let art = CALayer()
        art.frame = layer.bounds
        art.contents = card.poster
        art.contentsGravity = .resizeAspectFill
        art.cornerRadius = radius
        art.masksToBounds = true
        layer.addSublayer(art)

        let edge = CALayer()
        edge.frame = layer.bounds
        edge.cornerRadius = radius
        edge.borderWidth = 1
        edge.borderColor = CGColor(gray: 1, alpha: 0.14)
        layer.addSublayer(edge)

        let shade = CALayer()
        shade.frame = layer.bounds
        shade.backgroundColor = CGColor(gray: 0, alpha: 1)
        shade.cornerRadius = radius
        shade.opacity = 0
        layer.addSublayer(shade)
        return layer
    }

    // MARK: Wash and caption

    private func updateWash() {
        switch style {
        case .fan:
            if let front = cards.first?.card {
                wash.show(.shaded(front.samples, columns: 3, rows: 3, brightness: 0.5))
            }
        case .pile:
            // The three front posters, woven together: each cell takes its region's colour from one of them.
            let samples = cards.prefix(3).map(\.card.samples)
            guard !samples.isEmpty else { return }
            let colors = (0..<9).map { cell in
                let source = samples[(cell / 3 + cell % 3) % samples.count]
                return source[cell]
            }
            wash.show(.shaded(colors, columns: 3, rows: 3, brightness: 0.48))
        }
    }

    private func updateCaption(animated: Bool) {
        guard let entry = cards.first?.card.entry else { return }
        let next = CALayer()
        next.frame = layer.bounds
        let margin = unit * 0.06
        switch style {
        case .fan:
            let width = min(size.width * 0.72, unit * 1.1)
            var lines = layouts.posterFocusLines(entry, details: details, width: width)
            if let title = lines.first, title.weight == .bold {
                // Under a deck the title is smaller than on Poster Focus.
                lines[0] = .init(
                    text: title.text,
                    size: layouts.fittedTitle(title.text, width: width, largest: 0.046, smallest: 0.03),
                    weight: .bold, alpha: title.alpha, lines: 2)
            }
            let block = layouts.stack(lines, width: width, center: true)
            let top = anchor.y - cardSize.height / 2 - unit * 0.05
            layouts.place(block, x: (size.width - width) / 2, top: top, in: next)
        case .pile:
            let width =
                portrait
                ? size.width - margin * 2 : min(unit * 0.62, size.width / 2 - cardSize.width / 2 - margin * 2)
            // Quiet: the title, then one small line with the place in the library and the facts.
            let ordinal = dealt % max(total, 1) + 1
            var lines: [ScreenSaverLayouts.Line] = []
            if let title = entry.title, !title.isEmpty {
                lines.append(
                    .init(
                        text: title, size: layouts.fittedTitle(title, width: width, largest: 0.03, smallest: 0.022),
                        weight: .semibold, alpha: 0.95, lines: 2))
            }
            var facts = layouts.factsLine(entry, details: details)
            if details.contains(.season), let season = entry.season, !season.isEmpty {
                facts = facts.isEmpty ? season : season + " · " + facts
            }
            let count = String(format: "%02d / %02d", ordinal, total)
            lines.append(
                .init(
                    text: facts.isEmpty ? count : count + " · " + facts, size: unit * 0.014, weight: .regular,
                    alpha: 0.5, lines: 2, spaceBefore: unit * 0.008))
            let block = layouts.stack(lines, width: width)
            layouts.place(block, x: margin, top: margin + block.height, in: next)
        }
        crossfade(from: caption, to: next, animated: animated)
        caption = next
    }

    private func crossfade(from old: CALayer?, to next: CALayer, animated: Bool) {
        layer.addSublayer(next)
        guard let old else { return }
        guard animated else {
            old.removeFromSuperlayer()
            return
        }
        let reveal = style == .fan ? FanDeal.reveal : PileDeal.reveal
        next.opacity = 0
        next.animate("opacity", to: 1, duration: 0.34, delay: reveal)
        CATransaction.begin()
        CATransaction.setCompletionBlock { old.removeFromSuperlayer() }
        old.animate("opacity", to: 0, duration: 0.22, delay: reveal - 0.22)
        CATransaction.commit()
    }
}
