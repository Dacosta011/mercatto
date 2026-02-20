-- Añade soporte de rerolls al sistema
alter table tournaments
  add column if not exists rerolls_allowed integer not null default 1;

alter table members
  add column if not exists rerolls_used integer not null default 0;

-- El presupuesto pertenece al participante (member), no al equipo
alter table members
  add column if not exists budget bigint;
