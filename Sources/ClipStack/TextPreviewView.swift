import SwiftUI
import ClipStackCore

struct TextPreviewView: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("文本预览").font(.headline)
                    Text("\(item.content.count) 字符")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(copied ? "已复制" : "复制全文") {
                    onCopy()
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            ScrollView(.vertical) {
                Text(item.content)
                    .font(.system(size: 14, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .frame(width: 640, height: 480)
    }
}
