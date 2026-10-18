// Package walkは、散歩イベントのドメインモデルとユースケースを提供する。
package walk

import "time"

// Sessionは、1回の散歩とその開始時刻を表す。
type Session struct {
	ID            string
	StartDatetime time.Time
}

// Locationは、散歩中に記録した1件の位置情報を表す。
type Location struct {
	ID         string
	SessionID  string
	RecordedAt time.Time
	Latitude   float64
	Longitude  float64
	AccuracyM  float64
}

// Stepsは、散歩中の1つの固定区間における歩数を表す。
type Steps struct {
	ID            string
	SessionID     string
	StartDatetime time.Time
	EndDatetime   time.Time
	Steps         int32
	Revision      int64
}
