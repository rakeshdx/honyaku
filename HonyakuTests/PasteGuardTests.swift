import XCTest
@testable import Honyaku

final class PasteGuardTests: XCTestCase {
    private let front: pid_t = 100
    private let other: pid_t = 200

    private enum Subrole: CaseIterable { case secure, ordinary, unreadable }
    private enum Owner: CaseIterable { case off, frontApp, anotherApp, unknown }

    /// Every row of design Decision 1: subrole × secure-input owner × front-app category.
    func testDecisionTable() {
        for subrole in Subrole.allCases {
            for owner in Owner.allCases {
                for category in [AppCategory.terminal, .other] {
                    let focusedSubrole: String? = switch subrole {
                    case .secure: "AXSecureTextField"
                    case .ordinary: "AXTextArea"
                    case .unreadable: nil
                    }
                    let (on, ownerPID): (Bool, pid_t?) = switch owner {
                    case .off: (false, nil)
                    case .frontApp: (true, front)
                    case .anotherApp: (true, other)
                    case .unknown: (true, nil)
                    }
                    let expected: PasteGuardDecision
                    if subrole == .secure {
                        expected = .block
                    } else {
                        switch owner {
                        case .off: expected = .allow
                        case .frontApp: expected = category == .terminal ? .allow : .block
                        case .anotherApp: expected = .warn(ownerPID: other)
                        case .unknown: expected = .warn(ownerPID: nil)
                        }
                    }
                    let decision = PasteGuard.decide(focusedSubrole: focusedSubrole, secureInputOwnerPID: ownerPID,
                                                     secureInputOn: on, frontmostPID: front, frontmostCategory: category)
                    XCTAssertEqual(decision, expected, "\(subrole), \(owner), \(category)")
                }
            }
        }
    }

    func testOwnerReportedWithoutTheFlagStillCounts() {
        XCTAssertEqual(PasteGuard.decide(focusedSubrole: nil, secureInputOwnerPID: front, secureInputOn: false,
                                         frontmostPID: front, frontmostCategory: .other), .block)
    }

    func testNoFrontAppWarnsRatherThanBlocks() {
        XCTAssertEqual(PasteGuard.decide(focusedSubrole: nil, secureInputOwnerPID: other, secureInputOn: true,
                                         frontmostPID: nil, frontmostCategory: nil), .warn(ownerPID: other))
    }

    func testWarningNotice() {
        XCTAssertEqual(PasteGuard.warningNotice(ownerName: "1Password"), "Pasted. Note: 1Password has secure input on")
        XCTAssertEqual(PasteGuard.warningNotice(ownerName: nil), "Pasted. Note: another app has secure input on")
    }
}
