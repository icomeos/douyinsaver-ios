import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: DownloadModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 标题
                VStack(alignment: .leading, spacing: 4) {
                    Text("无水印视频下载")
                        .font(.title2).bold()
                    Text("支持抖音 / B站 / TikTok · 保存到相册")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // 链接输入
                VStack(alignment: .leading, spacing: 8) {
                    Text("视频分享链接")
                        .font(.headline)
                    TextEditor(text: $model.input)
                        .frame(minHeight: 90)
                        .padding(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                        )
                    HStack {
                        Button {
                            model.pasteFromClipboard()
                        } label: {
                            Label("从剪贴板读取", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                }

                // 进度
                if model.isBusy {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Float(model.progress), total: 100)
                        Text("下载中… \(model.progress)%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 状态
                Text(model.status)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .textSelection(.enabled)

                // 操作按钮
                HStack(spacing: 12) {
                    Button {
                        model.startDownload()
                    } label: {
                        Label(model.isBusy ? "下载中…" : "下载并保存到相册",
                              systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)

                    if model.isBusy {
                        Button("取消") { model.cancel() }
                            .buttonStyle(.bordered)
                    }
                }

                // 使用说明
                VStack(alignment: .leading, spacing: 8) {
                    Text("使用方法")
                        .font(.headline)
                    Text("""
                    1. 在抖音 / B站 / TikTok 里点「分享 → 复制链接」
                    2. 回到本 App，点「从剪贴板读取」或直接粘贴到输入框
                    3. 点「下载并保存到相册」，等待完成

                    提示：TikTok 需要手机能打开 TikTok 的网络环境。
                    免费签名版本 7 天需重新签名一次。
                    """)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}
