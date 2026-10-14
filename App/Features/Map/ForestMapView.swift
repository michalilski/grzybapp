import GrzybEngine
import GrzybStore
import MapLibre
import SwiftUI

/// One-shot camera instruction; a new id triggers it again.
struct MapCommand: Equatable {
    enum Action: Equatable {
        case center(Coordinate, zoom: Double)
        case fit(BoundingBox)
    }

    let id = UUID()
    let action: Action
}

/// Everything the map draws, passed down from SwiftUI.
struct MapContent: Equatable {
    var overlay: ScoreOverlay?
    var overlayOpacity: Double = 0.6
    var outlinesURL: URL?
    var showOutlines = true
    var observations: [FieldObservation] = []
    var regionBoxes: [BoundingBox] = []
    var selection: BoundingBox?
}

/// MapLibre map with OpenFreeMap style, user location, potential overlay and observation markers.
struct ForestMapView: UIViewRepresentable {
    var content: MapContent
    var command: MapCommand?
    var initialCamera: (center: Coordinate, zoom: Double)?
    var interactive = true
    var onTap: (Coordinate) -> Void = { _ in }
    var onLongPress: (Coordinate) -> Void = { _ in }
    var onCameraChange: (Coordinate, Double, BoundingBox) -> Void = { _, _, _ in }

    func makeCoordinator() -> MapCoordinator {
        MapCoordinator()
    }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: OfflineTilesService.styleURL)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsUserHeadingIndicator = true
        map.compassViewPosition = .topRight
        map.compassViewMargins = CGPoint(x: 16, y: 120)
        map.logoView.isHidden = true
        map.attributionButtonPosition = .bottomLeft
        map.attributionButtonMargins = CGPoint(x: 8, y: 8)
        map.isRotateEnabled = interactive
        map.isPitchEnabled = false
        let camera = initialCamera ?? (Coordinate(lon: 19.4, lat: 52.0), 5.3)
        map.setCenter(CLLocationCoordinate2D(latitude: camera.center.lat, longitude: camera.center.lon), zoomLevel: camera.zoom, animated: false)
        context.coordinator.installGestures(on: map)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.apply(content, to: map)
        if let command, command != coordinator.lastCommand {
            coordinator.lastCommand = command
            coordinator.perform(command, on: map)
        }
    }
}

final class MapCoordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
    var parent: ForestMapView?
    var lastCommand: MapCommand?
    private var applied: MapContent?
    private var styleReady = false
    private var pending: MapContent?

    private enum ID {
        static let overlaySource = "potential-src"
        static let overlayLayer = "potential"
        static let outlineSource = "stands-src"
        static let outlineLayer = "stands"
        static let foundSource = "found-src"
        static let foundLayer = "found"
        static let emptySource = "empty-src"
        static let emptyLayer = "empty"
        static let regionSource = "regions-src"
        static let regionLayer = "regions"
        static let selectionSource = "selection-src"
        static let selectionLayer = "selection"
    }

    func installGestures(on map: MLNMapView) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        for recognizer in map.gestureRecognizers ?? [] where (recognizer as? UITapGestureRecognizer)?.numberOfTapsRequired == 2 {
            tap.require(toFail: recognizer)
        }
        map.addGestureRecognizer(tap)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        press.minimumPressDuration = 0.5
        map.addGestureRecognizer(press)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let map = recognizer.view as? MLNMapView else { return }
        parent?.onTap(coordinate(recognizer.location(in: map), map))
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let map = recognizer.view as? MLNMapView else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        parent?.onLongPress(coordinate(recognizer.location(in: map), map))
    }

    private func coordinate(_ point: CGPoint, _ map: MLNMapView) -> Coordinate {
        let c = map.convert(point, toCoordinateFrom: map)
        return Coordinate(lon: c.longitude, lat: c.latitude)
    }

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        localizeLabels(style)
        styleReady = true
        applied = nil
        if let pending { apply(pending, to: mapView) }
    }

    func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
        let c = mapView.centerCoordinate
        let b = mapView.visibleCoordinateBounds
        let box = BoundingBox(minLon: b.sw.longitude, minLat: b.sw.latitude, maxLon: b.ne.longitude, maxLat: b.ne.latitude)
        parent?.onCameraChange(Coordinate(lon: c.longitude, lat: c.latitude), mapView.zoomLevel, box)
    }

    /// OpenFreeMap carries `name:pl`; show it where available instead of English names.
    private func localizeLabels(_ style: MLNStyle) {
        let polish = NSExpression(mglJSONObject: ["coalesce", ["get", "name:pl"], ["get", "name"]])
        for case let layer as MLNSymbolStyleLayer in style.layers where layer.text != nil {
            let current = layer.text.description
            if current.contains("name") { layer.text = polish }
        }
    }

    func perform(_ command: MapCommand, on map: MLNMapView) {
        switch command.action {
        case .center(let c, let zoom):
            map.setCenter(CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon), zoomLevel: zoom, animated: true)
        case .fit(let box):
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: box.minLat, longitude: box.minLon),
                ne: CLLocationCoordinate2D(latitude: box.maxLat, longitude: box.maxLon)
            )
            map.setVisibleCoordinateBounds(bounds, edgePadding: UIEdgeInsets(top: 140, left: 24, bottom: 200, right: 24), animated: true, completionHandler: nil)
        }
    }

    func apply(_ content: MapContent, to map: MLNMapView) {
        guard styleReady, let style = map.style else {
            pending = content
            return
        }
        let old = applied
        if old?.overlay != content.overlay || old?.overlayOpacity != content.overlayOpacity {
            applyOverlay(content, style)
        }
        if old?.outlinesURL != content.outlinesURL || old?.showOutlines != content.showOutlines {
            applyOutlines(content, style)
        }
        if old?.observations != content.observations { applyObservations(content.observations, style) }
        if old?.regionBoxes != content.regionBoxes { applyRegions(content.regionBoxes, style) }
        if old?.selection != content.selection { applySelection(content.selection, style) }
        applied = content
    }

    private func firstSymbolLayer(_ style: MLNStyle) -> MLNStyleLayer? {
        style.layers.first { $0 is MLNSymbolStyleLayer }
    }

    private func insert(_ layer: MLNStyleLayer, _ style: MLNStyle, belowLabels: Bool = true) {
        if belowLabels, let symbol = firstSymbolLayer(style) {
            style.insertLayer(layer, below: symbol)
        } else {
            style.addLayer(layer)
        }
    }

    private func applyOverlay(_ content: MapContent, _ style: MLNStyle) {
        guard let overlay = content.overlay else {
            remove([ID.overlayLayer], [ID.overlaySource], style)
            return
        }
        let b = overlay.bbox
        let quad = MLNCoordinateQuad(
            topLeft: CLLocationCoordinate2D(latitude: b.maxLat, longitude: b.minLon),
            bottomLeft: CLLocationCoordinate2D(latitude: b.minLat, longitude: b.minLon),
            bottomRight: CLLocationCoordinate2D(latitude: b.minLat, longitude: b.maxLon),
            topRight: CLLocationCoordinate2D(latitude: b.maxLat, longitude: b.maxLon)
        )
        if let source = style.source(withIdentifier: ID.overlaySource) as? MLNImageSource {
            source.coordinates = quad
            source.image = overlay.image
        } else {
            let source = MLNImageSource(identifier: ID.overlaySource, coordinateQuad: quad, image: overlay.image)
            style.addSource(source)
            let layer = MLNRasterStyleLayer(identifier: ID.overlayLayer, source: source)
            layer.rasterFadeDuration = NSExpression(forConstantValue: 0)
            insert(layer, style)
        }
        guard let layer = style.layer(withIdentifier: ID.overlayLayer) as? MLNRasterStyleLayer else { return }
        let mode: MLNRasterResamplingMode = overlay.smooth ? .linear : .nearest
        layer.rasterResamplingMode = NSExpression(forConstantValue: NSValue(mlnRasterResamplingMode: mode))
        layer.rasterOpacity = NSExpression(forConstantValue: overlay.smooth ? 1 : content.overlayOpacity)
    }

    private func applyOutlines(_ content: MapContent, _ style: MLNStyle) {
        remove([ID.outlineLayer], [ID.outlineSource], style)
        guard content.showOutlines, let url = content.outlinesURL, FileManager.default.fileExists(atPath: url.path) else { return }
        let source = MLNShapeSource(identifier: ID.outlineSource, url: url, options: nil)
        style.addSource(source)
        let layer = MLNLineStyleLayer(identifier: ID.outlineLayer, source: source)
        layer.minimumZoomLevel = 14.5
        layer.lineColor = NSExpression(forConstantValue: UIColor(white: 0.07, alpha: 0.45))
        layer.lineWidth = NSExpression(forConstantValue: 0.8)
        insert(layer, style)
    }

    private func applyObservations(_ observations: [FieldObservation], _ style: MLNStyle) {
        let found = observations.filter { $0.kind == .found }.map(point)
        let empty = observations.filter { $0.kind == .empty }.map(point)
        upsertShape(ID.foundSource, MLNShapeCollectionFeature(shapes: found), style) { source in
            let layer = MLNCircleStyleLayer(identifier: ID.foundLayer, source: source)
            layer.circleRadius = NSExpression(forConstantValue: 6)
            layer.circleColor = NSExpression(forConstantValue: UIColor(white: 0.07, alpha: 1))
            layer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            layer.circleStrokeWidth = NSExpression(forConstantValue: 2)
            return layer
        }
        upsertShape(ID.emptySource, MLNShapeCollectionFeature(shapes: empty), style) { source in
            let layer = MLNCircleStyleLayer(identifier: ID.emptyLayer, source: source)
            layer.circleRadius = NSExpression(forConstantValue: 5)
            layer.circleColor = NSExpression(forConstantValue: UIColor.white)
            layer.circleStrokeColor = NSExpression(forConstantValue: UIColor(white: 0.07, alpha: 1))
            layer.circleStrokeWidth = NSExpression(forConstantValue: 2)
            return layer
        }
    }

    private func applyRegions(_ boxes: [BoundingBox], _ style: MLNStyle) {
        let lines = boxes.map(ring)
        upsertShape(ID.regionSource, MLNShapeCollectionFeature(shapes: lines), style) { source in
            let layer = MLNLineStyleLayer(identifier: ID.regionLayer, source: source)
            layer.lineColor = NSExpression(forConstantValue: UIColor(white: 0.07, alpha: 0.8))
            layer.lineWidth = NSExpression(forConstantValue: 1.5)
            layer.lineDashPattern = NSExpression(forConstantValue: [3, 2])
            return layer
        }
    }

    private func applySelection(_ selection: BoundingBox?, _ style: MLNStyle) {
        let shapes = selection.map { [ring($0)] } ?? []
        upsertShape(ID.selectionSource, MLNShapeCollectionFeature(shapes: shapes), style, belowLabels: false) { source in
            let layer = MLNLineStyleLayer(identifier: ID.selectionLayer, source: source)
            layer.lineColor = NSExpression(forConstantValue: UIColor(white: 0.07, alpha: 1))
            layer.lineWidth = NSExpression(forConstantValue: 3)
            return layer
        }
    }

    private func upsertShape(
        _ id: String, _ shape: MLNShape, _ style: MLNStyle, belowLabels: Bool = true,
        makeLayer: (MLNShapeSource) -> MLNStyleLayer
    ) {
        if let source = style.source(withIdentifier: id) as? MLNShapeSource {
            source.shape = shape
            return
        }
        let source = MLNShapeSource(identifier: id, shape: shape, options: nil)
        style.addSource(source)
        insert(makeLayer(source), style, belowLabels: belowLabels)
    }

    private func remove(_ layers: [String], _ sources: [String], _ style: MLNStyle) {
        for id in layers { if let layer = style.layer(withIdentifier: id) { style.removeLayer(layer) } }
        for id in sources { if let source = style.source(withIdentifier: id) { style.removeSource(source) } }
    }

    private func point(_ obs: FieldObservation) -> MLNPointFeature {
        let feature = MLNPointFeature()
        feature.coordinate = CLLocationCoordinate2D(latitude: obs.lat, longitude: obs.lon)
        return feature
    }

    private func ring(_ box: BoundingBox) -> MLNPolylineFeature {
        var coords = [
            CLLocationCoordinate2D(latitude: box.maxLat, longitude: box.minLon),
            CLLocationCoordinate2D(latitude: box.maxLat, longitude: box.maxLon),
            CLLocationCoordinate2D(latitude: box.minLat, longitude: box.maxLon),
            CLLocationCoordinate2D(latitude: box.minLat, longitude: box.minLon),
            CLLocationCoordinate2D(latitude: box.maxLat, longitude: box.minLon),
        ]
        return MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
    }
}
