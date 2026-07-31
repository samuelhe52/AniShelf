//
//  TMDbImageAndTranslationTests+SVG.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import Foundation
import Kingfisher
import TMDb
import Testing

@testable import DataProvider
@testable import MyAnimeList

extension TMDbImageAndTranslationTests {
    @Test func testSVGImageProcessorRasterizesInlineSVG() throws {
        let processor = SVGImageProcessor(
            targetSize: CGSize(width: 24, height: 24),
            scale: 2
        )
        let svgData = Data(
            #"""
            <svg width="12" height="12" viewBox="0 0 12 12" xmlns="http://www.w3.org/2000/svg">
              <rect width="12" height="12" fill="red"/>
            </svg>
            """#.utf8)

        let image = try #require(
            processor.process(
                item: .data(svgData),
                options: KingfisherParsedOptionsInfo([.processor(processor)])
            )
        )

        #expect(image.size == CGSize(width: 24, height: 24))
        #expect(image.scale == 2)
    }

    @Test func testSVGImageProcessorPreservesAspectRatioWithinTargetSize() throws {
        let processor = SVGImageProcessor(
            targetSize: CGSize(width: 24, height: 24),
            scale: 2
        )
        let wideSVGData = Data(
            #"""
            <svg width="120" height="40" viewBox="0 0 120 40" xmlns="http://www.w3.org/2000/svg">
              <rect width="120" height="40" fill="red"/>
            </svg>
            """#.utf8)
        let tallSVGData = Data(
            #"""
            <svg width="40" height="120" viewBox="0 0 40 120" xmlns="http://www.w3.org/2000/svg">
              <rect width="40" height="120" fill="blue"/>
            </svg>
            """#.utf8)

        let wideImage = try #require(
            processor.process(
                item: .data(wideSVGData),
                options: KingfisherParsedOptionsInfo([.processor(processor)])
            )
        )
        let tallImage = try #require(
            processor.process(
                item: .data(tallSVGData),
                options: KingfisherParsedOptionsInfo([.processor(processor)])
            )
        )

        #expect(wideImage.size == CGSize(width: 24, height: 8))
        #expect(tallImage.size == CGSize(width: 8, height: 24))
        #expect(wideImage.scale == 2)
        #expect(tallImage.scale == 2)
    }

    @Test func testSVGImageProcessorIdentifiersIncludeSizeAndScale() {
        let scaleTwo = SVGImageProcessor(targetSize: CGSize(width: 500, height: 500), scale: 2)
        let scaleThree = SVGImageProcessor(targetSize: CGSize(width: 500, height: 500), scale: 3)
        let intrinsic = SVGImageProcessor(scale: 3)

        #expect(scaleTwo.identifier != scaleThree.identifier)
        #expect(scaleThree.identifier != intrinsic.identifier)
    }

    @Test func testSVGImageProcessorRejectsInvalidData() {
        let processor = SVGImageProcessor(targetSize: CGSize(width: 24, height: 24), scale: 2)

        #expect(
            processor.process(
                item: .data(Data("not svg".utf8)),
                options: KingfisherParsedOptionsInfo([.processor(processor)])
            ) == nil
        )
    }

}
