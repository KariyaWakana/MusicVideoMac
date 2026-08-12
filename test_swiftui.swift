import SwiftUI

struct TestView: View {
    var body: some View {
        Text("Hello")
            .importsItemProviders([.image]) { providers in
                return true
            }
    }
}
print("Compiles fine.")
