import AppKit
import SwiftUI

@available(macOS 26, *)
struct GlassOutlineShape: Shape {
    var halo: CGRect
    var panel: CGRect
    var haloRadius: CGFloat
    var panelRadius: CGFloat
    var fillet: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bottom = halo.maxY
        let hangs = panel.maxY - bottom >= fillet + panelRadius && panel.maxX < halo.maxX
        guard hangs else {
            path.addRoundedRect(
                in: halo.union(panel), cornerSize: CGSize(width: haloRadius, height: haloRadius))
            return path
        }
        let left = halo.minX
        let right = halo.maxX
        let top = halo.minY
        let neck = panel.maxX
        path.move(to: CGPoint(x: left + haloRadius, y: top))
        path.addArc(
            tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right, y: bottom),
            radius: haloRadius)
        path.addArc(
            tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: left, y: bottom),
            radius: haloRadius)
        path.addArc(
            tangent1End: CGPoint(x: neck, y: bottom),
            tangent2End: CGPoint(x: neck, y: bottom + fillet), radius: fillet)
        path.addArc(
            tangent1End: CGPoint(x: neck, y: panel.maxY),
            tangent2End: CGPoint(x: left, y: panel.maxY), radius: panelRadius)
        path.addArc(
            tangent1End: CGPoint(x: left, y: panel.maxY), tangent2End: CGPoint(x: left, y: top),
            radius: panelRadius)
        path.addArc(
            tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: right, y: top),
            radius: haloRadius)
        path.closeSubpath()
        return path
    }
}

@available(macOS 26, *)
struct GlassOutlineView: View {
    let shape: GlassOutlineShape
    let tint: Color

    var body: some View {
        Color.clear
            .glassEffect(.regular.tint(tint), in: shape)
    }
}
