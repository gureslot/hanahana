# Claude Code 指示書：⑤ 出撃画面（ボス）に「空にする」を追加

対象：`Chikarian/index.html`。HEAD 基準。
目的：出撃画面の各デッキ行にある「⚡最大充填」の隣に「空にする」を追加（デッキ全カードの武気をプールへ返却＝loaded_buki=0）。既存の「最大充填」(maxFillDeck) と同方式で、`emptyDeck(n)` を新設。
方針：**追加のみ**。BossScreen のみ（③/④の DeckScreen には未接触）。連打防止に `emptyingDeck` を新設し、最大充填と相互排他（両ボタンとも処理中は無効）。SP はスキップ。武気返却は `equipBuki(id, quality, 0)`。
編集3箇所、すべて文字列アンカー一致。構文は Babel(JSX) 検証済み。

---

## 編集1：emptyingDeck state を追加（fillingDeck の直後）

【検索（厳密一致）】
```
  const [fillingDeck, setFillingDeck] = useState(null);                // 最大充填 処理中のデッキ番号（連打防止）
```
【置換】
```
  const [fillingDeck, setFillingDeck] = useState(null);                // 最大充填 処理中のデッキ番号（連打防止）
  const [emptyingDeck, setEmptyingDeck] = useState(null);              // 空にする 処理中のデッキ番号（連打防止）
```

---

## 編集2：emptyDeck 関数を追加（maxFillDeck の直後・live phase コメントの前）

【検索（厳密一致・複数行）】
```
    } finally { setFillingDeck(null); }
  }

  // 各デッキの live phase（毎秒再計算）
```
【置換】
```
    } finally { setFillingDeck(null); }
  }

  // 空にする：当該デッキの全カードの武気を解除（loaded_buki=0）→プールへ返却。SPはスキップ。
  async function emptyDeck(n) {
    if (fillingDeck !== null || emptyingDeck !== null) return; setEmptyingDeck(n);
    let totalEmptied = 0;
    try {
      for (const c of deckMembers(n).filter(Boolean)) {
        if (/_sp$/.test(c.card_key || '')) continue;                  // SP＝武気を持たない
        const before = c.loaded_buki || 0;
        if (before <= 0) continue;
        try {
          await ChikarianAPI.equipBuki(c.id, c.quality || 'crude', 0);   // 0=空（武気はプールへ返却）
          totalEmptied += before;
        } catch (e) { /* 個別失敗は継続（最終判定はサーバ） */ }
      }
      try { await onRefresh(); } catch (e) {}                         // cards 再取得（loaded_buki 表示更新）
      let remaining = null;
      try { const rk = normalizeRk(await ChikarianAPI.getRenkiden()); remaining = rk ? rk.buki : null; } catch (e) {}
      if (totalEmptied > 0) flash(`武気を ${totalEmptied.toLocaleString()} 枠 解除しました` + (remaining != null ? `（練気殿 残り ${Number(remaining).toLocaleString()}）` : ''));
      else flash('解除する武気がありません');
    } finally { setEmptyingDeck(null); }
  }

  // 各デッキの live phase（毎秒再計算）
```

---

## 編集3：「最大充填」ボタンに emptyingDeck を反映＋「空にする」ボタンを追加

「最大充填」ボタン（1行）を、emptyingDeck も無効条件に含めた版＋直後に「空にする」ボタンを足した版に置換する。

【検索（厳密一致・1行のうちの該当ボタン）】
```
<button onClick={(e) => { e.stopPropagation(); maxFillDeck(n); }} disabled={blocked || fillingDeck !== null} style={{ marginLeft: 6, fontFamily: 'inherit', fontSize: 10, fontWeight: 800, color: (blocked || fillingDeck !== null) ? '#7a6a8a' : '#bfe3ff', background: 'rgba(40,60,80,.6)', border: '1px solid rgba(120,200,255,.45)', borderRadius: 8, padding: '2px 8px', cursor: (blocked || fillingDeck !== null) ? 'default' : 'pointer' }}>{fillingDeck === n ? '充填中…' : '⚡ 最大充填'}</button>
```
【置換】
```
<button onClick={(e) => { e.stopPropagation(); maxFillDeck(n); }} disabled={blocked || fillingDeck !== null || emptyingDeck !== null} style={{ marginLeft: 6, fontFamily: 'inherit', fontSize: 10, fontWeight: 800, color: (blocked || fillingDeck !== null || emptyingDeck !== null) ? '#7a6a8a' : '#bfe3ff', background: 'rgba(40,60,80,.6)', border: '1px solid rgba(120,200,255,.45)', borderRadius: 8, padding: '2px 8px', cursor: (blocked || fillingDeck !== null || emptyingDeck !== null) ? 'default' : 'pointer' }}>{fillingDeck === n ? '充填中…' : '⚡ 最大充填'}</button><button onClick={(e) => { e.stopPropagation(); emptyDeck(n); }} disabled={blocked || fillingDeck !== null || emptyingDeck !== null} style={{ marginLeft: 6, fontFamily: 'inherit', fontSize: 10, fontWeight: 800, color: (blocked || fillingDeck !== null || emptyingDeck !== null) ? '#7a6a8a' : '#ffc7b0', background: 'rgba(70,40,30,.6)', border: '1px solid rgba(255,150,110,.45)', borderRadius: 8, padding: '2px 8px', cursor: (blocked || fillingDeck !== null || emptyingDeck !== null) ? 'default' : 'pointer' }}>{emptyingDeck === n ? '解除中…' : '空にする'}</button>
```

---

## 確認事項
- `deckMembers` `onRefresh` `normalizeRk` `ChikarianAPI.equipBuki/getRenkiden` `flash` は既存（maxFillDeck と同じものを使用）。新規 import 不要。
- 最大充填と空にするは相互排他（片方処理中は両方とも無効・連打防止）。SPカードはスキップ。
- 武気は `equipBuki(id,quality,0)` でプール(renkiden.buki_stored)へ返却される（サーバ側で返却処理）。0050(A-2) と整合：外す＝自動返却、空にする＝構成を残して一括返却。
- 適用後 commit & push → Ctrl+Shift+R。出撃画面の各デッキ行で「✎ 編成 / ⚡最大充填 / 空にする」を確認。空にする→武気が解除されプール残が増える。
