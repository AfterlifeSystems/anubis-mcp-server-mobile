import Contacts
import EventKit
import Foundation

/// Contacts, calendar, and reminders — permission-gated personal data tools.
enum PIMTools {
    static let eventStore = EKEventStore()

    static func all() -> [MCPTool] {
        [contactsSearch, calendarListEvents, calendarCreateEvent, remindersCreate]
    }

    static let contactsSearch = MCPTool(
        name: "contacts_search",
        description: "Search the user's contacts by name and return matching names, phone numbers, and emails.",
        inputSchema: Schema.object(["query": Schema.string("Name or partial name to search for")], required: ["query"])
    ) { args in
        guard let query = args["query"] as? String else { throw ToolError("Missing 'query' argument") }
        let store = CNContactStore()
        let granted = try await store.requestAccess(for: .contacts)
        guard granted else { throw ToolError("Contacts permission denied") }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
        ] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: query)
        let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
        let results: [[String: Any]] = contacts.map { contact in
            [
                "name": "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces),
                "phones": contact.phoneNumbers.map { $0.value.stringValue },
                "emails": contact.emailAddresses.map { $0.value as String },
            ]
        }
        return [.text(JSON.encodeString(["contacts": results]))]
    }

    static let calendarListEvents = MCPTool(
        name: "calendar_list_events",
        description: "List calendar events from now through the next N days (default 7).",
        inputSchema: Schema.object(["days": Schema.integer("How many days ahead to include (default 7)")])
    ) { args in
        try await requestCalendarAccess()
        let days = (args["days"] as? Int) ?? 7
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: max(1, days), to: start)!
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)
        let results: [[String: Any]] = events.map { event in
            [
                "title": event.title ?? "(untitled)",
                "start": event.startDate.isoString,
                "end": event.endDate.isoString,
                "all_day": event.isAllDay,
                "location": event.location ?? "",
                "calendar": event.calendar.title,
            ]
        }
        return [.text(JSON.encodeString(["events": results]))]
    }

    static let calendarCreateEvent = MCPTool(
        name: "calendar_create_event",
        description: "Create a calendar event with a title, ISO-8601 start time, and duration in minutes.",
        inputSchema: Schema.object(
            [
                "title": Schema.string("Event title"),
                "start": Schema.string("Start time, ISO-8601 (e.g. 2026-08-05T18:30:00Z)"),
                "duration_minutes": Schema.integer("Duration in minutes (default 60)"),
                "notes": Schema.string("Optional notes"),
                "location": Schema.string("Optional location"),
            ],
            required: ["title", "start"]
        )
    ) { args in
        guard let title = args["title"] as? String,
              let startString = args["start"] as? String,
              let start = startString.parsedISODate
        else { throw ToolError("Missing 'title' or valid ISO-8601 'start'") }
        try await requestCalendarAccess()

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        let minutes = (args["duration_minutes"] as? Int) ?? 60
        event.endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
        event.notes = args["notes"] as? String
        event.location = args["location"] as? String
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent, commit: true)
        return [.text(JSON.encodeString([
            "ok": true,
            "event_id": event.eventIdentifier ?? "",
            "start": event.startDate.isoString,
            "end": event.endDate.isoString,
        ]))]
    }

    static let remindersCreate = MCPTool(
        name: "reminders_create",
        description: "Create a reminder with a title and optional ISO-8601 due time.",
        inputSchema: Schema.object(
            [
                "title": Schema.string("Reminder title"),
                "due": Schema.string("Optional due time, ISO-8601"),
                "notes": Schema.string("Optional notes"),
            ],
            required: ["title"]
        )
    ) { args in
        guard let title = args["title"] as? String else { throw ToolError("Missing 'title' argument") }
        let granted = try await eventStore.requestFullAccessToReminders()
        guard granted else { throw ToolError("Reminders permission denied") }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = args["notes"] as? String
        if let dueString = args["due"] as? String, let due = dueString.parsedISODate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
        }
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        try eventStore.save(reminder, commit: true)
        return [.text(JSON.encodeString(["ok": true]))]
    }

    private static func requestCalendarAccess() async throws {
        let granted = try await eventStore.requestFullAccessToEvents()
        guard granted else { throw ToolError("Calendar permission denied") }
    }
}
