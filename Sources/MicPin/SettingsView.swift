import SwiftUI
import MicPinCore

struct SettingsView: View {
    let controller: PinController
    @State private var loginEnabled = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Microphones")
                .font(.headline)

            List {
                ForEach(controller.devices) { device in
                    row(for: device)
                }
                if let pinned = controller.pinnedUID,
                   !controller.devices.contains(where: { $0.uid == pinned }) {
                    HStack {
                        Text("\(controller.pinnedName ?? pinned) — disconnected")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Unpin") { controller.unpin() }
                    }
                }
            }

            Toggle("Start at Login", isOn: loginBinding)

            HStack {
                Spacer()
                Text("MicPin \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 400, height: 440)
        .onAppear { loginEnabled = LoginItem.isEnabled }
    }

    @ViewBuilder
    private func row(for device: AudioDevice) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                Text(device.transport.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if device.uid == controller.activeUID {
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
                    .help("Currently active input")
            }
            if device.uid == controller.pinnedUID {
                Button("Unpin") { controller.unpin() }
            } else {
                Button("Pin") { controller.pin(uid: device.uid) }
            }
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { loginEnabled },
            set: { newValue in
                LoginItem.setEnabled(newValue)
                loginEnabled = LoginItem.isEnabled   // re-query actual status
            }
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
