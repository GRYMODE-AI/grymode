import XCTest

@testable import Grymode

final class APIErrorMapperTests: XCTestCase {
    func testDecodesBackendErrorContract() {
        let body = Data(
            #"{"code":"quota_exceeded","message":"Try again later.","request_id":"srv-1","retryable":true}"#.utf8
        )

        let error = APIErrorMapper.map(status: 429, data: body, headerRequestID: "hdr-1")

        XCTAssertEqual(
            error,
            .api(status: 429, code: "quota_exceeded", message: "Try again later.", requestID: "srv-1", retryable: true)
        )
    }

    func testUnauthorizedPrefersBodyRequestIDThenHeader() {
        let body = Data(#"{"code":"auth","message":"x","request_id":"srv-2","retryable":false}"#.utf8)
        XCTAssertEqual(
            APIErrorMapper.map(status: 401, data: body, headerRequestID: "hdr"), .unauthorized(requestID: "srv-2"))
        XCTAssertEqual(
            APIErrorMapper.map(status: 401, data: Data(), headerRequestID: "hdr"), .unauthorized(requestID: "hdr"))
    }

    func testNonContractBodiesFallBackToGenericErrors() {
        let html = Data("<html>Bad gateway</html>".utf8)

        let transient = APIErrorMapper.map(status: 502, data: html, headerRequestID: "hdr")
        XCTAssertEqual(transient.apiCode, "http_502")
        XCTAssertTrue(transient.isRetryable)
        XCTAssertEqual(transient.requestID, "hdr")

        let permanent = APIErrorMapper.map(status: 404, data: html, headerRequestID: nil)
        XCTAssertEqual(permanent.apiCode, "http_404")
        XCTAssertFalse(permanent.isRetryable)

        XCTAssertTrue(APIErrorMapper.map(status: 408, data: Data(), headerRequestID: nil).isRetryable)
        XCTAssertTrue(APIErrorMapper.map(status: 429, data: Data(), headerRequestID: nil).isRetryable)
    }

    func testMapsTransportErrors() {
        XCTAssertEqual(APIErrorMapper.map(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(APIErrorMapper.map(URLError(.cannotConnectToHost)), .offline)
        XCTAssertEqual(APIErrorMapper.map(URLError(.timedOut)), .timedOut)
        XCTAssertEqual(APIErrorMapper.map(URLError(.cancelled)), .cancelled)
        XCTAssertEqual(APIErrorMapper.map(URLError(.badURL)), .unexpected)
        XCTAssertEqual(APIErrorMapper.map(CancellationError()), .cancelled)
        XCTAssertEqual(APIErrorMapper.map(AppError.decoding), .decoding)
    }

    func testUserFacingMessagesNeverExposeInternals() {
        let errors: [AppError] = [
            .offline, .timedOut, .unauthorized(requestID: "r"), .invalidResponse, .decoding, .unexpected,
        ]
        for error in errors {
            XCTAssertFalse(error.title.isEmpty)
            XCTAssertFalse(error.userMessage.isEmpty)
            XCTAssertFalse(error.userMessage.contains("http_"))
        }
    }
}
