/*
 * Copyright 2018, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import Dispatch
import Foundation
@testable import JavaAuth
import SwiftGRPC
import XCTest

enum Security {
    case regular, none
}

class EchoProvider: Echo_EchoProvider {
	// get returns requests as they were received.
	func get(request: Echo_EchoRequest, session _: Echo_EchoGetSession) throws -> Echo_EchoResponse {
		var response = Echo_EchoResponse()
		response.text = "Swift echo get: " + request.text
		return response
	}
	
	// expand splits a request into words and returns each word in a separate message.
	func expand(request: Echo_EchoRequest, session: Echo_EchoExpandSession) throws -> ServerStatus? {
		let parts = request.text.components(separatedBy: " ")
		for (i, part) in parts.enumerated() {
			var response = Echo_EchoResponse()
			response.text = "Swift echo expand (\(i)): \(part)"
			try session.send(response) {
				if let error = $0 {
					print("expand error: \(error)")
				}
			}
		}
		return .ok
	}
	
	// collect collects a sequence of messages and returns them concatenated when the caller closes.
	func collect(session: Echo_EchoCollectSession) throws -> Echo_EchoResponse? {
		var parts: [String] = []
		while true {
			do {
				guard let request = try session.receive()
					else { break }  // End of stream
				parts.append(request.text)
			} catch {
				print("collect error: \(error)")
				break
			}
		}
		var response = Echo_EchoResponse()
		response.text = "Swift echo collect: " + parts.joined(separator: " ")
		return response
	}
	
	// update streams back messages as they are received in an input stream.
	func update(session: Echo_EchoUpdateSession) throws -> ServerStatus? {
		var count = 0
		while true {
			do {
				guard let request = try session.receive()
					else { break }  // End of stream
				var response = Echo_EchoResponse()
				response.text = "Swift echo update (\(count)): \(request.text)"
				count += 1
				try session.send(response) {
					if let error = $0 {
						print("update error: \(error)")
					}
				}
			} catch {
				print("update error: \(error)")
				break
			}
		}
		return .ok
	}
}

class BasicEchoTestCase: XCTestCase {
	func makeProvider() -> Echo_EchoProvider { return EchoProvider() }
	
	var provider: Echo_EchoProvider!
	var server: Echo_EchoServer!
	var client: Echo_EchoServiceClient!
	
	var defaultTimeout: TimeInterval { return 100.0 }
	var secure: Bool { return true }
	var address: String { return "localhost:5050" }

    override func setUp() {
		provider = makeProvider()
		
		if secure {
			//print("certChain", Certs.certChain)
			//print("privateKey", Certs.privateKey)
			server = Echo_EchoServer(address: address,
									 certificateString: Certs.certChain,
									 keyString: Certs.privateKey,
									 rootCerts: Certs.trustCertCollection,
									 provider: provider)
			server.start()
			//client = Echo_EchoServiceClient(address: address, certificates: certificateString, arguments: [.sslTargetNameOverride("example.com")])
			//client.host = "example.com"
		} else {
			server = Echo_EchoServer(address: address, provider: provider)
			server.start()
			client = Echo_EchoServiceClient(address: address, secure: false)
		}
		
		//client.timeout = defaultTimeout
		
        super.setUp()
    }

    func testRegularSSL() {
        let certificate = Certs.trustCertCollection
        client = Echo_EchoServiceClient(address: address, certificates: certificate, arguments: [.sslTargetNameOverride("example.com")])
        client.host = "example.com"
        client.timeout = defaultTimeout

        XCTAssertEqual("hi", try! client.get(Echo_EchoRequest(text: "hi")).text)
    }

    func testTLSMutualAuth() {
        let certificate = Certs.trustCertCollection
        let clientCertificate = Certs.clientCertChain
        let clientKey = Certs.clientPrivateKey
        client = Echo_EchoServiceClient(address: address, certificates: certificate, clientCertificates: clientCertificate, clientKey: clientKey)
        client.host = "example.com"
        client.timeout = defaultTimeout

        XCTAssertEqual("hi", try! client.get(Echo_EchoRequest(text: "hi")).text)
    }

    override func tearDown() {
        client = nil

        super.tearDown()
    }
}
