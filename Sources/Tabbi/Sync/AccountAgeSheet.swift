import SwiftUI
import TabbiKitCore

/// The age check before Sign in with Apple (`PartyAgeCheck`), asked the way
/// Party asks it: the month and year the user was born, both blank so no
/// answer is suggested, beside the Terms and Privacy Policy. Old enough, it
/// offers Apple's button (`signInButton`); under 13, it says when signing
/// in opens, with no way to answer again.
struct AccountAgeSheet<SignInButton: View>: View {
    let status: PartyAgeCheck.Status
    let answer: (PartyAgeCheck.Birth) -> Void
    let close: () -> Void
    @ViewBuilder let signInButton: () -> SignInButton
    @State private var birthMonth = 0
    @State private var birthYear = 0

    private var birth: PartyAgeCheck.Birth? {
        birthMonth == 0 || birthYear == 0 ? nil : PartyAgeCheck.Birth(month: birthMonth, year: birthYear)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sign in with Apple", bundle: .tabbi)
                    .font(.title3.weight(.semibold))
                Text("Sync your pet, points and streaks across your Macs.", bundle: .tabbi)
                    .foregroundStyle(.secondary)
            }
            switch status {
            case .unanswered: question
            case .tooYoung(let until): tooYoung(until: until)
            case .passed: ready
            }
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.spring(duration: 0.3), value: status)
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(PartySetup.birthLabel)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    Picker(String(localized: "Month", bundle: .tabbi), selection: $birthMonth) {
                        Text("Month", bundle: .tabbi).tag(0)
                        ForEach(Array(PartyAgeCheck.monthNames().enumerated()), id: \.offset) { index, month in
                            Text(month).tag(index + 1)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    .help(String(localized: "The month you were born", bundle: .tabbi))
                    Picker(String(localized: "Year", bundle: .tabbi), selection: $birthYear) {
                        Text("Year", bundle: .tabbi).tag(0)
                        ForEach(PartyAgeCheck.birthYears(at: Date()), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                    .help(String(localized: "The year you were born", bundle: .tabbi))
                }
                Text(PartySetup.birthNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Spacer(minLength: 8)
                Button(String(localized: "Cancel", bundle: .tabbi), action: close)
                    .keyboardShortcut(.cancelAction)
                    .help(String(localized: "Close this. You can sign in any time.", bundle: .tabbi))
                Button(String(localized: "Continue", bundle: .tabbi)) {
                    if let birth { answer(birth) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(birth == nil)
                .help(birth == nil ? String(localized: "Pick the month and year you were born", bundle: .tabbi)
                      : String(localized: "Continue to Sign in with Apple", bundle: .tabbi))
            }
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                signInButton()
                    .frame(width: 200, height: 32)
                    .help(String(localized: "Sign in with your Apple Account to sync your pet across your Macs", bundle: .tabbi))
                Text(LocalizedStringKey(AccountAgeText.agreement))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "Opens on tabbinotch.com", bundle: .tabbi))
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: .tabbi), action: close)
                    .keyboardShortcut(.cancelAction)
                    .help(String(localized: "Close this. You can sign in any time.", bundle: .tabbi))
            }
        }
    }

    private func tooYoung(until date: Date) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(AccountAgeText.tooYoung(until: date), systemImage: "hand.raised")
                .font(.callout)
            HStack {
                Spacer()
                Button(String(localized: "Close", bundle: .tabbi), action: close)
                    .keyboardShortcut(.defaultAction)
                    .help(String(localized: "Close this", bundle: .tabbi))
            }
        }
    }
}

/// What the account says about the age check, in the row and the sheet.
enum AccountAgeText {
    /// The links the user agrees to by signing in, as Markdown.
    static var agreement: String {
        String(localized: "By signing in you agree to the [Terms of Use](\(SupportContact.termsURL.absoluteString)) and the [Privacy Policy](\(SupportContact.privacyURL.absoluteString)).", bundle: .tabbi)
    }

    /// What the account row and this sheet say to someone too young.
    static func tooYoung(until date: Date) -> String {
        String(localized: "Accounts are for people \(PartyAgeCheck.minimumAge) and older. Signing in opens in \(PartyAgeCheck.opensText(date)).", bundle: .tabbi)
    }
}
