import SwiftUI

/// 性能：处理器大卡 + 温度 + 内存
struct PerformancePage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        PageScaffold(page: .performance) { size in
            let gap: CGFloat = 14
            let availH = max(size.height - 46 - gap, 320)
            let leftW = min(max(size.width * 0.46, 340), 640)

            HStack(spacing: gap) {
                PerfCpuCard(cpu: model.snapshot.cpu, history: model.cpuHistory)
                    .frame(width: leftW)
                    .frame(maxHeight: .infinity)

                VStack(spacing: gap) {
                    PerfTempCard(temp: model.snapshot.temp, history: model.tempHistory)
                        .frame(height: availH * 0.48)
                    PerfMemCard(mem: model.snapshot.mem, history: model.memHistory)
                }
            }
            .frame(height: availH)
        }
    }
}
