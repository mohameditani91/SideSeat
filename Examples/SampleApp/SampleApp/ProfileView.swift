import SwiftUI
import SideSeat

final class ProfileHostingController: UIHostingController<ProfileView> {
    init() {
        super.init(rootView: ProfileView())
    }

    @MainActor required dynamic init?(coder: NSCoder) { nil }
}

struct ProfileView: View {

    @State private var name = "Alex Doe"
    @State private var pin = ""
    @State private var newsletter = true
    @State private var plan = "Basic"
    @State private var likes = 0

    var body: some View {
        NavigationView {
            Form {
                Section("Account") {
                    TextField("Name", text: $name)
                    SecureField("PIN", text: $pin)
                    Toggle("Newsletter", isOn: $newsletter)
                    Picker("Plan", selection: $plan) {
                        ForEach(["Basic", "Plus", "Pro"], id: \.self, content: Text.init)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Gesture-driven card") {
                    HStack {
                        Image(systemName: "hand.thumbsup.fill")
                        Text("Liked \(likes) times")
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { likes += 1 }
                    .sideSeatTarget { likes += 1 }
                }

                Section("Private") {
                    Text("Card on file: 4242 4242 4242 4242")
                        .sideSeatMasked()
                }

                Section("History") {
                    ForEach(1...30, id: \.self) { visit in
                        Text("Visit \(visit)")
                    }
                }
            }
            .navigationTitle("Profile")
        }
        .navigationViewStyle(.stack)
    }
}
