import SwiftUI

struct NumericSlider: View {
    var title: String
    var systemImage: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    
    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .frame(width: 100, alignment: .leading)
            
            Slider(value: $value, in: range)
            
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 50)
                .disableAutocorrection(true)
            
            Text("pt").foregroundColor(.secondary)
        }
    }
}
