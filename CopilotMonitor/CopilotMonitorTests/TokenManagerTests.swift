import XCTest
@testable import OpenCode_Bar

final class TokenManagerTests: XCTestCase {

    func testReadClaudeAnthropicAuthFilesParsesEnabledAccounts() throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let accountsPath = tempDirectory.appendingPathComponent("accounts.json")

        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let json = """
        {
          "version": 1,
          "accounts": [
            {
              "id": "account-primary",
              "type": "oauth",
              "refresh": "refresh-1",
              "access": "access-1",
              "expires": 1770563557150,
              "label": "Primary",
              "enabled": true
            },
            {
              "id": "account-disabled",
              "type": "oauth",
              "refresh": "refresh-2",
              "access": "access-2",
              "expires": 1770563557150,
              "label": "Disabled",
              "enabled": false
            }
          ],
          "activeAccountID": "account-primary",
          "updatedAt": 1770563557150
        }
        """

        try XCTUnwrap(json.data(using: .utf8)).write(to: accountsPath)

        let accounts = TokenManager.shared.readClaudeAnthropicAuthFiles(at: [accountsPath])

        XCTAssertEqual(accounts.count, 1)

        let account = try XCTUnwrap(accounts.first)
        XCTAssertEqual(account.accessToken, "access-1")
        XCTAssertEqual(account.accountId, "account-primary")
        XCTAssertEqual(account.refreshToken, "refresh-1")
        XCTAssertEqual(account.authSource, accountsPath.path)
        XCTAssertEqual(account.source, .opencodeAuth)
        XCTAssertEqual(account.sourceLabels, ["OpenCode"])

        let expiresAt = try XCTUnwrap(account.expiresAt)
        XCTAssertEqual(expiresAt.timeIntervalSince1970, 1_770_563_557.15, accuracy: 0.01)
    }
}
