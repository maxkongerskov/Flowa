// AcknowledgementsView.swift
// Flowa
//
// Third-party licence sheet (data-driven MIT entries).

import SwiftUI

struct AcknowledgementsView: View {
    @Binding var isPresented: Bool

    private static let entries: [(name: String, copyright: String)] = [
        ("Whisper / OpenAI", "Copyright © 2022 OpenAI"),
        ("WhisperKit / Argmax", "Copyright © 2023 Argmax, Inc."),
    ]

    private static let mitBody = """
    MIT License

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Acknowledgements")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.accent)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(Self.entries.enumerated()), id: \.offset) { i, entry in
                        if i > 0 { Divider() }
                        Text(entry.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("\(Self.mitBody.replacingOccurrences(of: "MIT License\n\n", with: "MIT License\n\n\(entry.copyright)\n\n"))")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 480, height: 500)
        .background(Theme.pageBackground)
    }
}
