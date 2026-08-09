import SwiftUI

struct NumericSlider: View {
    var title: String
    var systemImage: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    
    var appStorageKey: String
    var defaultValue: Double
    var viewModel: AppViewModel
    
    @Environment(\.undoManager) var undoManager
    @State private var initialValue: Double?
    
    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .frame(width: 100, alignment: .leading)
            
            Slider(value: $value, in: range) { editing in
                if editing {
                    initialValue = value
                } else {
                    if let old = initialValue, old != value {
                        viewModel.registerSliderUndo(undoManager: undoManager, key: appStorageKey, oldValue: old, newValue: value)
                    }
                }
            }
            
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 50)
                .disableAutocorrection(true)
            
            Text("pt").foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            let old = value
            if old != defaultValue {
                value = defaultValue
                viewModel.registerSliderUndo(undoManager: undoManager, key: appStorageKey, oldValue: old, newValue: defaultValue)
            }
        }
    }
}
