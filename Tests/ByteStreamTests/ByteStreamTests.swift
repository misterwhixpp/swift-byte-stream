import Foundation
import XCTest

@testable import ByteStream

final class ByteStreamTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    func testReadFromFile() async throws {
        let testData = "Hello, World!".data(using: .utf8)!
        let fileURL = tempDirectory.appendingPathComponent("test.txt")
        try testData.write(to: fileURL)

        let stream = try ByteStream(forReading: fileURL)
        let readData = try await stream.readToEnd()

        XCTAssertEqual(readData, testData)
    }

    func testWriteToFile() async throws {
        let testData = "Hello, World!".data(using: .utf8)!
        let fileURL = tempDirectory.appendingPathComponent("test.txt")

        let stream = try ByteStream(forWriting: fileURL)
        try await stream.write(testData)
        await stream.close()

        let readData = try Data(contentsOf: fileURL)
        XCTAssertEqual(readData, testData)
    }

    func testReadAndWriteToSameFile() async throws {
        let fileURL = tempDirectory.appendingPathComponent("test.txt")
        let testData = "Hello, World!".data(using: .utf8)!

        let stream = try ByteStream(forReadingAndWriting: fileURL)
        try await stream.write(testData)

        // Reset stream position to beginning
        await stream.close()
        let readStream = try ByteStream(forReading: fileURL)
        let readData = try await readStream.readToEnd()

        XCTAssertEqual(readData, testData)
    }

    func testHandleNonExistentFile() async throws {
        let fileURL = tempDirectory.appendingPathComponent("nonexistent.txt")

        do {
            _ = try ByteStream(forReading: fileURL)
            XCTFail("Expected error when reading non-existent file")
        } catch {
            XCTAssertTrue(error is StreamError)
        }
    }

    func testReadWithCustomBufferSize() async throws {
        let testData = "Hello, World!".data(using: .utf8)!
        let fileURL = tempDirectory.appendingPathComponent("test.txt")
        try testData.write(to: fileURL)

        let stream = try ByteStream(forReading: fileURL, bufferSize: 4)
        let readData = try await stream.readToEnd()

        XCTAssertEqual(readData, testData)
    }

    func testWriteLargeData() async throws {
        let fileURL = tempDirectory.appendingPathComponent("large.txt")
        let largeData = Data(count: 1024 * 1024)  // 1MB of zeros

        let stream = try ByteStream(forWriting: fileURL)
        try await stream.write(largeData)
        await stream.close()

        let readData = try Data(contentsOf: fileURL)
        XCTAssertEqual(readData.count, largeData.count)
    }

    func testAppendToFile() async throws {
        let fileURL = tempDirectory.appendingPathComponent("append.txt")
        let initialData = "Hello, ".data(using: .utf8)!
        let appendData = "World!".data(using: .utf8)!

        // Write initial data
        let initialStream = try ByteStream(forWriting: fileURL)
        try await initialStream.write(initialData)
        await initialStream.close()

        // Append data
        let appendStream = try ByteStream(forWriting: fileURL, append: true)
        try await appendStream.write(appendData)
        await appendStream.close()

        // Read complete data
        let readStream = try ByteStream(forReading: fileURL)
        let readData = try await readStream.readToEnd()

        XCTAssertEqual(readData, initialData + appendData)
    }

    func testCloseStreamMultipleTimes() async throws {
        let fileURL = tempDirectory.appendingPathComponent("test.txt")
        let stream = try ByteStream(forWriting: fileURL)

        // Should not throw when closing multiple times
        await stream.close()
        await stream.close()
        await stream.close()

        // If we get here, no error was thrown
        XCTAssertTrue(true)
    }
}
