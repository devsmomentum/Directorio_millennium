-- Soporte para conectores one-way (escaleras mecánicas, rampas direccionales).
-- Las aristas existentes siguen siendo bidireccionales (default false).
-- Para una escalera mecánica que SÓLO sube de A→B, marcar la fila como
-- directional=true: el pathfinder no la transitará en sentido B→A.
ALTER TABLE public.map_edges
  ADD COLUMN IF NOT EXISTS directional boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.map_edges.directional IS
  'true = arista válida sólo node_a_id → node_b_id (escaleras mecánicas, rampas one-way). '
  'false = bidireccional (pasillos, ascensores, escaleras fijas).';
