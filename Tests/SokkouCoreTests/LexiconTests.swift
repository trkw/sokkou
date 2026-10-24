import Foundation
import Testing
@testable import SokkouCore

struct SKKDictionaryTests {
    let contents = """
        ;; -*- coding: utf-8 -*-
        ;; okuri-ari entries.
        かk /書/描;えがく/[く/書/]/
        ;; okuri-nasi entries.
        かく /核;nucleus/角/(skk-current-date)/格/
        github /GitHub/
        #かい /#1回/#3回/
        """

    @Test func readsOkuriAriAndOkuriNasi() {
        let dictionary = SKKDictionary(contents: contents)
        #expect(dictionary.words(reading: "か", okuri: "k") == ["書", "描"])
        #expect(dictionary.words(reading: "かく", okuri: nil) == ["核", "角", "格"])
        #expect(SKKDictionary(contents: "ab /(concat \"a\\057b\")/\n").words(reading: "ab", okuri: nil) == ["a/b"])
        #expect(dictionary.words(reading: "github", okuri: nil) == ["GitHub"])
        #expect(dictionary.words(reading: "かく", okuri: "k").isEmpty)
    }

    @Test func numericHeadingsExpand() {
        let lexicon = SKKLexicon(user: UserDictionary(url: temporaryURL()), systems: [SKKDictionary(contents: contents)])
        #expect(lexicon.systemWords(reading: "3かい", okuri: nil) == ["３回", "三回"])
    }
}

struct UserDictionaryTests {
    let url = temporaryURL()

    @Test func registeredWordsComeFirstAndPersist() {
        let dictionary = UserDictionary(url: url)
        dictionary.register("角", reading: "かく", okuri: nil)
        dictionary.register("核", reading: "かく", okuri: nil)
        dictionary.register("書", reading: "か", okuri: "k")
        let reloaded = UserDictionary(url: url)
        #expect(reloaded.words(reading: "かく", okuri: nil) == ["核", "角"])
        #expect(reloaded.words(reading: "か", okuri: "k") == ["書"])
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        #expect(text.contains("かく /核/角/\n"))
        #expect(text.contains("かk /書/\n"))
    }

    @Test func wordsWithDelimitersSurviveSaving() {
        let dictionary = UserDictionary(url: url)
        for word in ["https://example.com/a;b", "[x]", "(y)", "a\\\"b/"] {
            dictionary.register(word, reading: "てすと", okuri: nil)
        }
        #expect(UserDictionary(url: url).words(reading: "てすと", okuri: nil) == ["a\\\"b/", "(y)", "[x]", "https://example.com/a;b"])
    }

    @Test func removedWordsAreIgnoredUntilRegisteredAgain() {
        let dictionary = UserDictionary(url: url)
        dictionary.register("角", reading: "かく", okuri: nil)
        dictionary.remove("角", reading: "かく", okuri: nil)
        dictionary.remove("核", reading: "かく", okuri: nil)
        let reloaded = UserDictionary(url: url)
        #expect(reloaded.words(reading: "かく", okuri: nil).isEmpty)
        #expect(reloaded.isIgnored("核", reading: "かく", okuri: nil))
        reloaded.register("核", reading: "かく", okuri: nil)
        #expect(!reloaded.isIgnored("核", reading: "かく", okuri: nil))
    }

    @Test func completionsAreNewestFirst() {
        let dictionary = UserDictionary(url: url)
        dictionary.register("確認", reading: "かくにん", okuri: nil)
        dictionary.register("核心", reading: "かくしん", okuri: nil)
        dictionary.register("核", reading: "かく", okuri: nil)
        #expect(dictionary.completions(of: "かく") == ["かくしん", "かくにん"])
    }

    @Test func mergeAddsOnlyNewWords() throws {
        let other = temporaryURL()
        try FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "かく /核/角/\nさい /差異/\n".write(to: other, atomically: true, encoding: .utf8)
        let dictionary = UserDictionary(url: url)
        dictionary.register("核", reading: "かく", okuri: nil)
        #expect(dictionary.merge(contentsOf: other) == 2)
        #expect(dictionary.words(reading: "かく", okuri: nil) == ["核", "角"])
        #expect(UserDictionary(url: url).words(reading: "さい", okuri: nil) == ["差異"])
    }
}

struct NumericTests {
    @Test func templateReplacesDigitRuns() {
        #expect(Numeric.template("10がつ3か")?.key == "#がつ#か")
        #expect(Numeric.template("10がつ3か")?.numbers == ["10", "3"])
        #expect(Numeric.template("かく") == nil)
    }

    @Test func formats() {
        #expect(Numeric.format("1024", 1) == "１０２４")
        #expect(Numeric.format("1024", 2) == "一〇二四")
        #expect(Numeric.format("1024", 3) == "千二十四")
        #expect(Numeric.format("10000", 3) == "一万")
        #expect(Numeric.format("20000000", 3) == "二千万")
        #expect(Numeric.format("100010000", 3) == "一億一万")
        #expect(Numeric.format("1234567", 8) == "1,234,567")
        #expect(Numeric.format("0", 3) == "〇")
        #expect(Numeric.format("5", 5) == nil)
    }

    @Test func variantsOfAWord() {
        #expect(Numeric.variants(of: "3000円") == ["3,000円", "３０００円", "三千円", "三〇〇〇円"])
        #expect(Numeric.variants(of: "円").isEmpty)
    }
}

func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("sokkou-\(UUID().uuidString)")
        .appendingPathComponent("skk-jisyo.utf8")
}
