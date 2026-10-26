import GolfCore
import SwiftUI

/// Pantalla de prueba de la etapa 0: comprueba que la fuente Archivo, la versión y la fecha
/// de compilación llegan bien al iPhone. En la etapa 1 se sustituye por el Inicio de la maqueta.
struct HomeView: View {
    var body: some View {
        VStack(spacing: Spacing.s) {
            Text("Trazo")
                .font(Typography.marca)
                .foregroundStyle(Color.pino)

            VStack(spacing: Spacing.xs) {
                Text(BuildLabel.version(BuildInfo.version, build: BuildInfo.build))
                Text(dateLine)
            }
            .font(Typography.sub)
            .foregroundStyle(Color.texto2)

            // Si la fuente no se cargó, se dice claro en vez de enseñar otra fuente sin avisar.
            if !Typography.isArchivoAvailable {
                Text("No se ha cargado la fuente Archivo")
                    .font(Typography.sub)
                    .foregroundStyle(Color.pino)
                    .padding(.top, Spacing.l)
            }
        }
        .multilineTextAlignment(.center)
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bola)
    }

    private var dateLine: String {
        guard let date = BuildInfo.date else { return "Sin fecha de compilación" }
        return "Compilada el \(BuildLabel.date(date))"
    }
}

#Preview {
    HomeView()
}
