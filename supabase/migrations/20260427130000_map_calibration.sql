CREATE TABLE IF NOT EXISTS public.map_calibration (
  floor_code text PRIMARY KEY,
  scale double precision DEFAULT 1.0,
  ox double precision DEFAULT 0.0,
  oy double precision DEFAULT 0.0,
  oz double precision DEFAULT 0.0,
  rot_y double precision DEFAULT 0.0,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
