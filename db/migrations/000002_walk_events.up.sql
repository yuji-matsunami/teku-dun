CREATE TABLE walk_sessions (
    id UUID PRIMARY KEY,
    start_datetime TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE location_events (
    id UUID PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES walk_sessions (id),
    recorded_at TIMESTAMPTZ NOT NULL,
    position GEOGRAPHY(Point, 4326) NOT NULL,
    accuracy_m DOUBLE PRECISION NOT NULL CHECK (accuracy_m >= 0),
    received_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX location_events_session_recorded_at_idx
    ON location_events (session_id, recorded_at);

CREATE INDEX location_events_position_gist_idx
    ON location_events USING GIST (position);

CREATE TABLE step_events (
    id UUID PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES walk_sessions (id),
    start_datetime TIMESTAMPTZ NOT NULL,
    end_datetime TIMESTAMPTZ NOT NULL,
    steps INTEGER NOT NULL CHECK (steps >= 0),
    revision BIGINT NOT NULL CHECK (revision >= 1),
    first_received_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    last_received_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (session_id, start_datetime),
    CHECK (end_datetime > start_datetime),
    CHECK (end_datetime <= start_datetime + INTERVAL '1 minute')
);
