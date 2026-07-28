import PixelDoneDesignFoundation
import PixelDoneDomain
import PixelDoneSyncContract
import SwiftUI

struct FoundationHandoffView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Label("MAIN", systemImage: "checklist")
                Label("TRASH", systemImage: "trash")
            }
            .navigationTitle("PixelDone")
        } detail: {
            VStack(alignment: .leading, spacing: PixelDoneDesignFoundation.baseGrid * 4) {
                Text("PixelDone")
                    .font(.largeTitle)
                Text("Apple foundation \(PixelDoneProductBaseline.androidVersion)")
                    .foregroundStyle(.secondary)
                Text("Read MAC_HANDOFF.md before continuing implementation.")
            }
            .padding()
        }
    }
}

struct FoundationSettingsView: View {
    var body: some View {
        Form {
            Text("Foundation configuration is documented in APP_SPEC.md.")
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 320)
    }
}
