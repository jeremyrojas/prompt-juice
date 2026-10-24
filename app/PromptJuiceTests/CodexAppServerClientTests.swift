import Darwin
import Foundation
import XCTest
@testable import PromptJuice

final class CodexAppServerClientTests: XCTestCase {
    func testTimeoutEscalatesForChildIgnoringTermination() throws {
        try withScript("trap '' TERM\nprintf '%s' $$ > \"$PID_FILE\"\nwhile :; do :; done\n") { url, pidFile in
            let start = Date()
            XCTAssertThrowsError(try client(url, pidFile, timeout: 0.15).readRateLimits()) {
                guard case .timeout = $0 as? CodexAppServerClientError else {
                    return XCTFail("Expected timeout, got \($0)")
                }
            }
            XCTAssertLessThan(Date().timeIntervalSince(start), 2)
            let pid = try childPID(pidFile)
            XCTAssertEqual(kill(pid, 0), -1)
            XCTAssertEqual(errno, ESRCH)
        }
    }

    func testStdoutAndStderrLimitsStopFloodingChildren() throws {
        for redirect in ["", " >&2"] {
            try withScript("printf '%s' $$ > \"$PID_FILE\"\nwhile :; do printf '%01024d' 0\(redirect); done\n") { url, pidFile in
                let start = Date()
                XCTAssertThrowsError(try client(url, pidFile, timeout: 5).readRateLimits()) {
                    XCTAssertEqual($0 as? CodexAppServerClientError, .outputTooLarge)
                }
                XCTAssertLessThan(Date().timeIntervalSince(start), 3)
                XCTAssertEqual(kill(try childPID(pidFile), 0), -1)
            }
        }
    }

    func testCancellationStopsAnActiveRead() async throws {
        try await withAsyncScript("trap '' TERM\nprintf '%s' $$ > \"$PID_FILE\"\nwhile :; do :; done\n") { url, pidFile in
            let reader = client(url, pidFile, timeout: 30)
            let task = Task.detached { try reader.readRateLimits() }
            let deadline = Date().addingTimeInterval(2)
            while !FileManager.default.fileExists(atPath: pidFile.path), Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let pid = try childPID(pidFile)
            task.cancel()
            let start = Date()
            do {
                _ = try await task.value
                XCTFail("Expected cancellation")
            } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertLessThan(Date().timeIntervalSince(start), 2)
            XCTAssertEqual(kill(pid, 0), -1)
        }
    }

    func testProtocolErrorStillCleansUpChild() throws {
        try withScript("""
        printf '%s' $$ > "$PID_FILE"
        read -r initialize
        printf '%s\\n' '{"id":1,"result":{}}'
        read -r initialized
        read -r request
        printf '%s\\n' '{"id":2,"error":{"message":"synthetic server error"}}'
        while :; do :; done
        """
        ) { url, pidFile in
            XCTAssertThrowsError(try client(url, pidFile, timeout: 1).readRateLimits()) {
                XCTAssertEqual($0 as? CodexAppServerClientError, .serverError("synthetic server error"))
            }
            XCTAssertEqual(kill(try childPID(pidFile), 0), -1)
        }
    }

    private func client(_ url: URL, _ pidFile: URL, timeout: TimeInterval) -> CodexAppServerClient {
        CodexAppServerClient(executableURL: url, timeout: timeout,
                             environment: ["PATH": "/usr/bin:/bin", "PID_FILE": pidFile.path])
    }

    private func childPID(_ file: URL) throws -> pid_t {
        let text = try String(contentsOf: file, encoding: .utf8)
        return try XCTUnwrap(pid_t(text))
    }

    private func withScript(_ body: String, operation: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("synthetic-codex")
        try ("#!/bin/sh\n" + body).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        try operation(script, root.appendingPathComponent("pid"))
    }

    private func withAsyncScript(_ body: String, operation: (URL, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("synthetic-codex")
        try ("#!/bin/sh\n" + body).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        try await operation(script, root.appendingPathComponent("pid"))
    }
}
