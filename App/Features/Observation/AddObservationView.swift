import GrzybEngine
import PhotosUI
import SwiftUI

/// Observation form: species, amount, place, date, photo, note; typical find takes ≤ 3 taps.
struct AddObservationView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let draft: ObservationDraft
    @State private var speciesId: String?
    @State private var isEmpty = false
    @State private var amount = 2
    @State private var coordinate: Coordinate?
    @State private var date = Date()
    @State private var note = ""
    @State private var photo: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    kindToggle
                    speciesSection
                    if !isEmpty { amountSection }
                    locationSection
                    detailsSection
                }
                .padding(Theme.Spacing.xl)
            }
            .safeAreaInset(edge: .bottom) {
                Button(draft.editing == nil ? "Zapisz" : "Zapisz zmiany", action: save)
                    .buttonStyle(PrimaryPillStyle())
                    .disabled(coordinate == nil || (!isEmpty && speciesId == nil))
                    .padding(Theme.Spacing.lg)
                    .background(Theme.Palette.canvas)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Anuluj") { dismiss() }.foregroundStyle(Theme.Palette.ink)
                }
                ToolbarItem(placement: .principal) {
                    Text(draft.editing == nil ? "NOWA OBSERWACJA" : "EDYCJA").font(Theme.Typeface.display(24))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: load)
        .onChange(of: pickerItem) { _, item in loadPhoto(item) }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $photo).ignoresSafeArea()
        }
    }

    private var kindToggle: some View {
        HStack(spacing: Theme.Spacing.sm) {
            FilterChip(title: "Znalazłem", isSelected: !isEmpty) { isEmpty = false }
            FilterChip(title: "Było pusto", isSelected: isEmpty) { isEmpty = true }
        }
    }

    private var speciesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Gatunek")
            FlowLayout(spacing: Theme.Spacing.sm) {
                if isEmpty {
                    FilterChip(title: "Nic", isSelected: speciesId == nil) { speciesId = nil }
                }
                ForEach(orderedSpecies) { species in
                    FilterChip(title: species.namePl, isSelected: speciesId == species.id) { speciesId = species.id }
                }
            }
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Ilość")
            HStack(spacing: Theme.Spacing.sm) {
                ForEach([(1, "Pojedyncze"), (2, "Kilka"), (3, "Dużo")], id: \.0) { value, label in
                    FilterChip(title: label, isSelected: amount == value) { amount = value }
                }
            }
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Miejsce", trailing: coordinate.map { String(format: "%.5f, %.5f", $0.lat, $0.lon) })
            ZStack {
                ForestMapView(
                    content: MapContent(),
                    initialCamera: coordinate.map { ($0, 16) },
                    onCameraChange: { center, _, _ in coordinate = center }
                )
                Image(systemName: "mappin")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.Palette.signal)
                    .offset(y: -17)
                    .allowsHitTesting(false)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.field))
            Text("Przesuń mapę, żeby ustawić pinezkę.")
                .font(Theme.Typeface.captionSM)
                .foregroundStyle(Theme.Palette.mute)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Szczegóły")
            DatePicker("Data", selection: $date, in: ...Date())
                .font(Theme.Typeface.bodyStrong)
                .tint(Theme.Palette.ink)
            HStack(spacing: Theme.Spacing.sm) {
                Button { showCamera = true } label: { Label("Aparat", systemImage: "camera") }
                    .buttonStyle(SecondaryPillStyle())
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Biblioteka", systemImage: "photo")
                        .font(Theme.Typeface.button)
                        .foregroundStyle(Theme.Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.Palette.softCloud, in: Capsule())
                }
            }
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
            TextField("Notatka", text: $note, axis: .vertical)
                .font(Theme.Typeface.body)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.Palette.softCloud, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
        }
    }

    private var orderedSpecies: [SpeciesProfile] {
        let recent = app.journal.observations.compactMap(\.speciesId)
        let rank = Dictionary(recent.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        return app.species.profiles.sorted { (rank[$0.id] ?? Int.max, $0.namePl) < (rank[$1.id] ?? Int.max, $1.namePl) }
    }

    private func load() {
        speciesId = draft.speciesId ?? (draft.kind == .found ? orderedSpecies.first?.id : nil)
        isEmpty = draft.kind == .empty
        coordinate = draft.coordinate ?? app.services.location.coordinate
        if let editing = draft.editing {
            amount = editing.amount
            date = editing.observedAt
            note = editing.note ?? ""
            photo = app.journal.photo(editing.photoPath)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        Task {
            if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                photo = image
            }
        }
    }

    private func save() {
        guard let coordinate else { return }
        var obs = draft.editing ?? FieldObservation(speciesId: speciesId, kind: .found, lon: coordinate.lon, lat: coordinate.lat)
        let moved = draft.editing.map { $0.coordinate != coordinate || $0.speciesId != speciesId || $0.observedAt != date } ?? true
        obs.speciesId = speciesId
        obs.kind = isEmpty ? .empty : .found
        obs.amount = isEmpty ? 1 : amount
        obs.lon = coordinate.lon
        obs.lat = coordinate.lat
        obs.observedAt = date
        obs.note = note.isEmpty ? nil : note
        if let photo { obs.photoPath = app.journal.savePhoto(photo, id: obs.id) }
        if moved {
            obs.factors = nil
            obs.context = nil
        }
        app.record(obs)
        app.toast = isEmpty ? "Zapisano: pusto" : "Zapisano znalezisko"
        dismiss()
    }
}

/// Wraps UIImagePickerController for taking a photo in the forest.
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            rows[rows.count - 1].indices.append(i)
            rows[rows.count - 1].width += size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
