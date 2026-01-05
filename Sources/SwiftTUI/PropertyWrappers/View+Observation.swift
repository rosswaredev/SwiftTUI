import Observation
import Foundation

@available(macOS 14.0, *)
extension View {
    func setupObservableClassProperties(node: Node) {
        for (_, value) in Mirror(reflecting: self).children {
            if value is Observation.Observable {
                startObservation(node: node)
            }
        }
    }
    
    func startObservation(node: Node) {
        log("Starting observation")
        withObservationTracking {
            _ = self.body
        } onChange: {
            log("Observation observed a change. invalidating node...")
            node.root.application?.invalidateNode(node)
            startObservation(node: node)
        }
    }
}
