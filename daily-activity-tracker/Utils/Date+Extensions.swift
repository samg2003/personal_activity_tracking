import Foundation

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// ISO weekday: 1=Mon..7=Sun
    var weekdayISO: Int {
        let wd = Calendar.current.component(.weekday, from: self) // 1=Sun..7=Sat
        return wd == 1 ? 7 : wd - 1
    }

    var dayOfMonth: Int {
        Calendar.current.component(.day, from: self)
    }

    var currentHour: Int {
        Calendar.current.component(.hour, from: self)
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    var shortDisplay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: self)
    }

    var shortWeekday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: self)
    }

    var shortMonthDay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }
}
