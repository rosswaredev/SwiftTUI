import Observation
import Foundation

@available(macOS 14.0, *)
extension View {
    func setupObservableClassProperties(node: Node) {
        let hasObservableProperty = Mirror(reflecting: self).children.contains { _, value in
            value is Observation.Observable
        }
        guard hasObservableProperty else { return }
        startObservation(node: node)
    }

    func startObservation(node: Node) {
        guard let application = node.root.application else {
            return
        }

        let nodeID = ObjectIdentifier(node)
        node._observationRestart = { [weak node] in
            guard let node else { return }
            self.startObservation(node: node)
        }
        application._registerObservedNode(node)

        log("Starting observation")
        _ = withObservationTracking {
            self.body
        } onChange: {
            Task { @MainActor in
                application._handleObservationChange(for: nodeID)
            }
        }
    }
}