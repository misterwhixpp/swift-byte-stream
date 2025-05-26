import Foundation

/// A protocol for readable streams.
public protocol ReadableStream: Sendable {
  /// Reads data from the stream.
  /// - Returns: The data read from the stream, or nil if the end of the stream was reached.
  /// - Throws: An error if the read operation fails.
  func read() async throws -> Data?
}

/// A protocol for writable streams.
public protocol WritableStream: Sendable {
  /// Writes data to the stream.
  /// - Parameter data: The data to write.
  /// - Throws: An error if the write operation fails.
  func write(_ data: Data) async throws
}

/// A generic stream type that wraps Foundation's InputStream and OutputStream
public actor ByteStream: ReadableStream, WritableStream {
  public static let defaultBufferSize = 4096

  private let inputStream: AsyncInputStream?
  private let outputStream: AsyncOutputStream?
  private let bufferSize: Int
  private var isManaged: Bool

  /// Creates a new ByteStream with the specified streams
  /// - Parameters:
  ///   - inputStream: The input stream to read from
  ///   - outputStream: The output stream to write to
  ///   - bufferSize: The size of the buffer to use for reading/writing operations
  public init(
    inputStream: AsyncInputStream? = nil,
    outputStream: AsyncOutputStream? = nil,
    bufferSize: Int = defaultBufferSize
  ) {
    self.inputStream = inputStream
    self.outputStream = outputStream
    self.bufferSize = bufferSize
    self.isManaged = false
  }

  /// Creates a new ByteStream for reading from a file
  /// - Parameters:
  ///   - fileURL: The URL of the file to read from
  ///   - bufferSize: The size of the buffer to use for reading operations
  /// - Throws: An error if the file cannot be opened for reading
  public init(forReading fileURL: URL, bufferSize: Int = defaultBufferSize) throws {
    guard let stream = InputStream(url: fileURL) else {
      throw StreamError.streamNotAvailable
    }
    self.inputStream = AsyncInputStream(stream, bufferSize: bufferSize)
    self.outputStream = nil
    self.bufferSize = bufferSize
    self.isManaged = true
  }

  /// Creates a new ByteStream for writing to a file
  /// - Parameters:
  ///   - fileURL: The URL of the file to write to
  ///   - append: Whether to append to the file or overwrite it
  ///   - bufferSize: The size of the buffer to use for writing operations
  /// - Throws: An error if the file cannot be opened for writing
  public init(
    forWriting fileURL: URL,
    append: Bool = false,
    bufferSize: Int = defaultBufferSize
  ) throws {
    guard let stream = OutputStream(url: fileURL, append: append) else {
      throw StreamError.streamNotAvailable
    }
    self.inputStream = nil
    self.outputStream = AsyncOutputStream(stream)
    self.bufferSize = bufferSize
    self.isManaged = true
  }

  /// Creates a new ByteStream for both reading from and writing to a file
  /// - Parameters:
  ///   - fileURL: The URL of the file to read from and write to
  ///   - append: Whether to append to the file or overwrite it
  ///   - bufferSize: The size of the buffer to use for reading/writing operations
  /// - Throws: An error if the file cannot be opened for reading or writing
  public init(
    forReadingAndWriting fileURL: URL,
    append: Bool = false,
    bufferSize: Int = defaultBufferSize
  ) throws {
    guard
      let inputStream = InputStream(url: fileURL),
      let outputStream = OutputStream(url: fileURL, append: append)
    else {
      throw StreamError.streamNotAvailable
    }
    self.inputStream = AsyncInputStream(inputStream, bufferSize: bufferSize)
    self.outputStream = AsyncOutputStream(outputStream)
    self.bufferSize = bufferSize
    self.isManaged = true
  }

  /// Reads data from the input stream
  /// - Returns: The data read from the stream, or nil if the end of the stream was reached
  /// - Throws: An error if the read operation fails
  public func read() async throws -> Data? {
    guard let inputStream else {
      throw StreamError.streamNotAvailable
    }

    return try await inputStream.read()
  }

  /// Reads all data from the input stream until the end is reached
  /// - Returns: All data read from the stream
  /// - Throws: An error if the read operation fails
  public func readToEnd() async throws -> Data {
    var result = Data()

    while let chunk = try await read() {
      result.append(chunk)
    }

    return result
  }

  /// Writes data to the output stream
  /// - Parameter data: The data to write
  /// - Throws: An error if the write operation fails
  public func write(_ data: Data) async throws {
    guard let outputStream = outputStream else {
      throw StreamError.streamNotAvailable
    }

    try await outputStream.write(data)
  }

  /// Closes both input and output streams
  public func close() {
    inputStream?.close()
    outputStream?.close()
  }
}

/// Errors that can occur during stream operations
public enum StreamError: Error {
  case streamNotAvailable
  case readError(Error?)
  case writeError(Error?)
  case incompleteWrite
}

extension StreamError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .streamNotAvailable:
      return "Stream is not available"
    case .readError(let error):
      return "Read error: \(error?.localizedDescription ?? "Unknown error")"
    case .writeError(let error):
      return "Write error: \(error?.localizedDescription ?? "Unknown error")"
    case .incompleteWrite:
      return "Incomplete write operation"
    }
  }
}

public final class AsyncInputStream: ReadableStream, AsyncSequence, AsyncIteratorProtocol {
  public typealias Element = Data

  nonisolated(unsafe) let inputStream: InputStream
  let bufferSize: Int

  public init(_ inputStream: InputStream, bufferSize: Int) {
    self.inputStream = inputStream
    self.bufferSize = bufferSize
  }

  public func read() async throws -> Data? {
    if inputStream.streamStatus == .closed {
      // TODO: should we throw an error here?
      return nil
    }

    if inputStream.streamStatus == .notOpen {
      inputStream.open()
    }

    return try await withCheckedThrowingContinuation { continuation in
      let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
      defer { buffer.deallocate() }

      let bytesRead = inputStream.read(buffer, maxLength: bufferSize)

      if bytesRead < 0 {
        inputStream.close()
        continuation.resume(throwing: StreamError.readError(inputStream.streamError))
        return
      }

      if bytesRead == 0 {
        inputStream.close()
        continuation.resume(returning: nil)
        return
      }

      let data = Data(bytes: buffer, count: bytesRead)
      continuation.resume(returning: data)
    }
  }

  public func makeAsyncIterator() -> AsyncInputStream {
    self
  }

  public func next() async throws -> Data? {
    try await read()
  }

  public func close() {
    inputStream.close()
  }
}

public final class AsyncOutputStream: WritableStream {
  fileprivate nonisolated(unsafe) let stream: OutputStream

  public init(_ stream: OutputStream) {
    self.stream = stream
  }

  public func write(_ data: Data) async throws {
    if stream.streamStatus == .closed {
      // TODO: should we throw an error here?
      return
    }

    if stream.streamStatus == .notOpen {
      stream.open()
    }

    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      let bytesWritten = data.withUnsafeBytes { buffer in
        stream.write(
          buffer.bindMemory(to: UInt8.self).baseAddress!,
          maxLength: data.count
        )
      }

      if bytesWritten < 0 {
        continuation.resume(throwing: StreamError.writeError(stream.streamError))
        return
      }

      if bytesWritten != data.count {
        continuation.resume(throwing: StreamError.incompleteWrite)
        return
      }

      continuation.resume()
    }
  }

  public func close() {
    stream.close()
  }
}
