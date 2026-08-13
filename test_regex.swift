import Foundation

let text = """
00:00 Movement 1
05:30 Movement 2
1:05:30 Movement 3
  15:30   Movement with spaces  
"""

let lines = text.components(separatedBy: .newlines)
guard let regex = try? NSRegularExpression(pattern: "^(?:(\\d{1,2}):)?(\\d{1,2}):(\\d{2})\\s+(.+)$") else { fatalError() }

for line in lines {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { continue }
    
    if let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) {
        let nsString = trimmed as NSString
        var hours = 0.0, minutes = 0.0, seconds = 0.0
        
        let range1 = match.range(at: 1)
        let range2 = match.range(at: 2)
        let range3 = match.range(at: 3)
        let titleRange = match.range(at: 4)
        
        if range1.location != NSNotFound {
            hours = Double(nsString.substring(with: range1)) ?? 0.0
            minutes = Double(nsString.substring(with: range2)) ?? 0.0
        } else {
            minutes = Double(nsString.substring(with: range2)) ?? 0.0
        }
        seconds = Double(nsString.substring(with: range3)) ?? 0.0
        
        let title = nsString.substring(with: titleRange).trimmingCharacters(in: .whitespaces)
        let totalSeconds = (hours * 3600) + (minutes * 60) + seconds
        
        print("\(totalSeconds)s : \(title)")
    } else {
        print("NO MATCH: \(trimmed)")
    }
}
