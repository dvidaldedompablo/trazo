import CoreGraphics

/// Datos de la ventana del Tracer en Inicio, copiados de `design/maqueta.html`.
/// Todo está en el sistema de coordenadas de la maqueta: una ventana de 358 x 180 puntos
/// con el origen arriba a la izquierda y la y hacia abajo.
enum PreviewScene {
    static let size = CGSize(width: 358, height: 180)

    /// Donde acaba el cielo y empieza la calle.
    static let skyBottom: CGFloat = 118
    static let grassTop: CGFloat = 116
    /// Centro y radio del resplandor del sol.
    static let sunCenter = P(300, 10)
    static let sunRadius: CGFloat = 120

    /// Punto de fuga de las franjas de corte de la calle y el borde izquierdo de cada franja abajo.
    /// Cada franja mide 60 pt abajo y hay una cada 120 pt.
    static let stripesVanishingPoint = P(250, 116)
    static let stripeStarts: [CGFloat] = [-290, -170, -50, 70, 190, 310, 430, 550, 670]
    static let stripeWidth: CGFloat = 60

    /// Carteles de distancia: el de 100 m cerca y el de 150 m más lejos (más pequeño).
    static let boards = [
        DistanceBoard(text: "100", frame: CGRect(x: 80, y: 120, width: 24, height: 12), cornerRadius: 1.6,
                      postBottom: 143.2, postWidth: 1.12, fontSize: 8.8, baseline: 129.12),
        DistanceBoard(text: "150", frame: CGRect(x: 197.75, y: 115.75, width: 16.5, height: 8.25), cornerRadius: 1.1,
                      postBottom: 131.7, postWidth: 0.77, fontSize: 6.05, baseline: 122.02),
    ]

    /// Vuelo de la bola, de la salida (abajo a la izquierda) a la caída.
    static let flight: [CGPoint] = [
        P(38.0, 176.0), P(41.1, 167.9), P(44.3, 159.8), P(47.7, 151.8), P(51.3, 143.9), P(55.0, 136.0),
        P(58.9, 128.3), P(62.8, 120.8), P(67.0, 113.3), P(71.2, 106.1), P(75.6, 99.0), P(80.1, 92.2),
        P(84.7, 85.5), P(89.4, 79.1), P(94.2, 73.0), P(99.2, 67.1), P(104.2, 61.6), P(109.3, 56.3),
        P(114.5, 51.4), P(119.8, 46.8), P(125.1, 42.6), P(130.5, 38.8), P(136.0, 35.3), P(141.6, 32.3),
        P(147.2, 29.7), P(152.8, 27.5), P(158.5, 25.9), P(164.2, 24.7), P(170.0, 24.0), P(175.5, 23.7),
        P(180.8, 23.8), P(185.8, 24.2), P(190.7, 25.0), P(195.4, 26.0), P(200.0, 27.3), P(204.3, 28.9),
        P(208.5, 30.8), P(212.5, 32.9), P(216.4, 35.2), P(220.1, 37.8), P(223.6, 40.6), P(227.0, 43.6),
        P(230.2, 46.8), P(233.3, 50.1), P(236.3, 53.6), P(239.1, 57.3), P(241.8, 61.1), P(244.3, 65.0),
        P(246.7, 69.1), P(249.0, 73.2), P(251.2, 77.5), P(253.3, 81.8), P(255.2, 86.1), P(257.1, 90.6),
        P(258.8, 95.0), P(260.5, 99.5), P(262.0, 104.0),
    ]

    static let backTrees = TreeLine(
        start: P(-30.0, 119.0),
        firstBase: P(-10.0, 108.0),
        crowns: [
            P(-5.4, 103.6), P(-0.8, 107.8), P(4.2, 102.8), P(9.3, 107.3), P(14.3, 100.9), P(19.3, 107.0),
            P(23.2, 98.2), P(27.1, 105.2), P(31.5, 99.6), P(35.9, 104.0), P(38.9, 99.9), P(42.0, 104.1),
            P(45.4, 96.1), P(48.8, 103.1), P(53.0, 97.5), P(57.1, 103.8), P(60.5, 97.0), P(63.8, 102.2),
            P(68.8, 94.4), P(73.8, 99.1), P(77.0, 92.6), P(80.1, 98.3), P(83.3, 91.9), P(86.4, 98.7),
            P(89.5, 93.4), P(92.6, 101.6), P(97.5, 95.0), P(102.4, 100.3), P(105.7, 92.0), P(109.0, 96.1),
            P(113.9, 89.4), P(118.8, 100.1), P(123.9, 95.3), P(129.0, 99.4), P(133.5, 93.9), P(137.9, 101.7),
            P(143.0, 94.2), P(148.0, 100.7), P(153.1, 96.3), P(158.3, 101.4), P(161.8, 95.3), P(165.3, 103.9),
            P(168.5, 97.1), P(171.7, 105.1), P(174.6, 99.2), P(177.6, 105.4), P(181.8, 99.0), P(186.1, 106.6),
            P(190.5, 102.3), P(194.9, 106.9), P(198.5, 101.6), P(202.0, 107.2), P(206.0, 102.8), P(209.9, 107.8),
            P(213.9, 101.3), P(217.8, 108.0), P(220.8, 103.1), P(223.7, 108.0), P(226.6, 102.5), P(229.4, 107.9),
            P(234.3, 100.6), P(239.1, 107.6), P(243.8, 100.4), P(248.5, 106.9), P(252.7, 99.7), P(256.8, 106.6),
            P(259.8, 100.6), P(262.7, 105.9), P(267.8, 99.4), P(272.9, 104.9), P(277.5, 95.7), P(282.1, 101.9),
            P(287.1, 96.4), P(292.2, 102.4), P(295.9, 96.0), P(299.5, 100.9), P(304.2, 95.7), P(308.8, 101.9),
            P(313.4, 93.4), P(318.0, 97.9), P(322.9, 92.7), P(327.7, 101.3), P(332.8, 93.9), P(337.9, 100.9),
            P(341.5, 91.3), P(345.1, 98.2), P(350.1, 92.3), P(355.1, 100.0), P(360.2, 94.2), P(365.2, 99.7),
            P(368.7, 94.7), P(372.3, 101.3),
        ],
        end: P(388.0, 119.0)
    )

    static let frontTrees = TreeLine(
        start: P(-30.0, 121.0),
        firstBase: P(-10.0, 112.3),
        crowns: [
            P(-6.7, 106.2), P(-3.3, 111.0), P(0.3, 104.9), P(3.9, 111.6), P(6.4, 104.9), P(9.0, 111.5),
            P(11.5, 104.9), P(14.0, 109.7), P(16.3, 103.9), P(18.6, 110.0), P(21.1, 104.9), P(23.6, 110.5),
            P(26.5, 104.0), P(29.4, 108.7), P(32.6, 103.8), P(35.7, 111.1), P(38.3, 106.1), P(40.9, 110.7),
            P(44.6, 103.6), P(48.3, 108.6), P(51.8, 104.5), P(55.4, 108.8), P(58.8, 103.5), P(62.3, 108.7),
            P(65.8, 104.4), P(69.3, 110.9), P(72.9, 104.4), P(76.6, 110.7), P(80.0, 104.9), P(83.5, 111.0),
            P(86.4, 106.9), P(89.2, 111.8), P(92.1, 105.5), P(95.0, 112.2), P(97.3, 107.2), P(99.6, 111.7),
            P(103.1, 106.3), P(106.7, 112.1), P(110.0, 106.5), P(113.4, 113.2), P(116.8, 108.2), P(120.3, 114.0),
            P(123.6, 109.1), P(126.9, 114.1), P(129.3, 108.8), P(131.7, 114.4), P(134.8, 110.0), P(137.8, 114.7),
            P(140.7, 108.1), P(143.7, 114.8), P(146.5, 110.4), P(149.3, 114.9), P(152.3, 108.5), P(155.3, 115.0),
            P(157.8, 110.3), P(160.3, 115.0), P(163.1, 110.0), P(165.8, 115.0), P(169.1, 109.6), P(172.4, 114.8),
            P(175.2, 110.5), P(178.0, 114.6), P(181.8, 110.1), P(185.5, 114.5), P(187.9, 108.8), P(190.3, 113.9),
            P(193.9, 108.2), P(197.5, 113.5), P(199.9, 106.8), P(202.2, 113.4), P(205.9, 105.3), P(209.6, 112.3),
            P(213.1, 108.2), P(216.7, 112.7), P(220.3, 106.4), P(223.9, 112.0), P(227.3, 107.6), P(230.7, 112.1),
            P(234.6, 104.1), P(238.4, 110.5), P(241.8, 105.5), P(245.2, 111.2), P(248.4, 103.2), P(251.6, 109.8),
            P(254.8, 104.2), P(258.0, 110.3), P(261.4, 105.8), P(264.8, 110.2), P(267.4, 106.1), P(270.0, 110.6),
            P(273.4, 105.9), P(276.7, 110.8), P(279.2, 104.2), P(281.7, 111.0), P(285.0, 105.1), P(288.2, 109.6),
            P(291.3, 104.2), P(294.4, 111.3), P(297.3, 105.5), P(300.2, 110.6), P(302.4, 105.6), P(304.7, 111.7),
            P(308.6, 105.3), P(312.5, 111.8), P(315.1, 107.1), P(317.8, 111.7), P(321.0, 105.6), P(324.1, 112.5),
            P(327.1, 106.3), P(330.0, 112.3), P(333.6, 105.5), P(337.2, 113.3), P(339.9, 107.5), P(342.6, 113.0),
            P(346.5, 106.3), P(350.3, 113.5), P(353.3, 108.2), P(356.2, 113.8), P(358.9, 108.1), P(361.5, 114.4),
            P(364.5, 108.5), P(367.5, 114.4),
        ],
        end: P(388.0, 121.0)
    )

    /// Punto de caída: punto blanco y anillo.
    static let landing = P(262, 104)
    static let landingDotRadius: CGFloat = 3.69
    static let landingRingRadius: CGFloat = 6.97
    static let hairline: CGFloat = 0.984

    /// Etiqueta de palo y distancia, arriba a la derecha de la caída, unida a ella por una línea fina.
    static let label = CGRect(x: 273.48, y: 54.8, width: 75.44, height: 37.72)
    static let labelCornerRadius: CGFloat = 8.2
    static let labelPadding: CGFloat = 9.84
    /// Líneas base del palo y de la distancia, medidas desde arriba de la etiqueta.
    static let labelClubBaseline: CGFloat = 13.12
    static let labelDistanceBaseline: CGFloat = 31.16
    static let labelClubFontSize: CGFloat = 8.61
    static let labelDistanceFontSize: CGFloat = 18.86
    static let leaderEnd = P(273.48, 92.52)
}

/// Un cartel de distancia del campo de prácticas, con su poste.
struct DistanceBoard {
    let text: String
    let frame: CGRect
    let cornerRadius: CGFloat
    let postBottom: CGFloat
    let postWidth: CGFloat
    let fontSize: CGFloat
    let baseline: CGFloat
}

/// Una fila de árboles: sube desde fuera de la ventana y dibuja una copa con cada curva
/// (un punto de control y un punto final), hasta salir por la derecha.
struct TreeLine {
    let start: CGPoint
    let firstBase: CGPoint
    /// Parejas de puntos: control de la curva y final de la copa.
    let crowns: [CGPoint]
    let end: CGPoint
}

/// Abreviatura para que las listas de puntos se lean en una línea.
private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: y)
}
