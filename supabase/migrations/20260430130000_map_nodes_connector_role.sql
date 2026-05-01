-- Rol semántico de nodos conectores (escaleras / ascensores).
-- 'exit'  = el avatar camina HASTA aquí para abandonar el piso actual.
-- 'entry' = el avatar APARECE aquí al llegar desde otro piso.
-- 'both'  = nodo bidireccional (escalera fija, ascensor).
-- NULL    = nodo sin rol de conector (pasillo, tienda, kiosco).
ALTER TABLE public.map_nodes
  ADD COLUMN IF NOT EXISTS connector_role text
  CHECK (connector_role IN ('exit', 'entry', 'both'));

-- UUID del nodo par en el piso destino.
-- Un nodo 'exit' en piso A apunta al nodo 'entry' en piso B y viceversa.
-- Permite a la app colocar al avatar exactamente en la entrada correcta
-- sin depender sólo del A* para inferir el punto de llegada.
ALTER TABLE public.map_nodes
  ADD COLUMN IF NOT EXISTS paired_node_id uuid
  REFERENCES public.map_nodes(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.map_nodes.connector_role IS
  'exit=sale del piso, entry=llega al piso, both=bidireccional, NULL=no es conector';
COMMENT ON COLUMN public.map_nodes.paired_node_id IS
  'Nodo par en el piso destino: el exit de piso A apunta al entry de piso B';
