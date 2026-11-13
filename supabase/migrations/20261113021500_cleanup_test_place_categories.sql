-- GPS-FMRA — ONE-SHOT cleanup: categorías de prueba (Prueba* / Directing* / DirectIns*)
-- Safe: solo filas created_by = auth.uid() (sesión del editor) O nombres exactos de test.
-- named_places.category_id → NULL antes de borrar (FK on delete set null también aplica).
--
-- Si el worker ya limpió vía API: puede no borrar nada (ok).
-- Wilson: ejecutar en Supabase SQL Editor SOLO si aún ves Prueba*/DirectIns* en la app.
-- Éxito: cleanup_test_place_categories_ok = true

begin;

-- 1) Desvincular lugares de categorías de prueba (propias + nombres test)
update public.named_places np
set category_id = null
where np.category_id in (
  select c.id
  from public.place_categories c
  where (
      c.created_by = auth.uid()
      and (
        lower(c.name) like 'prueba%'
        or lower(c.name) like 'directing%'
        or lower(c.name) like 'directins%'
      )
    )
    or c.name in ('PruebaCat9857', 'DirectIns5916')
);

-- 2) Borrar categorías de prueba
delete from public.place_categories c
where (
    c.created_by = auth.uid()
    and (
      lower(c.name) like 'prueba%'
      or lower(c.name) like 'directing%'
      or lower(c.name) like 'directins%'
    )
  )
  or c.name in ('PruebaCat9857', 'DirectIns5916');

commit;

select
  not exists (
    select 1
    from public.place_categories c
    where lower(c.name) like 'prueba%'
       or lower(c.name) like 'directing%'
       or lower(c.name) like 'directins%'
       or c.name in ('PruebaCat9857', 'DirectIns5916')
  ) as cleanup_test_place_categories_ok;
