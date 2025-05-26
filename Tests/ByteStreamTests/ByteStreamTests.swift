import Foundation
import Testing

@testable import ByteStream

final class ByteStreamTests {
    private var tempDirectory: URL!

    init() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    @Test("Read from file")
    func testReadFromFile() async throws {
        let testData = "Hello, World!".data(using: .utf8)!
        let fileURL = tempDirectory.appendingPathComponent("test.txt")
        try testData.write(to: fileURL)

        let stream = try ByteStream(forReading: fileURL)
        let readData = try await stream.readToEnd()

        #expect(readData == testData)
    }

    @Test("Write to file")
    func testWriteToFile() async throws {
        let testData = "Hello, World!".data(using: .utf8)!
        let fileURL = tempDirectory.appendingPathComponent("test.txt")

        let stream = try ByteStream(forWriting: fileURL)
        try await stream.write(testData)
        await stream.close()

        let readData = try Data(contentsOf: fileURL)
        #expect(readData == testData)
    }

    @Test("Read and write to same file")
    func testReadAndWriteToSameFile() async throws {
        let fileURL = tempDirectory.appendingPathComponent("test.txt")
        let testData = "Hello, World!".data(using: .utf8)!

        let stream = try ByteStream(forReadingAndWriting: fileURL)
        try await stream.write(testData)

        // Reset stream position to beginning
        await stream.close()
        let readStream = try ByteStream(forReading: fileURL)
        let readData = try await readStream.readToEnd()

        #expect(readData == testData)
    }

    @Test("Handle non-existent file")
    func testHandleNonExistentFile() async throws {
        let fileURL = tempDirectory.appendingPathComponent("nonexistent.txt")

        do {
            let stream = try ByteStream(forReading: fileURL)
            _ = try await stream.read()
            Issue.record("Expected error when reading non-existent file")
        } catch {
            #expect(error is StreamError)
        }
    }

    @Test("Read with custom buffer size")
    func testReadWithCustomBufferSize() async throws {
        let testData = "Hello, World!".data(using: .utf8)!
        let fileURL = tempDirectory.appendingPathComponent("test.txt")
        try testData.write(to: fileURL)

        let stream = try ByteStream(forReading: fileURL, bufferSize: 4)
        let readData = try await stream.readToEnd()

        #expect(readData == testData)
    }

    @Test("Write large data")
    func testWriteLargeData() async throws {
        let fileURL = tempDirectory.appendingPathComponent("large.txt")
        let largeData = Data(count: 1024 * 1024)  // 1MB of zeros

        let stream = try ByteStream(forWriting: fileURL)
        try await stream.write(largeData)
        await stream.close()

        let readData = try Data(contentsOf: fileURL)
        #expect(readData.count == largeData.count)
    }

    @Test("Append to file")
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

        #expect(readData == initialData + appendData)
    }

    @Test("Close stream multiple times")
    func testCloseStreamMultipleTimes() async throws {
        let fileURL = tempDirectory.appendingPathComponent("test.txt")
        let stream = try ByteStream(forWriting: fileURL)

        // Should not throw when closing multiple times
        await stream.close()
        await stream.close()
        await stream.close()
    }
}
