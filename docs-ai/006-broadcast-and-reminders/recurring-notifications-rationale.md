# iOS Recurring Local Notifications Q&A

Updated: 2026-08-14

## Can AniShelf cancel one occurrence while preserving the rest of a recurrence?

No. A repeating `UNCalendarNotificationTrigger` belongs to one
`UNNotificationRequest`. Future occurrences are not exposed as separately
identifiable pending requests.

Calling `removePendingNotificationRequests(withIdentifiers:)` with that
request's identifier cancels the entire remaining recurrence. Notifications
that were already delivered remain in Notification Center unless the app
removes them separately.

To make individual occurrences cancellable, AniShelf must calculate them and
register each one as a nonrepeating request with a unique identifier, for
example:

```text
broadcast.<entry-id>.2026-08-21T14:30Z
broadcast.<entry-id>.2026-08-28T14:30Z
broadcast.<entry-id>.2026-09-04T14:30Z
```

Removing one identifier then leaves the other pending requests intact.

## Can a native recurring notification have a start or stop date?

No. `UNCalendarNotificationTrigger` accepts matching date components and a
`repeats` flag, but it has no separate start-date or end-date boundary.

AniShelf could add a repeating request when a schedule starts and remove it
when the schedule ends, but that depends on the app receiving an execution
opportunity at both boundaries. It is not reliable when the app is not running.

For bounded schedules, AniShelf should instead:

1. Persist the intended schedule boundaries in its own feature state.
2. Calculate concrete occurrences within those boundaries.
3. Register each occurrence as a nonrepeating notification request.
4. Maintain a rolling window of future requests and replenish it when the app
   gets an opportunity to run.
5. Remove requests that become invalid when provider data or user settings
   change.

## Recommendation for broadcast notifications

Use individually scheduled notifications for verified TVMaze `airstamp`
occurrences. This supports skipped weeks, corrections, individual cancellation,
and bounded schedules without pretending that a weekly recurrence is always
valid.

A native repeating trigger is appropriate only if AniShelf later offers a
separate, intentionally indefinite generic weekly reminder. It should not be
used as an episode-aware next-airing notification.

## Apple documentation

- [Scheduling a notification locally from your
  app](https://developer.apple.com/documentation/UserNotifications/scheduling-a-notification-locally-from-your-app)
- [`UNCalendarNotificationTrigger`](https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger)
- [`removePendingNotificationRequests(withIdentifiers:)`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removependingnotificationrequests%28withidentifiers%3A%29)
