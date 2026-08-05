import SwiftUI

/// First-launch welcome + permission priming. It explains *why* Firmament needs
/// camera, location, and motion before the system prompts appear, so the user
/// grants them in context instead of being ambushed. Shown once (an
/// `@AppStorage` flag), and after "Begin" the caller starts the sensors, which
/// triggers the real system dialogs.
///
/// © Ankur Sinha.
struct OnboardingView: View {
    let onBegin: () -> Void

    private let rows: [(icon: String, title: String, body: String)] = [
        ("camera.fill", "Camera",
         "To show the live sky and capture long-exposure night photos."),
        ("location.fill", "Location",
         "To compute exactly where each star, planet and satellite is in your sky."),
        ("gyroscope", "Motion",
         "To know where your phone is pointing — and when it's steady on a tripod."),
    ]

    var body: some View {
        ZStack {
            // Calm night backdrop, echoing the app icon.
            LinearGradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.09),
                                    Color(red: 0.10, green: 0.17, blue: 0.33)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                    Text("Firmament")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Point your phone at the real sky and understand it. Then capture it.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 14) {
                    ForEach(rows, id: \.title) { row in
                        HStack(spacing: 14) {
                            Image(systemName: row.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(.cyan)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(row.body)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                        }
                    }
                }
                .padding(20)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 24)

                Text("Everything runs on your device. Your location and photos never leave the phone.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                Spacer()

                Button(action: onBegin) {
                    Text("Begin")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.black)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}
