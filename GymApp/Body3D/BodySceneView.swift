import SwiftUI
import SceneKit

/// SceneKit view with drag-to-rotate and tap-to-identify muscles.
struct BodySceneView: UIViewRepresentable {
    let scene: SCNScene
    var onTapMuscle: (MuscleGroup?) -> Void = { _ in }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.target = SCNVector3(0, 0.9, 0)
        view.antialiasingMode = .multisampling4X
        view.scene = scene
        view.addGestureRecognizer(UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onTap = onTapMuscle
        if view.scene !== scene {
            // Keep the user's current camera angle when the model is rebuilt.
            let pov = view.pointOfView?.clone()
            view.scene = scene
            if let pov { scene.rootNode.addChildNode(pov); view.pointOfView = pov }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTapMuscle) }

    final class Coordinator: NSObject {
        var onTap: (MuscleGroup?) -> Void
        init(onTap: @escaping (MuscleGroup?) -> Void) { self.onTap = onTap }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let view = g.view as? SCNView else { return }
            let hit = view.hitTest(g.location(in: view), options: nil)
                .first { $0.node.name?.hasPrefix("muscle:") == true }
            let raw = hit?.node.name?.replacingOccurrences(of: "muscle:", with: "")
            onTap(raw.flatMap(MuscleGroup.init))
        }
    }
}
