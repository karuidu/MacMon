import SwiftUI

/// 存储网络：网络吞吐 + 磁盘容量 + 电池
struct StoragePage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        PageScaffold(page: .storage) {
            HStack(spacing: 12) {
                Text(model.snapshot.net.iface)
                    .font(.system(size: TS.caption, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text("↓ \(Fmt.rate(model.snapshot.net.rxSec))  ↑ \(Fmt.rate(model.snapshot.net.txSec))")
                    .font(.system(size: TS.caption, design: .monospaced))
                    .foregroundStyle(Theme.dim)
            }
        } content: { size in
            let gap: CGFloat = 14
            let availH = max(size.height - 46 - gap, 320)
            let leftW = min(max(size.width * 0.56, 380), 880)

            HStack(spacing: gap) {
                NetPanel(
                    net: model.snapshot.net,
                    rxHistory: model.netRxHistory,
                    txHistory: model.netTxHistory
                )
                .frame(width: leftW)
                .frame(maxHeight: .infinity)

                VStack(spacing: gap) {
                    DiskPanel(disk: model.snapshot.disk)
                        .frame(height: availH * 0.5)
                    BatteryPanel(battery: model.snapshot.battery)
                }
            }
            .frame(height: availH)
        }
    }
}
