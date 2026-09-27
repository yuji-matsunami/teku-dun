// Package walk contains the walk event domain model and use cases.
package walk

import "time"

// Session identifies one walk and its start instant.
type Session struct {
	ID            string
	StartDatetime time.Time
}

// Location is a location sample recorded during a session.
type Location struct {
	ID         string
	SessionID  string
	RecordedAt time.Time
	Latitude   float64
	Longitude  float64
	AccuracyM  float64
}

// Steps is the step count for one fixed interval in a session.
type Steps struct {
	ID            string
	SessionID     string
	StartDatetime time.Time
	EndDatetime   time.Time
	Steps         int32
	Revision      int64
}
