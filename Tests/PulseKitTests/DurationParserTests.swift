import XCTest
@testable import PulseKit

final class DurationParserTests: XCTestCase {

    private func secs(_ s: String, file: StaticString = #filePath, line: UInt = #line) -> Int? {
        DurationParser.seconds(s)
    }

    func testDigitsWithUnits() {
        XCTAssertEqual(secs("25 minutes"), 1500)
        XCTAssertEqual(secs("25m"), 1500)
        XCTAssertEqual(secs("25 min"), 1500)
        XCTAssertEqual(secs("90 seconds"), 90)
        XCTAssertEqual(secs("90s"), 90)
        XCTAssertEqual(secs("2 hours"), 7200)
        XCTAssertEqual(secs("2h"), 7200)
        XCTAssertEqual(secs("1 hour 30 minutes"), 5400)
        XCTAssertEqual(secs("1h30m"), 5400)
        XCTAssertEqual(secs("1h 30m"), 5400)
        XCTAssertEqual(secs("2h5m10s"), 7510)
    }

    func testBareNumberMeansMinutes() {
        XCTAssertEqual(secs("45"), 2700)
        XCTAssertEqual(secs("5"), 300)
    }

    func testTrailingBareNumberInheritsSmallerUnit() {
        XCTAssertEqual(secs("1 hour 30"), 5400)
        XCTAssertEqual(secs("5 min 30"), 330)
    }

    func testNumberWords() {
        XCTAssertEqual(secs("twenty five minutes"), 1500)
        XCTAssertEqual(secs("forty five minutes"), 2700)
        XCTAssertEqual(secs("ten minutes"), 600)
        XCTAssertEqual(secs("an hour"), 3600)
        XCTAssertEqual(secs("a minute"), 60)
        XCTAssertEqual(secs("ninety seconds"), 90)
        XCTAssertEqual(secs("a couple minutes"), 120)
    }

    func testHalvesAndQuarters() {
        XCTAssertEqual(secs("half an hour"), 1800)
        XCTAssertEqual(secs("half hour"), 1800)
        XCTAssertEqual(secs("an hour and a half"), 5400)
        XCTAssertEqual(secs("two and a half hours"), 9000)
        XCTAssertEqual(secs("quarter of an hour"), 900)
        XCTAssertEqual(secs("half a minute"), 30)
    }

    func testColonForms() {
        XCTAssertEqual(secs("12:30"), 750)          // mm:ss
        XCTAssertEqual(secs("1:02:03"), 3723)       // h:mm:ss
    }

    func testPresets() {
        XCTAssertEqual(secs("pomodoro"), 1500)
        XCTAssertEqual(secs("short break"), 300)
        XCTAssertEqual(secs("long break"), 900)
        XCTAssertEqual(secs("deep work"), 5400)
    }

    func testFullSentences() {
        XCTAssertEqual(secs("set a timer for 25 minutes"), 1500)
        XCTAssertEqual(secs("give me twenty minutes to write the essay"), 1200)
        XCTAssertEqual(secs("I want to spend 40 minutes on the deck"), 2400)
    }

    func testLabelExtraction() {
        guard case .start(let s1, let l1) = DurationParser.intent("set a timer for 25 minutes to write the essay")
        else { return XCTFail("expected start") }
        XCTAssertEqual(s1, 1500)
        XCTAssertEqual(l1, "Write the essay")

        guard case .start(let s2, let l2) = DurationParser.intent("write essay for 25 minutes")
        else { return XCTFail("expected start") }
        XCTAssertEqual(s2, 1500)
        XCTAssertEqual(l2, "Write essay")

        guard case .start(let s3, let l3) = DurationParser.intent("25m deep focus on the parser")
        else { return XCTFail("expected start") }
        XCTAssertEqual(s3, 1500)
        XCTAssertEqual(l3, "Deep focus on the parser")

        guard case .start(_, let l4) = DurationParser.intent("30 minutes")
        else { return XCTFail("expected start") }
        XCTAssertNil(l4)
    }

    func testLabelPreservesOriginalCasing() {
        guard case .start(_, let label) = DurationParser.intent("20 minutes on the Anthropic writeup")
        else { return XCTFail("expected start") }
        XCTAssertEqual(label, "Anthropic writeup")
    }

    func testTransportCommands() {
        XCTAssertEqual(DurationParser.intent("pause"), .pause)
        XCTAssertEqual(DurationParser.intent("hold on"), .pause)
        XCTAssertEqual(DurationParser.intent("resume"), .resume)
        XCTAssertEqual(DurationParser.intent("stop"), .stop)
        XCTAssertEqual(DurationParser.intent("cancel"), .stop)
        XCTAssertEqual(DurationParser.intent("reset"), .stop)
        XCTAssertEqual(DurationParser.intent("start over again"), .restart)
    }

    func testAddTime() {
        XCTAssertEqual(DurationParser.intent("add 5 minutes"), .add(seconds: 300))
        XCTAssertEqual(DurationParser.intent("give me five more minutes"), .add(seconds: 300))
        XCTAssertEqual(DurationParser.intent("plus 10"), .add(seconds: 600))
    }

    func testUntilWallClock() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 14, minute: 0))!
        let tokens = DurationParser.tokenize("until 3pm")
        XCTAssertEqual(DurationParser.matchUntil(tokens, now: now)?.seconds, 3600)

        let tokens2 = DurationParser.tokenize("until 4:30")
        XCTAssertEqual(DurationParser.matchUntil(tokens2, now: now)?.seconds, 150 * 60)

        // Already past today → rolls to the next occurrence rather than going negative.
        let tokens3 = DurationParser.tokenize("until 9am")
        let s3 = DurationParser.matchUntil(tokens3, now: now)?.seconds ?? -1
        XCTAssertGreaterThan(s3, 0)
    }

    func testGarbageIsUnrecognized() {
        guard case .unrecognized = DurationParser.intent("banana sandwich") else {
            return XCTFail("expected unrecognized")
        }
    }

    func testHomophoneGuard() {
        // "for" only becomes 4 when a unit follows it.
        guard case .start(let s, let l) = DurationParser.intent("10 minutes for the review")
        else { return XCTFail("expected start") }
        XCTAssertEqual(s, 600)
        XCTAssertEqual(l, "Review")
    }

    func testEmptyInput() {
        guard case .unrecognized = DurationParser.intent("") else {
            return XCTFail("expected unrecognized")
        }
    }
}

final class TimeFormatTests: XCTestCase {
    func testClock() {
        XCTAssertEqual(TimeFormat.clock(1500), "25:00")
        XCTAssertEqual(TimeFormat.clock(59.4), "1:00")
        XCTAssertEqual(TimeFormat.clock(3723), "1:02:03")
        XCTAssertEqual(TimeFormat.clock(0), "0:00")
        XCTAssertEqual(TimeFormat.clock(-23), "+0:23")
        XCTAssertEqual(TimeFormat.clock(-61), "+1:01")
    }

    func testCompactDropsSecondsPastAnHour() {
        XCTAssertEqual(TimeFormat.compact(3723), "1:02")
        XCTAssertEqual(TimeFormat.compact(1500), "25:00")
    }

    func testHumane() {
        XCTAssertEqual(TimeFormat.humane(1500), "25 min")
        XCTAssertEqual(TimeFormat.humane(5400), "1h 30m")
        XCTAssertEqual(TimeFormat.humane(3600), "1h")
        XCTAssertEqual(TimeFormat.humane(45), "45s")
    }

    func testPulseEnvelopeShape() {
        XCTAssertEqual(PulseEnvelope.intensity(elapsed: -1), 0)
        XCTAssertEqual(PulseEnvelope.intensity(elapsed: 0), 0, accuracy: 0.001)
        XCTAssertEqual(PulseEnvelope.intensity(elapsed: PulseEnvelope.attack), 1.0, accuracy: 0.001)
        XCTAssertEqual(PulseEnvelope.intensity(elapsed: 99), 0)
        // Decays monotonically after the peak.
        let a = PulseEnvelope.intensity(elapsed: 0.5)
        let b = PulseEnvelope.intensity(elapsed: 1.0)
        XCTAssertGreaterThan(a, b)
        XCTAssertGreaterThan(b, 0)
    }
}
