import Foundation

let formatter = RelativeDateTimeFormatter()
formatter.unitsStyle = .abbreviated
print(formatter.localizedString(for: Date(), relativeTo: Date()))
print(formatter.localizedString(for: Date().addingTimeInterval(1), relativeTo: Date()))
print(formatter.localizedString(for: Date().addingTimeInterval(-1), relativeTo: Date()))
