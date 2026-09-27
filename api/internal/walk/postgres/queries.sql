-- name: GetSessionForUpdate :one
SELECT id, start_datetime
FROM walk_sessions
WHERE id = $1
FOR UPDATE;

-- name: InsertSession :exec
INSERT INTO walk_sessions (id, start_datetime)
VALUES ($1, $2)
ON CONFLICT (id) DO NOTHING;

-- name: GetLocationForUpdate :one
SELECT
    id,
    session_id,
    recorded_at,
    ST_Y(position::geometry)::double precision AS latitude,
    ST_X(position::geometry)::double precision AS longitude,
    accuracy_m
FROM location_events
WHERE id = $1
FOR UPDATE;

-- name: InsertLocation :exec
INSERT INTO location_events (
    id,
    session_id,
    recorded_at,
    position,
    accuracy_m
)
VALUES (
    sqlc.arg(id),
    sqlc.arg(session_id),
    sqlc.arg(recorded_at),
    ST_SetSRID(
        ST_MakePoint(
            sqlc.arg(longitude)::double precision,
            sqlc.arg(latitude)::double precision
        ),
        4326
    )::geography,
    sqlc.arg(accuracy_m)
)
ON CONFLICT (id) DO NOTHING;

-- name: GetStepsByIDForUpdate :one
SELECT id, session_id, start_datetime, end_datetime, steps, revision
FROM step_events
WHERE id = $1
FOR UPDATE;

-- name: GetStepsByIntervalForUpdate :one
SELECT id, session_id, start_datetime, end_datetime, steps, revision
FROM step_events
WHERE session_id = $1 AND start_datetime = $2
FOR UPDATE;

-- name: InsertSteps :execrows
INSERT INTO step_events (
    id,
    session_id,
    start_datetime,
    end_datetime,
    steps,
    revision
)
VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT DO NOTHING;

-- name: UpdateSteps :exec
UPDATE step_events
SET steps = $2,
    revision = $3,
    last_received_at = clock_timestamp()
WHERE id = $1;
