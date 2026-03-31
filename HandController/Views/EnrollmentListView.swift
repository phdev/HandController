import SwiftUI

/// Lists enrolled wake words and provides entry point for new enrollments.
struct EnrollmentListView: View {
    let client: HomeCenterClient
    @Environment(\.dismiss) private var dismiss

    @State private var enrollments: [HomeCenterClient.Enrollment] = []
    @State private var isLoading = false
    @State private var showAddFlow = false
    @State private var deleteTarget: HomeCenterClient.Enrollment?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && enrollments.isEmpty {
                    ProgressView("Loading...")
                } else if enrollments.isEmpty {
                    emptyState
                } else {
                    enrollmentList
                }
            }
            .navigationTitle("Wake Word Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showAddFlow = true
                    } label: {
                        Label("Add Wake Word", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showAddFlow) {
                EnrollmentFlowView(client: client)
            }
            .onChange(of: showAddFlow) { _, showing in
                if !showing { fetchEnrollments() }
            }
            .onAppear { fetchEnrollments() }
            .alert("Delete Wake Word?", isPresented: .init(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let target = deleteTarget {
                        deleteEnrollment(target)
                    }
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                if let target = deleteTarget {
                    Text("This will remove \"\(target.name)\" and their wake word enrollment.")
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Wake Words Enrolled")
                .font(.headline)
            Text("Add a wake word so family members can navigate the dashboard by voice.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Enrollment List

    private var enrollmentList: some View {
        List {
            ForEach(enrollments) { enrollment in
                enrollmentRow(enrollment)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteTarget = enrollment
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func enrollmentRow(_ enrollment: HomeCenterClient.Enrollment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(enrollment.name)
                    .font(.headline)
                Spacer()
                Text(enrollment.target)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.15), in: Capsule())
            }

            HStack(spacing: 12) {
                if !enrollment.wakePhrase.isEmpty {
                    Label("\"\(enrollment.wakePhrase)\"", systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label("\(enrollment.nTemplates) templates", systemImage: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if enrollment.sampleDuration > 0 {
                    Label(String(format: "%.1fs", enrollment.sampleDuration), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func fetchEnrollments() {
        isLoading = true
        Task {
            if let list = await client.getEnrollments() {
                await MainActor.run {
                    enrollments = list
                    isLoading = false
                }
            } else {
                await MainActor.run { isLoading = false }
            }
        }
    }

    private func deleteEnrollment(_ enrollment: HomeCenterClient.Enrollment) {
        Task {
            if await client.deleteEnrollment(name: enrollment.name) {
                await MainActor.run {
                    enrollments.removeAll { $0.id == enrollment.id }
                }
            }
            deleteTarget = nil
        }
    }
}
