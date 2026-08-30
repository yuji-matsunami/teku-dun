-- The pinned development image initializes PostGIS and companion extensions
-- before repository migrations run. This migration verifies that PostGIS is
-- available but does not own the image-managed extension, so rollback must not
-- drop it (or its dependent postgis_topology/postgis_tiger_geocoder extensions).
SELECT 1;
