import SwiftUI

struct RenderQueueView: View {
    @Bindable var queueManager = RenderQueueManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Render Queue")
                    .font(.headline)
                Spacer()
                Button("Clear Completed") {
                    queueManager.clearCompleted()
                }
                .disabled(!queueManager.jobs.contains(where: { $0.status == .completed }))
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if queueManager.jobs.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Queue is empty")
                        .foregroundColor(.secondary)
                        .padding(.top, 5)
                    Spacer()
                }
                .frame(minHeight: 200)
            } else {
                List {
                    ForEach(queueManager.jobs) { job in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(job.albumTitle)
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                statusLabel(for: job.status)
                            }
                            
                            Text(job.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            if job.status == .rendering {
                                ProgressView(value: job.progress)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(minHeight: 200)
            }
        }
        .frame(width: 350, height: 400)
    }
    
    @ViewBuilder
    private func statusLabel(for status: RenderJobStatus) -> some View {
        switch status {
        case .queued:
            Label("Queued", systemImage: "clock")
                .foregroundColor(.secondary)
        case .rendering:
            Label("Rendering", systemImage: "gearshape.2.fill")
                .foregroundColor(.accentColor)
        case .completed:
            Label("Done", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed(let err):
            Label("Failed", systemImage: "xmark.circle.fill")
                .foregroundColor(.red)
                .help(err)
        }
    }
}
