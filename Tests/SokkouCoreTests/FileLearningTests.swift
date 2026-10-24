import Foundation
import Testing
@testable import SokkouCore

struct FileLearningTests {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sokkou-\(UUID().uuidString)")
        .appendingPathComponent("learning.json")

    @Test func remembersAcrossInstances() {
        FileLearning(url: url).record(reading: "かく", word: "核")
        #expect(FileLearning(url: url).preferred(for: "かく") == "核")
    }

    @Test func forgetClearsTheFile() {
        let learning = FileLearning(url: url)
        learning.record(reading: "かく", word: "核")
        learning.forget()
        #expect(FileLearning(url: url).preferred(for: "かく") == nil)
    }

    @Test func missingFileStartsEmpty() {
        #expect(FileLearning(url: url).preferred(for: "かく") == nil)
    }
}
