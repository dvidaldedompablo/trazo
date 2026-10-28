import CoreGraphics

/// Fondo de la pantalla Grabar para las capturas del CI y el simulador, que no tienen cámara:
/// el campo de prácticas de s02, con las coordenadas exactas del SVG de `design/maqueta.html`
/// (pantalla de 390 x 844 puntos; en el SVG todo está 110 puntos más abajo).
enum CaptureScene {
    static let size = CGSize(width: 390, height: 844)

    /// Cielo de arriba hasta el horizonte (con el degradado medido en su propio alto) y la calle.
    static let skyTop: CGFloat = -110
    static let skyBottom: CGFloat = 264
    static let grassTop: CGFloat = 262
    static let grassBottom: CGFloat = 850
    static let sunCenter = P(312, -14)
    static let sunRadius: CGFloat = 140

    /// Franjas de corte: salen del punto de fuga y miden 78 puntos abajo.
    static let stripesVanishingPoint = P(205, 262)
    static let stripeStarts: [CGFloat] = [-419, -263, -107, 49, 205, 361, 517, 673]
    static let stripeWidth: CGFloat = 78

    /// Carteles de 50, 100 y 150 m.
    static let boards = [
        DistanceBoard(text: "50", frame: CGRect(x: 100.75, y: 296.75, width: 34.5, height: 17.25), cornerRadius: 2.3,
                      postBottom: 330.1, postWidth: 1.61, fontSize: 12.65, baseline: 309.86),
        DistanceBoard(text: "100", frame: CGRect(x: 291.25, y: 275.25, width: 25.5, height: 12.75), cornerRadius: 1.7,
                      postBottom: 299.9, postWidth: 1.19, fontSize: 9.35, baseline: 284.94),
        DistanceBoard(text: "150", frame: CGRect(x: 158.7, y: 266.7, width: 18.6, height: 9.3), cornerRadius: 1.24,
                      postBottom: 284.68, postWidth: 0.868, fontSize: 6.82, baseline: 273.768),
    ]

    /// Zona de golpeo (alfombra) y la bola.
    static let teeBox = [P(60, 850), P(390, 850), P(390, 636), P(128, 622)]
    static let ball = P(326, 670)
    static let ballRadius: CGFloat = 5
    static let ballShadow = CGRect(x: 321, y: 672.6, width: 14, height: 4.8)
    static let ballHighlight = P(324.5, 668.5)

    static let backTrees = TreeLine(
        start: P(-30, 265),
        firstBase: P(-10, 244.6),
        crowns: [
            P(-5.4, 239.7), P(-0.8, 245.3), P(4, 238.5), P(8.8, 246), P(12.1, 239.3), P(15.5, 248.8),
            P(20.9, 243.6), P(26.3, 249.5), P(30.1, 244.2), P(33.8, 249.6), P(38.3, 244), P(42.7, 250.9),
            P(47.1, 244.9), P(51.6, 251.7), P(55.1, 245.9), P(58.7, 251.9), P(64.2, 246.2), P(69.7, 251.9),
            P(74.8, 245.5), P(80, 251.3), P(83.3, 243.8), P(86.6, 250.6), P(91.3, 244.5), P(96.1, 250),
            P(99.3, 242.9), P(102.6, 248.2), P(107, 240.7), P(111.4, 246.9), P(116.9, 240.1), P(122.5, 244.8),
            P(128.1, 239.4), P(133.7, 244.3), P(139, 235.6), P(144.4, 242.5), P(150, 232.8), P(155.7, 238.4),
            P(159.1, 232.7), P(162.5, 242.7), P(166.3, 232.5), P(170, 236.5), P(174.3, 231.3), P(178.7, 238.7),
            P(182.6, 233), P(186.6, 239.7), P(190.8, 235.6), P(195, 241.2), P(199.7, 234.6), P(204.4, 240.4),
            P(210, 234.5), P(215.6, 241.3), P(221.3, 237.1), P(226.9, 242.4), P(232.8, 236.5), P(238.6, 245.3),
            P(242.2, 239.9), P(245.8, 246.1), P(251.5, 240.1), P(257.3, 248.2), P(262, 243.1), P(266.6, 249.9),
            P(270.4, 243.8), P(274.1, 250.8), P(278.8, 244.5), P(283.5, 251.7), P(286.8, 247.6), P(290.1, 251.9),
            P(295.9, 247.7), P(301.8, 251.9), P(307.1, 245.4), P(312.4, 251.4), P(316, 244), P(319.5, 250.9),
            P(324.7, 244.3), P(330, 249), P(333.2, 243), P(336.5, 248.4), P(339.8, 241.3), P(343, 247),
            P(347.1, 240), P(351.1, 245), P(356.9, 239.2), P(362.7, 244.3), P(368.6, 238.7), P(374.4, 243.6),
            P(377.8, 235.9), P(381.1, 241), P(384.4, 235.3), P(387.6, 242.9), P(391.9, 234.5), P(396.1, 239.4),
            P(399.7, 234.3), P(403.2, 243),
        ],
        end: P(420, 265)
    )

    static let frontTrees = TreeLine(
        start: P(-30, 267),
        firstBase: P(-10, 259.9),
        crowns: [
            P(-6.4, 255.8), P(-2.7, 260), P(0.7, 253.1), P(4.1, 260), P(7.8, 255.1), P(11.5, 259.8),
            P(15, 253.4), P(18.5, 259.5), P(22.6, 254.5), P(26.8, 259.3), P(29.8, 252.4), P(32.9, 258.9),
            P(37.1, 251.8), P(41.2, 257.6), P(43.8, 251.7), P(46.3, 256.6), P(50.8, 251.6), P(55.3, 256.1),
            P(59, 249.9), P(62.7, 256.5), P(65.2, 250.8), P(67.7, 255), P(70.3, 250.4), P(72.9, 255.6),
            P(75.8, 249.9), P(78.8, 255.7), P(82.2, 247.2), P(85.6, 253.7), P(89.8, 247), P(94.1, 252.8),
            P(97.9, 247.7), P(101.6, 252.5), P(105.5, 245.8), P(109.3, 252.5), P(112.4, 245.4), P(115.4, 250),
            P(119.9, 246), P(124.5, 250.8), P(128.4, 246), P(132.4, 253.4), P(135.3, 248.1), P(138.2, 253.8),
            P(140.8, 248), P(143.4, 252.2), P(146.7, 247.7), P(150, 252.5), P(153.3, 247.4), P(156.5, 252.8),
            P(160.7, 247.1), P(165, 256.6), P(167.9, 250.4), P(170.8, 254.8), P(174.2, 249.7), P(177.6, 255.5),
            P(180.9, 248.8), P(184.2, 257.9), P(188, 250.6), P(191.7, 257.6), P(194.8, 251.6), P(197.8, 258.8),
            P(200.9, 252.6), P(204.1, 258.6), P(208.1, 252.9), P(212.2, 259.6), P(215.1, 255.1), P(218.1, 259.8),
            P(220.7, 255.7), P(223.2, 259.9), P(226.1, 255.8), P(228.9, 260), P(232.3, 253.3), P(235.7, 260),
            P(239.7, 253.8), P(243.6, 259.9), P(247.4, 252.7), P(251.2, 259.6), P(254.6, 255.2), P(257.9, 259.3),
            P(260.9, 252.4), P(263.9, 258.3), P(268.1, 252.7), P(272.2, 258.2), P(276.5, 251.4), P(280.8, 257.6),
            P(284.1, 250.8), P(287.4, 255.7), P(291.2, 248.7), P(295, 256.7), P(299.5, 251.4), P(304, 255.6),
            P(307, 247.6), P(310, 253.2), P(313.2, 247), P(316.3, 254.4), P(318.9, 247.7), P(321.5, 254.8),
            P(325.2, 247.7), P(328.9, 253.9), P(332.6, 246.9), P(336.3, 253), P(339.7, 243.9), P(343.1, 250.2),
            P(346.6, 243.5), P(350, 251.9), P(354.3, 246.9), P(358.6, 253.8), P(361.3, 244.8), P(364.1, 250.8),
            P(368.3, 244.1), P(372.4, 254), P(375.3, 245.9), P(378.1, 252.5), P(382.6, 247.3), P(387, 255.2),
            P(391.4, 247.5), P(395.9, 253.9), P(399.6, 247.3), P(403.3, 256),
        ],
        end: P(420, 267)
    )
}

/// Abreviatura para que las listas de puntos se lean en una línea.
private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: y)
}
