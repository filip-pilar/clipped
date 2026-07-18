import SwiftUI

struct TimecodeField: View {
    let value: Int
    let fieldKey: String
    let accessibilityIdentifier: String
    let onCommit: (Int) -> Bool
    let onValidityChange: (Bool) -> Void

    @State private var text: String
    @State private var isValid = true
    @FocusState private var isFocused: Bool

    init(
        value: Int,
        fieldKey: String,
        accessibilityIdentifier: String,
        onCommit: @escaping (Int) -> Bool,
        onValidityChange: @escaping (Bool) -> Void
    ) {
        self.value = value
        self.fieldKey = fieldKey
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onCommit = onCommit
        self.onValidityChange = onValidityChange
        _text = State(initialValue: Timecode.display(value))
    }

    var body: some View {
        TextField("00:00:00", text: $text)
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.center)
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .frame(width: 104, height: 30)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isValid ? Color.secondary.opacity(0.25) : Color.red, lineWidth: isValid ? 1 : 1.5)
            }
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    if isValid { commit() }
                    else { revert() }
                }
            }
            .onChange(of: value) { _, newValue in
                if !isFocused {
                    text = Timecode.display(newValue)
                    setValidity(true)
                }
            }
            .onChange(of: text) { _, newText in
                guard isFocused else { return }
                setValidity((try? Timecode.parse(newText)) != nil)
            }
            .onKeyPress(.escape) {
                revert()
                isFocused = false
                return .handled
            }
            .accessibilityIdentifier(accessibilityIdentifier)
            .help(isValid ? "Seconds, MM:SS, or HH:MM:SS" : "Use seconds, MM:SS, or HH:MM:SS")
    }

    private func commit() {
        do {
            let seconds = try Timecode.parse(text)
            guard onCommit(seconds) else {
                setValidity(false)
                return
            }
            text = Timecode.display(seconds)
            setValidity(true)
        } catch {
            setValidity(false)
        }
    }

    private func revert() {
        text = Timecode.display(value)
        setValidity(true)
    }

    private func setValidity(_ valid: Bool) {
        guard isValid != valid else { return }
        isValid = valid
        onValidityChange(valid)
    }
}
