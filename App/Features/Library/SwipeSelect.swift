import SwiftUI
import UIKit

/// Deslizar para seleccionar en "Tus vídeos", como en Fotos, con un gesto de UIKit (no de SwiftUI).
///
/// Por qué UIKit: hay que hacer tres cosas que SwiftUI no deja hacer juntas:
/// 1. Empezar solo si el dedo sale de lado (si sale en vertical, la lista se desplaza como siempre).
/// 2. En cuanto empieza, cortar el arrastre de la lista para que no se mueva con el dedo.
/// 3. Desplazar la lista desde el código cuando el dedo está en el borde, para llegar a los vídeos de
///    más abajo. Con `scrollDisabled` de SwiftUI también se bloqueaba esto, y solo se podían elegir los
///    que se veían en pantalla.
struct SwipeSelectGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    /// El espacio de coordenadas en el que se dan los puntos (el de la pantalla de la lista).
    let coordinateSpace: NamedCoordinateSpace
    let scroller: SwipeScroller
    let onBegan: (_ start: CGPoint, _ current: CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
        context.coordinator.scroller = scroller
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let location = context.converter.location(in: coordinateSpace)
        switch recognizer.state {
        case .began:
            // Se corta el arrastre de la lista: desde aquí, el dedo selecciona y no desplaza.
            scroller.cancelUserScroll()
            let moved = recognizer.translation(in: recognizer.view)
            onBegan(CGPoint(x: location.x - moved.x, y: location.y - moved.y), location)
        case .changed:
            onChanged(location)
        default:
            onEnded()
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(scroller: scroller)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var scroller: SwipeScroller

        init(scroller: SwipeScroller) {
            self.scroller = scroller
        }

        /// Solo empieza si el dedo va más de lado que en vertical.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        /// Al primer toque se busca la lista (el UIScrollView de encima) para poder desplazarla.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if scroller.scrollView == nil {
                var view = gestureRecognizer.view
                while let current = view, !(current is UIScrollView) { view = current.superview }
                scroller.scrollView = view as? UIScrollView
            }
            return true
        }

        /// Convive con el arrastre de la lista hasta que se ve hacia dónde va el dedo.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other === scroller.scrollView?.panGestureRecognizer
        }
    }
}

/// La lista de "Tus vídeos" vista desde UIKit: para cortar su arrastre y desplazarla desde el código.
@MainActor
final class SwipeScroller {
    weak var scrollView: UIScrollView?

    /// Corta el arrastre que lleve la lista (al apagar y encender su gesto, el dedo deja de moverla).
    func cancelUserScroll() {
        guard let pan = scrollView?.panGestureRecognizer else { return }
        pan.isEnabled = false
        pan.isEnabled = true
    }

    /// Desplaza la lista `delta` puntos sin salirse de sus límites. Devuelve si se ha movido.
    @discardableResult
    func scroll(by delta: CGFloat) -> Bool {
        guard let scrollView else { return false }
        let top = -scrollView.adjustedContentInset.top
        let bottom = max(scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom, top)
        let current = scrollView.contentOffset.y
        let target = min(max(current + delta, top), bottom)
        guard abs(target - current) > 0.1 else { return false }
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: target), animated: false)
        return true
    }
}
