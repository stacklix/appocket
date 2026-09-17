import SwiftUI

@main struct AppocketApp: App {
    @StateObject private var store = ModuleStore()
    var body: some Scene { WindowGroup { HomeView(store: store) } }
}
struct HomeView: View {
    @ObservedObject var store: ModuleStore
    @State private var didCheck = false
    @State private var showingSettings = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("YOUR LANGUAGE POCKET").font(.caption2.weight(.semibold)).tracking(3).foregroundStyle(.secondary)
                        Text("一点好奇，\n每天一点进步。").font(.system(size: 34, weight: .semibold, design: .serif))
                        Text("从一句话开始，找到适合你的学习方式。").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top, 20)
                    HStack { Text("我的学习工具").font(.headline); Spacer(); if store.checking { ProgressView(); Text("正在检查更新").font(.caption).foregroundStyle(.secondary) } }
                    ForEach(store.modules) { module in
                        NavigationLink { ModuleScreen(module: module, store: store) } label: {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack(spacing: 15) {
                                    Text(String(module.name.prefix(1))).font(.system(size: 34, weight: .medium, design: .serif)).frame(width: 60, height: 64).background(Color(red: 0.20, green: 0.32, blue: 0.25)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                                    VStack(alignment: .leading, spacing: 4) { Text(module.name).font(.title2.weight(.semibold)); Text("语言学习 · v\(module.version)").font(.caption).foregroundStyle(.secondary) }
                                    Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                                }
                                Text(module.description ?? "独立学习子应用").font(.subheadline).foregroundStyle(.secondary)
                                Divider()
                                Label(store.statuses[module.id] ?? "已内置 · 离线可打开", systemImage: store.blocked.contains(module.id) ? "exclamationmark.circle" : "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                            }.padding(22).background(.white.opacity(0.8)).clipShape(RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(.plain).disabled(store.checking || !didCheck || store.blocked.contains(module.id))
                    }
                    if !store.notice.isEmpty { Text(store.notice).font(.caption).foregroundStyle(.secondary) }
                    Button { Task { await store.checkForUpdates() } } label: { Label("检查子应用更新", systemImage: "arrow.clockwise") }.disabled(store.checking)
                    Text("无需账号 · 学习记录保存在本机").font(.caption2).foregroundStyle(.secondary).padding(.top, 25)
                }.padding(24)
            }.background(Color(red: 0.96, green: 0.95, blue: 0.93)).navigationTitle("Lingrove")
            .toolbar { Button { showingSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("应用设置") }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    Form {
                        Section("更新服务") { Text(HostConfiguration.bundled.catalogURL.isEmpty ? "未配置更新地址，请在 HostConfig.json 中配置后构建。" : HostConfiguration.bundled.catalogURL).font(.footnote) }
                        Section("网络授权") { Text("子应用默认可访问发布清单内的域名。自定义服务商首次连接时需要确认。撤销后，再次连接需重新授权。").font(.footnote); Button("撤销自定义域名授权", role: .destructive) { for module in store.modules { UserDefaults.standard.removeObject(forKey: "origins.\(module.id)") } } }
                        Section("关于") { Text("Lingrove 1.0.0"); Text("Vue 学习工具 · Swift 原生宿主") }
                    }.navigationTitle("设置").toolbar { Button("完成") { showingSettings = false } }
                }
            }
            .task { guard !didCheck else { return }; await store.checkForUpdates(); didCheck = true }
        }.tint(Color(red: 0.20, green: 0.32, blue: 0.25))
    }
}
