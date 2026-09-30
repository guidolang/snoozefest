import Foundation
import Testing
@testable import SnoozeFest

struct CSVCodecTests {
    let day = Day.start(Date(timeIntervalSince1970: 1_750_000_000))

    @Test func roundTrip() throws {
        let content = CSVCodec.Content(
            nights: [
                Night(date: day, segments: [10]),
                Night(date: Day.adding(1, to: day), segments: [5.5, 4, 0.75], excluded: true,
                      note: "flight, \"long\" day\nsecond line"),
            ],
            interventions: [
                InterventionEvent(date: day, name: "CBD (Sunsoil)", kind: .started, details: "5mg, evening"),
                InterventionEvent(date: Day.adding(1, to: day), name: "XR Melatonin", kind: .oneTime),
            ]
        )
        let text = CSVCodec.encode(content)
        let decoded = try CSVCodec.decode(text)
        #expect(decoded == content)
    }

    @Test func encodesExpectedColumns() {
        let text = CSVCodec.encode(.init(nights: [Night(date: day, segments: [5.5, 4])]))
        let lines = text.split(separator: "\n")
        #expect(lines[0] == "record_type,date,segment_1,segment_2,segment_3,segment_4,total_hours,interrupted,excluded,intervention_kind,intervention_name,intervention_details,note")
        #expect(lines[1] == "night,\(Day.iso(day)),5.5,4,,,9.5,true,false,,,,")
    }

    @Test func decodesMinimalFileAndCRLF() throws {
        let text = "record_type,date,segment_1,segment_2\r\nnight,2025-04-06,5.5,4\r\nnight,2025-04-07,10,\r\n"
        let decoded = try CSVCodec.decode(text)
        #expect(decoded.nights.map(\.segments) == [[5.5, 4], [10]])
    }

    @Test func rejectsBadInput() {
        #expect(throws: CSVCodec.ImportError.self) { try CSVCodec.decode("") }
        #expect(throws: CSVCodec.ImportError.self) { try CSVCodec.decode("foo,bar\n1,2") }
        #expect(throws: CSVCodec.ImportError.self) {
            try CSVCodec.decode("record_type,date,segment_1\nnight,2025-13-45,9")
        }
        #expect(throws: CSVCodec.ImportError.self) {
            try CSVCodec.decode("record_type,date,segment_1\nnight,2025-04-01,9\nnight,2025-04-01,8")
        }
    }
}
