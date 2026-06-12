# チカリアン Supabase設計スペック（2026-06-12）
> 本実装（SPA＋Supabase）のDB・RPC設計。設計スレッド（2026-06-12）で確定。
> 数値・式の正＝balance-chikarian-2026-06-12.md。用語＝hikitsugi §2。絶対固定は「90日8面」「デッキ3枚」のみ・他は仮。

## 0. 方針【確定】
- **不正対策＝C（折衷）**：資産が動く処理（採取・ガチャ・戦闘・強化・錬成・転移・練成・充填・報酬）は**全てサーバRPC**。クライアントに残すのは画面・演出・編成プレビュー表示・**修練場**（報酬ゼロ＝改竄しても得るものがない唯一のローカル戦闘計算）のみ。改竄対策は最優先（ユーザー確定方針）。
- **時刻原則**：時刻は全て**サーバ絶対時刻（timestamptz/date）で保存**。残り時間は保存しない。現在値は読むたびRPC内で計算（オフライン進行・チート耐性・0時リセットを同一機構で実現）。
- **0時リセット原則**：日次系（採取上限・ボス3回・SP復帰・デイリー）は「最終リセット日(date)」を行に持ち、アクセス時にRPC内で「保存日付＜今日→リセット」。cron不使用。JST基準。
- **RLS**：全テーブルRLS有効。クライアントは自分の行のSELECTのみ。書き込みは全て security definer のRPC経由（直接INSERT/UPDATE/DELETE禁止）。

## 1. テーブル（11本）※チャット設計の8本に decks／tansaku_states／zukan を追加
1. **profiles**（auth.usersと1:1）：id(=auth.uid)／chikarium・medal／crystal_blue・red・rainbow／hoshou_stone（確率保証石）／exp_book_s・m・l（経験の書）／saishu_today＋saishu_date（日次1000）／boss_count_today＋boss_date（1日3回）／cleared_stage 0-8（所持枠=300+100×値・最大1100）／created_at
2. **cards**：id／user_id／card_key（41種・cards.md準拠）／lv・exp・star／quality（crude/refined/enchanted/holy・SPはnull）／loaded_buki（込めた武気・§9損失で減る）／locked／obtained_at
3. **card_skills**：card_id／slot（0=固定・1・2=空き）／skill_key（SP専用3種含む）／skill_lv。PK=(card_id,slot)。固定スキル抽選結果もここ。転移＝行移動＋素材カード削除
4. **decks**：user_id／deck_no／slot1/2/3_card_id。PK=(user_id,deck_no)
5. **tansaku_states**：user_id／deck_no／area・depth（浅2/中5/深10メダル/分・EXP0.5/1.2/2.5）／last_collect_at（蓄積上限なし＝経過分×レート）／is_houchi（放置=1面浅域自動）
6. **renkiden**（user1行）：lv（レート0.1×Lv/秒・保管上限1000+1500×(Lv-1)）／buki_stored（武気プール）／fuel_medal（投資中残メダル・単価5）／last_calc_at
7. **kajiya_orders**：user_id／quality／done_at（精製24h/魔装36h/聖装48h）／claimed。鍛冶屋Lv＝claimed済み最大質から導出（粗製=初期）。未claimed行があれば新規依頼拒否（1件ずつ）
8. **sp_states**：card_id PK／unavailable_until(date)（SP発動日離脱・翌0時復帰。編成/探索/出撃の検証に使用）
9. **battle_logs**（追記のみ）：user_id／boss_key／win／deck・fired_skills・rewards(jsonb)／loss_rate／fought_at
10. **missions**：user_id／mission_key／period_start（デイリー=日付・週=週初・達成=固定）／progress／claimed。PK=3列
11. **zukan**：user_id／card_key／first_at。PK=(user_id,card_key)。図鑑収集ミッション（10/20/30/41種）の判定用＝カード消滅後も残る

## 2. RPC一覧（資産が動く処理＝全部ここ・乱数/判定/増減はサーバ内）
- claim_saishu(n)：+10刻み・日次1000上限・0時リセット・頻度制限
- do_gacha()：300チカリウム→6枚抽選（N53.8/R30/SR9/SP5/SSR2.2・帯内母数cards§4）＋固定スキル抽選→cards/card_skills/zukan挿入・所持枠検証
- do_boss_battle(deck_no, boss_key)：1日3回検証→実戦闘力（三すくみ・スキル/SP抽選）→勝敗→損失clamp(0.5R,0.10,1.00)→SP発動日離脱記録→報酬→battle_logs
- do_kyoka(base_id, mat_id, hoshou_n)：同レア同★（SPは同名同★）・ロック検証→成功率max(30,90−5★)+10×保証石→素材消滅→★+1
- do_skill_rensei(card_id, slot, color)：クリスタルC個消費（カーブ×レア倍率N1/R2/SR4）→青10/赤33/虹100%→成功Lv+1/失敗据置
- do_skill_teni(src_id, src_slot, dst_id, dst_slot)：メダル3,000→スキル行移動→素材カード削除（固定スロット不可侵・SP対象外）
- invest_renkiden(medal)／collect_renkiden()／instant_renkiden(n)：投資受付／時刻計算で確定（上限クランプ）／即生産（武気1=メダル15）
- upgrade_renkiden()：8,000×Lv
- place_kajiya_order(quality)／claim_kajiya(id)：順序・1件ずつ・15,000×Lv検証／done_at経過検証→解放
- equip_buki(card_id, quality, amount)：解放済み質・min(枠, プール÷コスト)をサーバ計算・プール⇄カード移動
- update_deck(deck_no, slots)：所持・SP離脱中でない・重複なしを検証
- start_tansaku(deck_no, area, depth)／collect_tansaku(deck_no)：探索開始／経過分×レート回収（メダル＋カードEXP）
- use_exp_book(card_id, size)：経験の書消費→EXP加算→Lv上限クランプ
- claim_mission(mission_key)：period判定・進捗検証→報酬付与

## 3. クライアントに残るもの
画面・演出・編成プレビューの戦力表示・修練場（カカシ＝報酬なし→ローカル計算で安全）。

## 4. 採取の限界と守り【確定】
カメラ検出の申告自体はブラウザ発＝原理的に完全防御不可。サーバ防御＝日次1000上限・+10刻み・頻度制限（claim_saishuに織込み）。上限がある限り偽装の実害は小。

## 5. 未確定（次スレッドで）
- 確率保証石の供給源（ミッション/ボス報酬への割付・mission-specに未記載）
- 認証方式（匿名 or メール）／複数デッキの本数上限／探索エリアの面別解放条件

## 6. Supabase状態と次の作業
プロジェクト**作成済み**（2026-06-12・無料プラン）。URL/anonキー/DBパスワードはユーザーがローカル保管（チャット・repoに貼らない。anonは公開可・DBパスワードとservice_roleは絶対秘匿）。
次の順：①マイグレーションSQL指示書（テーブル11本＋RLS）→SQL Editorで実行 ②認証方針→導入 ③RPC実装（profiles初期化→採取→ガチャ→編成→戦闘の順）④SPA化→GitHub Pages接続。
