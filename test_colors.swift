import Foundation

// Let's verify dictionary updating
var discBgColors: [String: [Double]] = [:]

func setDiscColor(disc: String, rgb: Int, val: Double, isBg: Bool) {
    if isBg {
        var colorArr = discBgColors[disc] ?? [0.2, 0.2, 0.2]
        colorArr[rgb] = val
        discBgColors[disc] = colorArr
    }
}

setDiscColor(disc: "1", rgb: 0, val: 0.8, isBg: true)
print(discBgColors["1"]!)
