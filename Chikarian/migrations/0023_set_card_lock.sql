-- ============================================================
-- Chikarian migration 0023: set_card_lock（カードのロック切替RPC）
-- 目的: カード詳細の「ロック切替」を専用RPC経由で行う（cards を直接UPDATEさせない）。
--       資産は動かないが、RLS/不正対策C に合わせて全書込みをRPC化（クライアントは get* のみ）。
-- 規約: 他RPC（0021 等）に合わせる＝security definer / set search_path = public, pg_temp /
--       auth.uid() 認証 / 自分の所有カードのみ / revoke from public,anon・grant authenticated。
-- ============================================================

create or replace function public.set_card_lock(
  p_card_id uuid,
  p_locked  boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  -- 自分の所有カードのみ更新（RLSはdefiner下でbypassされるため WHERE で所有を担保）
  update public.cards
     set locked = p_locked
   where id = p_card_id and user_id = v_uid;

  if not found then
    raise exception 'CARD_NOT_FOUND';
  end if;

  return jsonb_build_object('card_id', p_card_id, 'locked', p_locked);
end;
$$;

revoke all on function public.set_card_lock(uuid, boolean) from public, anon;
grant execute on function public.set_card_lock(uuid, boolean) to authenticated;
