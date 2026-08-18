//
//  File.swift
//  
//
//  Created by Miguel de Icaza on 4/29/21.
//
//
#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import SwiftTerm

final class ColorTests {
    private func rgb8(_ color: Color) -> (Int, Int, Int) {
        return (Int(color.red / 257), Int(color.green / 257), Int(color.blue / 257))
    }

    private func luminance(_ color: Color) -> Double {
        let (r8, g8, b8) = rgb8(color)

        func linearize(_ value: Int) -> Double {
            let srgb = Double(value) / 255.0
            return srgb > 0.04045 ? pow((srgb + 0.055) / 1.055, 2.4) : srgb / 12.92
        }

        let r = linearize(r8)
        let g = linearize(g8)
        let b = linearize(b8)
        return r * 0.2126 + g * 0.7152 + b * 0.0722
    }

    @Test func testExtendedColor() {
        let h = HeadlessTerminal (queue: SwiftTermTests.queue) { exitCode in }
        
        let t = h.terminal!
        
        // This tests that we are setting both foreground and background colors
        // using the semicolon style (there was some ambiguity that I had to deal with).
        t.feed (text: "\u{1b}[38;2;19;49;174;48;2;23;56;179mString\n\r")
        var chattr = t.buffer.getChar(at: Position (col: 0, row: 0))
        #expect(chattr.code == Int32(UInt8(ascii: "S")))
        #expect(chattr.attribute.fg == .trueColor(red: 19, green: 49, blue: 174))
        #expect(chattr.attribute.bg == .trueColor(red: 23, green: 56, blue: 179))
        
        // This is the new style
        t.feed (text: "\u{1b}[38:2::255:10:255mHello\n\r")
        chattr = t.buffer.getChar(at: Position (col: 0, row: 1))
        #expect(chattr.code == Int32(UInt8(ascii: "H")))
        #expect(chattr.attribute.fg == .trueColor(red: 255, green: 10, blue: 255))
        #expect(chattr.attribute.bg == .trueColor(red: 23, green: 56, blue: 179))
        
        // Partial sequences do not get parsed and should not alter current colors.
        t.feed (text: "\u{1b}[38:2::255mPartial\n\r")
        chattr = t.buffer.getChar(at: Position (col: 0, row: 2))
        #expect(chattr.code == Int32(UInt8(ascii: "P")))
        #expect(chattr.attribute.bg == .trueColor(red: 23, green: 56, blue: 179))
        #expect(chattr.attribute.fg == .trueColor(red: 255, green: 10, blue: 255))
    }

    @Test func testAnsi256PaletteXtermStrategy() {
        let palette = Color.setupDefaultAnsiColors(initialColors: Color.xtermColors,
                                                   strategy: .xterm)

        #expect(palette.count == 256)
        for i in 0..<16 {
            #expect(palette[i] == Color.xtermColors[i])
        }

        // Keep historical xterm values for the generated region.
        #expect(rgb8(palette[16]) == (0, 0, 0))
        #expect(rgb8(palette[17]) == (0, 0, 95))
        #expect(rgb8(palette[231]) == (255, 255, 255))
        #expect(rgb8(palette[232]) == (8, 8, 8))
        #expect(rgb8(palette[255]) == (238, 238, 238))
    }

    @Test func testAnsi256PaletteBase16LabStrategyMatchesGhosttyReferenceIndices() {
        let bg = Color(red8: 0, green8: 0, blue8: 0)
        let fg = Color(red8: 255, green8: 255, blue8: 255)

        let generated = Color.setupDefaultAnsiColors(initialColors: Color.xtermColors,
                                                     strategy: .base16Lab,
                                                     backgroundColor: bg,
                                                     foregroundColor: fg)
        let xterm = Color.setupDefaultAnsiColors(initialColors: Color.xtermColors,
                                                 strategy: .xterm)

        #expect(generated.count == 256)
        for i in 0..<16 {
            #expect(generated[i] == Color.xtermColors[i])
        }

        // These values are from the gist/Ghostty interpolation model.
        #expect(rgb8(generated[16]) == (0, 0, 0))
        #expect(rgb8(generated[17]) == (24, 12, 46))
        #expect(rgb8(generated[21]) == (0, 0, 238))
        #expect(rgb8(generated[196]) == (205, 0, 0))
        #expect(rgb8(generated[231]) == (255, 255, 255))
        #expect(rgb8(generated[232]) == (14, 14, 14))
        #expect(rgb8(generated[255]) == (243, 243, 243))

        // Ensure strategy actually changes the generated entries.
        #expect(rgb8(generated[17]) != rgb8(xterm[17]))
        #expect(rgb8(generated[232]) != rgb8(xterm[232]))
    }

    @Test func testAnsi256PaletteDarkThemeHarmoniousMatchesBase16Lab() {
        let bg = Color(red8: 0, green8: 0, blue8: 0)
        let fg = Color(red8: 255, green8: 255, blue8: 255)

        let normal = Color.setupDefaultAnsiColors(initialColors: Color.xtermColors,
                                                  strategy: .base16Lab,
                                                  backgroundColor: bg,
                                                  foregroundColor: fg)
        let harmonious = Color.setupDefaultAnsiColors(initialColors: Color.xtermColors,
                                                      strategy: .base16LabHarmonious,
                                                      backgroundColor: bg,
                                                      foregroundColor: fg)

        for i in 16..<256 {
            #expect(normal[i] == harmonious[i])
        }
    }

    @Test func testAnsi256PaletteLightThemeHarmoniousSkipsInversion() {
        let bg = Color(red8: 255, green8: 255, blue8: 255)
        let fg = Color(red8: 0, green8: 0, blue8: 0)

        let inverted = Color.setupDefaultAnsiColors(initialColors: Color.xtermColors,
                                                    strategy: .base16Lab,
                                                    backgroundColor: bg,
                                                    foregroundColor: fg)
        let harmonious = Color.setupDefaultAnsiColors(initialColors: Color.xtermColors,
                                                      strategy: .base16LabHarmonious,
                                                      backgroundColor: bg,
                                                      foregroundColor: fg)

        #expect(harmonious[16] == bg)
        #expect(inverted[16] != bg)

        var differ = 0
        for i in 16..<232 {
            if inverted[i] != harmonious[i] {
                differ += 1
            }
        }
        #expect(differ > 0)
    }

    @Test func testAnsi256PaletteLightThemeHarmoniousGrayscaleRampDirection() {
        let bg = Color(red8: 255, green8: 255, blue8: 255)
        let fg = Color(red8: 0, green8: 0, blue8: 0)

        let inverted = Color.setupDefaultAnsiColors(initialColors: Color.xtermColors,
                                                    strategy: .base16Lab,
                                                    backgroundColor: bg,
                                                    foregroundColor: fg)
        var previousLuminance = 0.0
        for i in 232..<256 {
            let currentLuminance = luminance(inverted[i])
            #expect(currentLuminance >= previousLuminance)
            previousLuminance = currentLuminance
        }

        let harmonious = Color.setupDefaultAnsiColors(initialColors: Color.xtermColors,
                                                      strategy: .base16LabHarmonious,
                                                      backgroundColor: bg,
                                                      foregroundColor: fg)
        previousLuminance = 1.0
        for i in 232..<256 {
            let currentLuminance = luminance(harmonious[i])
            #expect(currentLuminance <= previousLuminance)
            previousLuminance = currentLuminance
        }
    }

    @Test func testTerminalAnsi256PaletteStrategyRuntimeToggle() {
        let h = HeadlessTerminal(queue: SwiftTermTests.queue) { _ in }
        let terminal = h.terminal!
        terminal.backgroundColor = Color(red8: 0, green8: 0, blue8: 0)
        terminal.foregroundColor = Color(red8: 255, green8: 255, blue8: 255)

        terminal.installPalette(colors: Color.xtermColors)
        #expect(terminal.ansi256PaletteStrategy == .base16Lab)
        #expect(rgb8(terminal.ansiColors[17]) == (24, 12, 46))

        terminal.ansi256PaletteStrategy = .xterm
        #expect(rgb8(terminal.ansiColors[17]) == (0, 0, 95))
        #expect(rgb8(terminal.ansiColors[232]) == (8, 8, 8))

        terminal.ansi256PaletteStrategy = .base16Lab
        #expect(rgb8(terminal.ansiColors[17]) == (24, 12, 46))
        #expect(rgb8(terminal.ansiColors[232]) == (14, 14, 14))
    }

    @Test func testTerminalAnsi256PaletteStrategyRuntimeToggleIncludesHarmonious() {
        let h = HeadlessTerminal(queue: SwiftTermTests.queue) { _ in }
        let terminal = h.terminal!
        terminal.backgroundColor = Color(red8: 255, green8: 255, blue8: 255)
        terminal.foregroundColor = Color(red8: 0, green8: 0, blue8: 0)

        terminal.installPalette(colors: Color.xtermColors)

        terminal.ansi256PaletteStrategy = .base16Lab
        let invertedCubeOrigin = rgb8(terminal.ansiColors[16])
        let invertedGrayStart = rgb8(terminal.ansiColors[232])
        let invertedGrayEnd = rgb8(terminal.ansiColors[255])

        terminal.ansi256PaletteStrategy = .base16LabHarmonious
        let harmoniousCubeOrigin = rgb8(terminal.ansiColors[16])
        let harmoniousGrayStart = rgb8(terminal.ansiColors[232])
        let harmoniousGrayEnd = rgb8(terminal.ansiColors[255])

        #expect(invertedCubeOrigin != harmoniousCubeOrigin)
        #expect(harmoniousCubeOrigin == (255, 255, 255))
        #expect(invertedGrayStart != harmoniousGrayStart)
        #expect(invertedGrayEnd != harmoniousGrayEnd)
        #expect(luminance(terminal.ansiColors[232]) >= luminance(terminal.ansiColors[255]))
    }

    @Test func testTerminalHarmoniousPaletteRebuildsWhenThemeColorsChange() {
        let h = HeadlessTerminal(queue: SwiftTermTests.queue) { _ in }
        let terminal = h.terminal!
        terminal.installPalette(colors: Color.xtermColors)
        terminal.ansi256PaletteStrategy = .base16LabHarmonious

        terminal.backgroundColor = Color(red8: 255, green8: 255, blue8: 255)
        terminal.foregroundColor = Color(red8: 0, green8: 0, blue8: 0)
        let lightThemeGray = rgb8(terminal.ansiColors[232])

        terminal.backgroundColor = Color(red8: 0, green8: 0, blue8: 0)
        terminal.foregroundColor = Color(red8: 255, green8: 255, blue8: 255)
        let darkThemeGray = rgb8(terminal.ansiColors[232])

        #expect(lightThemeGray != darkThemeGray)
        #expect(luminance(terminal.ansiColors[232]) <= luminance(terminal.ansiColors[255]))
    }

    @Test func testBoldBaseColorUsesBrightVariantByDefault() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
        view.installColors(Color.xtermColors)
        view.terminal.feed(text: "\u{001B}[1;37mA\u{001B}[0;97mB")

        let boldBaseColor = renderedForeground(in: view, column: 0)
        let explicitBrightColor = renderedForeground(in: view, column: 1)

        #expect(view.boldUsesBrightColors)
        #expect(boldBaseColor?.isEqual(explicitBrightColor) == true)
    }

    @Test func testBoldBaseColorCanRemainDistinctFromExplicitBrightColor() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
        view.installColors(Color.xtermColors)
        view.terminal.feed(text: "\u{001B}[1;31mA\u{001B}[0;91mB")

        let promotedColor = renderedForeground(in: view, column: 0)
        view.boldUsesBrightColors = false
        let boldBaseColor = renderedForeground(in: view, column: 0)
        let explicitBrightColor = renderedForeground(in: view, column: 1)
        let expectedBaseColor = TTColor.make(color: Color.xtermColors[1])
        let expectedBrightColor = TTColor.make(color: Color.xtermColors[9])

        #expect(promotedColor?.isEqual(expectedBrightColor) == true)
        #expect(boldBaseColor?.isEqual(expectedBaseColor) == true)
        #expect(explicitBrightColor?.isEqual(expectedBrightColor) == true)
        #expect(boldBaseColor?.isEqual(explicitBrightColor) == false)
    }

    @Test func testBoldBaseUnderlineColorHonorsRuntimeSettingInBothAttributePaths() throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
        view.installColors(Color.xtermColors)
        view.terminal.feed(text: "\u{001B}[1;4;58;5;7mA")

        let cell = try #require(view.terminal.getCharData(col: 0, row: 0))
        let expectedBaseColor = TTColor.make(color: Color.xtermColors[7])
        let expectedBrightColor = TTColor.make(color: Color.xtermColors[15])
        let suppliedForeground = TTColor.make(color: Color.xtermColors[2])
        let suppliedBackground = TTColor.make(color: Color.xtermColors[0])

        let cachedBrightUnderline = renderedUnderline(for: cell.attribute, in: view)
        let directBrightUnderline = view.getAttributedValue(
            cell.attribute,
            usingFg: suppliedForeground,
            andBg: suppliedBackground
        )?[.underlineColor] as? NSColor

        view.boldUsesBrightColors = false

        let cachedBaseUnderline = renderedUnderline(for: cell.attribute, in: view)
        let directBaseUnderline = view.getAttributedValue(
            cell.attribute,
            usingFg: suppliedForeground,
            andBg: suppliedBackground
        )?[.underlineColor] as? NSColor

        #expect(cachedBrightUnderline?.isEqual(expectedBrightColor) == true)
        #expect(directBrightUnderline?.isEqual(expectedBrightColor) == true)
        #expect(cachedBaseUnderline?.isEqual(expectedBaseColor) == true)
        #expect(directBaseUnderline?.isEqual(expectedBaseColor) == true)
    }

    private func renderedForeground(in view: TerminalView, column: Int) -> NSColor? {
        guard let cell = view.terminal.getCharData(col: column, row: 0) else {
            return nil
        }
        return view.getAttributes(cell.attribute, withUrl: false)?[.foregroundColor] as? NSColor
    }

    private func renderedUnderline(for attribute: Attribute, in view: TerminalView) -> NSColor? {
        view.getAttributes(attribute, withUrl: false)?[.underlineColor] as? NSColor
    }
}
#endif
