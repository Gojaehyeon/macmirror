import SwiftUI

struct ContentView: View {
    @StateObject private var stream = MirrorStream()
    @AppStorage("macmirror_host") private var host: String = ""
    @State private var showSettings = false
    @State private var showControls = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let img = stream.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    if host.trimmingCharacters(in: .whitespaces).isEmpty {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)
                        Text("탭해서 맥 주소 입력")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("macmirror 메뉴바 → 주소 복사")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ProgressView().scaleEffect(1.5).tint(.white)
                        Text(stream.status).font(.body).foregroundStyle(.secondary)
                        Text(host).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding()
                .onTapGesture { showSettings = true }
            }

            if showControls {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Circle()
                            .fill(stream.status == "연결됨" ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(stream.status == "연결됨" ? "\(stream.fps) fps" : stream.status)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gear").font(.body)
                        }
                        .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { revealControls() }
        .onAppear {
            if !host.trimmingCharacters(in: .whitespaces).isEmpty {
                stream.connect(to: host)
            }
        }
        .sheet(isPresented: $showSettings) {
            HostEditor(host: $host) {
                showSettings = false
                stream.connect(to: host)
            }
        }
    }

    private func revealControls() {
        withAnimation(.easeInOut(duration: 0.2)) { showControls = true }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.4)) { showControls = false }
                }
            }
        }
    }
}

struct HostEditor: View {
    @Binding var host: String
    var onConnect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("맥 주소") {
                    TextField("192.168.0.10:8890 또는 URL", text: $host)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Button {
                        onConnect()
                    } label: {
                        Label("연결", systemImage: "wifi")
                    }
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("힌트") {
                    Text("macmirror 메뉴바에서 '같은 WiFi 기기용 주소 복사' 누른 뒤 여기 붙여넣으세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("외부망이면 '공개 주소' 의 cloudflare URL 을 그대로 입력해도 됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("연결 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
