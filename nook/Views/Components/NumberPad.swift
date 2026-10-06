//
//  NumberPad.swift
//  Nook
//

import SwiftUI

/// Big on-screen digits. Sends "0"–"9", "clear" or "delete".
struct NumberPad: View {
    @Environment(KioskSettings.self) private var settings
    var keySize = CGSize(width: 110, height: 84)
    let onKey: (String) -> Void

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "clear", "0", "delete"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(keySize.width), spacing: 16), count: 3), spacing: 16) {
            ForEach(keys, id: \.self) { key in
                Button {
                    onKey(key)
                } label: {
                    Group {
                        switch key {
                        case "delete": Image(systemName: "delete.left.fill").font(.system(size: 28))
                        case "clear": Text("Clear").kFont(20, .semibold)
                        default: Text(key).kFont(34, .semibold, design: .rounded)
                        }
                    }
                    .frame(width: keySize.width, height: keySize.height)
                    .foregroundStyle(settings.ink)
                    .background(key.count == 1 ? settings.surface : .clear, in: .rect(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(settings.highContrast && key.count == 1 ? settings.ink : .clear, lineWidth: 2))
                }
                .buttonStyle(TileButtonStyle())
                .accessibilityLabel(key == "delete" ? "Delete" : key)
            }
        }
    }
}
