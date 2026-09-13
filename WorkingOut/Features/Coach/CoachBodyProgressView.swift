import SwiftUI
import SwiftData
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers

private enum CoachBodyEditor: Identifiable {
    case weight(WeightEntry?), waist(CoachWaistMeasurement?), photo(CoachProgressPhoto)
    var id: String {
        switch self {
        case let .weight(row): "weight:" + (row?.id.uuidString ?? "new")
        case let .waist(row): "waist:" + (row?.id.uuidString ?? "new")
        case let .photo(row): "photo:" + row.id.uuidString
        }
    }
}

struct CoachBodyProgressView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("coach.progress.range") private var rangeRaw = CoachProgressRange.month.rawValue
    @State private var weights: [WeightEntry] = []
    @State private var waists: [CoachWaistMeasurement] = []
    @State private var photos: [CoachProgressPhoto] = []
    @State private var editor: CoachBodyEditor?
    @State private var baselineID: UUID?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var comparisonIDs = Set<UUID>()
    @State private var photoDate = Date()
    @State private var photoPose = ""
    @State private var importing = false
    @State private var importTask: Task<Void, Never>?
    @State private var readingHealth = false
    @State private var status: String?
    @State private var error: String?
    private var repository: CoachRepository { CoachRepository(context: ModelContext(context.container)) }
    private var range: CoachProgressRange { CoachProgressRange(rawValue: rangeRaw) ?? .month }
    private func includes(_ date: Date) -> Bool { (range.start() == nil || date >= range.start()!) && date <= Date() }
    private var filteredWeights: [WeightEntry] { weights.filter { includes($0.date) } }
    private var filteredWaists: [CoachWaistMeasurement] { waists.filter { includes($0.observedAt) } }
    private var filteredPhotos: [CoachProgressPhoto] { photos.filter { includes($0.observedAt) } }
    private func kg(_ row: WeightEntry) -> Double? { CoachMeasurementUnits.kilograms(row.weight, unit: row.weightUnit) }
    private func cm(_ row: CoachWaistMeasurement) -> Double? { CoachMeasurementUnits.centimeters(row.value, unit: row.unit) }

    var body: some View {
        List {
            Section { CoachProgressRangePicker(selection: $rangeRaw) }
            if let error { Section { Text(error).foregroundStyle(.red); Button("Reload", action: load) } }
            if let status { Section { Text(status).foregroundStyle(.secondary).accessibilityIdentifier("coach.body.saved") } }
            weightSection
            waistSection
            photoSection
        }
        .navigationTitle("Body Progress")
        .task { load() }
        .sheet(item: $editor, onDismiss: load) { editor in
            switch editor {
            case let .weight(row): CoachMeasurementEditor(weight: row)
            case let .waist(row): CoachMeasurementEditor(waist: row)
            case let .photo(row): CoachPhotoMetadataEditor(photo: row)
            }
        }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            importTask = Task { await importPhotos(items) }
        }
        .onDisappear { importTask?.cancel() }
    }
    private var weightSection: some View {
        Section("Weight") {
            CoachValueChart(title: "Weight", unit: "kg", points: filteredWeights.compactMap { row in
                kg(row).map { .init(id: row.id.uuidString, date: row.date, value: $0, detail: "Original \(CoachEntryNumber.text(row.weight)) \(row.weightUnit)") }
            })
            if filteredWeights.contains(where: { kg($0) == nil }) { Text("Some observations have an unsupported unit or invalid value. They remain in the observation list for correction and are excluded from comparisons.").font(.caption).foregroundStyle(.secondary) }
            if let trend = weightTrend {
                Text("7-day trend: \(CoachEntryNumber.text(trend.value)) kg · \(trend.days) of 7 days measured.")
                Text("The latest observation on each civil day is its representative. The trend averages only those measured days in the seven-day window ending on the latest measurement.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Log Weight") { editor = .weight(nil) }.accessibilityIdentifier("coach.body.add_weight")
            Button {
                readingHealth = true
                Task {
                    defer { readingHealth = false }
                    do {
                        let count = try await repository.importHealthWeights(preferredUnit: "kg")
                        load(); status = "Health refresh added \(count) new observations and applied any source corrections or deletions. No readable samples means unavailable, not zero weight."
                    } catch { self.error = error.localizedDescription }
                }
            } label: { if readingHealth { ProgressView("Reading Health weight…") } else { Text("Refresh Weight from Apple Health") } }
                .disabled(readingHealth)
            Text("Coach and the Weight tab share these records. Display conversion does not rewrite stored units; several observations on one day remain separate.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Edit weight observations") {
                ForEach(filteredWeights) { row in
                    Button { editor = .weight(row) } label: {
                        LabeledContent(row.date.formatted(date: .abbreviated, time: .shortened), value: "\(CoachEntryNumber.text(row.weight)) \(row.weightUnit)")
                    }.accessibilityIdentifier("coach.body.weight.observation.\(row.id.uuidString)")
                }
            }
        }
    }
    private var weightTrend: (value: Double, days: Int)? {
        guard let latest = filteredWeights.first(where: { kg($0) != nil }),
              let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: latest.date)) else { return nil }
        let rows = weights.filter { $0.date >= start && $0.date <= latest.date && kg($0) != nil }
        let daily = Dictionary(grouping: rows) { CoachDate.civil($0.date) }.compactMap { _, rows in rows.max { $0.date < $1.date } }
        guard !daily.isEmpty else { return nil }
        return (daily.compactMap(kg).reduce(0, +) / Double(daily.count), daily.count)
    }
    private var waistSection: some View {
        Section("Waist") {
            CoachValueChart(title: "Waist", unit: "cm", points: filteredWaists.compactMap { row in
                cm(row).map { .init(id: row.id.uuidString, date: row.observedAt, value: $0, detail: "Original \(CoachEntryNumber.text(row.value)) \(row.unit)\(row.notes.map { " · " + $0 } ?? "")") }
            })
            if filteredWaists.contains(where: { cm($0) == nil }) { Text("Some waist observations need unit or value correction before comparison.").font(.caption).foregroundStyle(.secondary) }
            if !waists.isEmpty {
                Picker("Comparison baseline", selection: $baselineID) {
                    Text("Choose baseline").tag(Optional<UUID>.none)
                    ForEach(waists) { row in Text("\(row.civilDate) · \(CoachEntryNumber.text(row.value)) \(row.unit)").tag(Optional(row.id)) }
                }
                if let baseline = waists.first(where: { $0.id == baselineID }), let latest = filteredWaists.first,
                   let latestValue = cm(latest), let baselineValue = cm(baseline) {
                    let difference = latestValue - baselineValue
                    Text("Latest versus selected baseline: \(difference >= 0 ? "+" : "")\(CoachEntryNumber.text(difference)) cm")
                }
            }
            Button("Log Waist Measurement") { editor = .waist(nil) }.accessibilityIdentifier("coach.body.add_waist")
            DisclosureGroup("Edit waist observations") {
                ForEach(filteredWaists) { row in
                    Button { editor = .waist(row) } label: {
                        LabeledContent(row.observedAt.formatted(date: .abbreviated, time: .shortened), value: "\(CoachEntryNumber.text(row.value)) \(row.unit)")
                    }.accessibilityIdentifier("coach.body.waist.observation.\(row.id.uuidString)")
                }
            }
        }
    }
    private var photoSection: some View {
        Section("Progress photos · Optional") {
            DatePicker("Observation date", selection: $photoDate, in: ...Date(), displayedComponents: .date)
                .disabled(importing)
            TextField("Pose label (optional)", text: $photoPose).disabled(importing)
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 6, selectionBehavior: .ordered, matching: .images) {
                Label("Add Photos", systemImage: "photo.badge.plus")
            }.disabled(importing).accessibilityIdentifier("coach.body.add_photo")
            if importing {
                ProgressView(status ?? "Importing selected photos…")
                Button("Cancel Remaining Imports", role: .cancel) { importTask?.cancel() }
            }
            Text("Select up to six photos. Copies are private to this app, resized to a 2,048-pixel longest edge, with location metadata removed. Initial selection may require a Photos download; imported copies work offline. Source limit: 25 MiB / 64 megapixels.")
                .font(.caption).foregroundStyle(.secondary)
            if filteredPhotos.isEmpty { Text("No photos in this range. Measurements work without photos.").foregroundStyle(.secondary) }
            let compare = photos.filter { comparisonIDs.contains($0.id) }.sorted { $0.observedAt < $1.observedAt }
            if compare.count == 2 {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(compare) { photo in
                        VStack {
                            CoachPhotoImage(photo: photo, thumbnail: false).frame(maxWidth: .infinity).frame(height: 230)
                            Text(photo.civilDate).font(.caption)
                            if let pose = photo.pose { Text(pose).font(.caption) }
                        }
                    }
                }.accessibilityElement(children: .contain).accessibilityLabel("Side by side progress photo comparison").accessibilityIdentifier("coach.body.photo.comparison")
            }
            ForEach(filteredPhotos) { photo in
                HStack(spacing: 12) {
                    CoachPhotoImage(photo: photo).frame(width: 70, height: 86)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(photo.civilDate).font(.headline)
                        if let pose = photo.pose { Text(pose).foregroundStyle(.secondary) }
                        Button("Edit Date / Pose or Delete App Copy") { editor = .photo(photo) }.font(.caption).accessibilityIdentifier("coach.body.photo.edit.\(photo.id.uuidString)")
                        Button(comparisonIDs.contains(photo.id) ? "Remove from Comparison" : "Compare") {
                            if comparisonIDs.contains(photo.id) { comparisonIDs.remove(photo.id) }
                            else if comparisonIDs.count < 2 { comparisonIDs.insert(photo.id) }
                        }.font(.caption).disabled(comparisonIDs.count >= 2 && !comparisonIDs.contains(photo.id)).accessibilityIdentifier("coach.body.photo.compare.\(photo.id.uuidString)")
                    }
                }.buttonStyle(.borderless)
            }
        }
    }
    private func load() {
        do {
            weights = try repository.weights(); waists = try repository.waistMeasurements(); photos = try repository.photos()
            comparisonIDs.formIntersection(Set(photos.map(\.id)))
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        let date = photoDate, pose = CoachEntryNumber.note(photoPose)
        importing = true
        var completed = 0
        defer { importing = false; selectedPhotos = []; importTask = nil }
        do {
            for item in items {
                try Task.checkCancellation()
                status = "Importing photo \(completed + 1) of \(items.count)…"
                guard let file = try await item.loadTransferable(type: CoachSelectedPhotoFile.self) else { throw CoachRepositoryError.invalidValue("downloaded, readable photo") }
                defer { try? FileManager.default.removeItem(at: file.url) }
                try Task.checkCancellation()
                _ = try await repository.importPhoto(fileURL: file.url, observedAt: date, pose: pose)
                completed += 1
            }
            load(); status = "Imported \(completed) app-owned photo \(completed == 1 ? "copy" : "copies")."
        } catch is CancellationError {
            load(); status = "Canceled remaining imports. \(completed) completed copies remain saved."
        } catch {
            load(); self.error = "\(completed) copies were saved. Remaining photos were not imported: \(error.localizedDescription)"
        }
    }
}

private struct CoachSelectedPhotoFile: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let values = try received.file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 25 * 1_024 * 1_024 else { throw CocoaError(.fileReadTooLarge) }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("coach-selected-\(UUID().uuidString).image")
            do {
                try FileManager.default.copyItem(at: received.file, to: destination)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: destination.path)
                var protected = destination
                var resources = URLResourceValues(); resources.isExcludedFromBackup = true
                try protected.setResourceValues(resources)
                return CoachSelectedPhotoFile(url: destination)
            } catch { try? FileManager.default.removeItem(at: destination); throw error }
        }
    }
}

private struct CoachPhotoImage: View {
    @Environment(\.modelContext) private var context
    let photo: CoachProgressPhoto
    var thumbnail = true
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit().accessibilityIdentifier("coach.body.photo.image.\(photo.id.uuidString).\(thumbnail ? "thumbnail" : "full")") }
            else if failed { VStack { Image(systemName: "photo.badge.exclamationmark"); Text("Copy unavailable").font(.caption); Button("Retry") { attempt += 1 }.font(.caption) } }
            else { ProgressView() }
        }
        .accessibilityLabel("Progress photo \(photo.civilDate)\(photo.pose.map { ", " + $0 } ?? "")")
        .task(id: photo.assetKey + String(thumbnail) + String(attempt)) {
            failed = false
            do {
                let url = try CoachRepository(context: context).assetURL(for: photo, thumbnail: thumbnail)
                let data = try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
                try Task.checkCancellation()
                image = UIImage(data: data); failed = image == nil
            } catch is CancellationError { }
            catch { failed = true }
        }
    }
}

private struct CoachMeasurementEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let isWeight: Bool
    private let recordID: UUID?
    @State private var date: Date
    @State private var value: String
    @State private var unit: String
    @State private var notes: String
    @State private var error: String?
    init(weight: WeightEntry?) {
        isWeight = true; recordID = weight?.id
        _date = State(initialValue: weight?.date ?? Date()); _value = State(initialValue: CoachEntryNumber.input(weight?.weight))
        _unit = State(initialValue: weight.map { CoachMeasurementUnits.canonicalWeight($0.weightUnit) ?? $0.weightUnit } ?? "kg"); _notes = State(initialValue: "")
    }
    init(waist: CoachWaistMeasurement?) {
        isWeight = false; recordID = waist?.id
        _date = State(initialValue: waist?.observedAt ?? Date()); _value = State(initialValue: CoachEntryNumber.input(waist?.value))
        _unit = State(initialValue: waist?.unit ?? "cm"); _notes = State(initialValue: waist?.notes ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Observed", selection: $date, in: ...Date())
                CoachOptionalNumberField(isWeight ? "Weight" : "Waist", unit: unit, text: $value)
                Picker("Unit", selection: $unit) {
                    if !(isWeight ? ["kg", "lb"] : ["cm", "in"]).contains(unit) { Text("Unsupported: \(unit) · Choose a unit").tag(unit) }
                    ForEach(isWeight ? ["kg", "lb"] : ["cm", "in"], id: \.self) { Text($0).tag($0) }
                }
                Text("Enter the value in the selected unit. Changing the unit does not convert the typed number.").font(.caption).foregroundStyle(.secondary)
                if !isWeight { TextField("Notes (optional)", text: $notes, axis: .vertical) }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("coach.body.measurement.error") }
                if recordID != nil {
                    Button("Delete App Observation", role: .destructive) { remove() }.accessibilityIdentifier("coach.body.measurement.delete")
                    Text("Deleting this observation does not delete an original Apple Health sample.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollDismissesKeyboard(.interactively).navigationTitle(isWeight ? "Weight Observation" : "Waist Observation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).accessibilityIdentifier("coach.body.measurement.save") }
            }
        }
    }
    private func save() {
        do {
            guard let number = try CoachEntryNumber.optional(value) else { throw CoachRepositoryError.invalidValue("measurement") }
            let repository = CoachRepository(context: context)
            if isWeight { _ = try repository.saveWeight(date: date, value: number, unit: unit, id: recordID) }
            else { _ = try repository.saveWaist(date: date, value: number, unit: unit, notes: CoachEntryNumber.note(notes), id: recordID) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func remove() {
        guard let recordID else { return }
        do {
            let repository = CoachRepository(context: context)
            if isWeight {
                try repository.transaction { isolated in
                    if let row = try isolated.fetch(FetchDescriptor<WeightEntry>()).first(where: { $0.id == recordID }) { isolated.delete(row) }
                }
            } else { try repository.deleteWaist(id: recordID) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct CoachPhotoMetadataEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let photo: CoachProgressPhoto
    @State private var date: Date
    @State private var pose: String
    @State private var error: String?
    init(photo: CoachProgressPhoto) {
        self.photo = photo; _date = State(initialValue: photo.observedAt); _pose = State(initialValue: photo.pose ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                CoachPhotoImage(photo: photo, thumbnail: false).frame(height: 260)
                DatePicker("Observation date", selection: $date, in: ...Date(), displayedComponents: .date)
                    .accessibilityIdentifier("coach.body.photo.observed_date")
                TextField("Pose label (optional)", text: $pose).accessibilityIdentifier("coach.body.photo.pose")
                Button("Delete App Copy", role: .destructive) {
                    do { try CoachRepository(context: context).deletePhoto(id: photo.id); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("coach.body.photo.delete")
                Text("Deleting the app copy leaves the original in your Photos library unchanged.").font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .scrollDismissesKeyboard(.interactively).navigationTitle("Photo Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try CoachRepository(context: context).updatePhoto(id: photo.id, observedAt: date, pose: CoachEntryNumber.note(pose)); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("coach.body.photo.save")
                }
            }
        }
    }
}


enum CoachMeasurementUnits {
    static func canonicalWeight(_ unit: String) -> String? {
        switch unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "kg", "kgs", "kilogram", "kilograms": "kg"
        case "lb", "lbs", "pound", "pounds": "lb"
        default: nil
        }
    }
    static func kilograms(_ value: Double, unit: String) -> Double? {
        guard value.isFinite, value > 0, let unit = canonicalWeight(unit) else { return nil }
        return unit == "kg" ? value : value * 0.45359237
    }
    static func centimeters(_ value: Double, unit: String) -> Double? {
        guard value.isFinite, value > 0 else { return nil }
        switch unit { case "cm": return value; case "in": return value * 2.54; default: return nil }
    }
    static func kilometers(_ value: Double, unit: String) -> Double? {
        guard value.isFinite, value >= 0 else { return nil }
        switch unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "km", "kilometer", "kilometers": return value
        case "mi", "mile", "miles": return value * 1.609344
        case "m", "meter", "meters": return value / 1000
        default: return nil
        }
    }
}
