# ボス 面内ノード順次解放（クライアント・index.html・1編集）

対象: `Chikarian/index.html`。SQL `0054_boss_node_sequential.sql` 適用とセットで動作します。
（サーバが順次クリアを強制し、本編集はその状態をマップ上でロック表示します。）

検索文字列は全体で1回だけ出現します。文字列アンカー一致で置換してください。

## 編集：BossScreen ノード描画にロック判定を追加

**検索:**
```jsx
        {curStage.bosses.map((b, i) => {
          const pos = BOSS_NODES[i];
          const role = BOSS_ROLE_KEYS[i];
          const pinSrc = i < 2 ? './images/ic_map_subboss.png' : './images/ic_map_boss.png';   // ピン＝汎用アイコン（ボス絵は報告書で使う）
          const nodeBusy = !!busyRoleOnStage[role];
          return (
            <div key={i} className={'boss-node' + (pos.up ? ' up' : '') + (nodeBusy ? ' busy' : '')} style={{ left: pos.left, top: pos.top }} onClick={() => openSheet(i)}>
              <div className={'boss-dot ' + pos.size}><span className="boss-gi" /><BossNodeImg src={pinSrc} /></div>
              <div className="boss-lbl">{b.role} ・ {b.name}</div>
            </div>
          );
        })}
```

**置換:**
```jsx
        {curStage.bosses.map((b, i) => {
          const pos = BOSS_NODES[i];
          const role = BOSS_ROLE_KEYS[i];
          const pinSrc = i < 2 ? './images/ic_map_subboss.png' : './images/ic_map_boss.png';   // ピン＝汎用アイコン（ボス絵は報告書で使う）
          const nodeBusy = !!busyRoleOnStage[role];
          // 面内順次解放：フロンティア面のみ中A→中B→面ボスの順。過去面（stage≤cleared）は全ノード開放。
          const roleProg = (profile && profile.boss_round_role) || 0;
          const nodeLocked = (stage === cleared + 1) && ((i === 1 && roleProg < 1) || (i === 2 && roleProg < 2));
          return (
            <div key={i} className={'boss-node' + (pos.up ? ' up' : '') + (nodeBusy ? ' busy' : '') + (nodeLocked ? ' locked' : '')} style={{ left: pos.left, top: pos.top }} onClick={() => { if (nodeLocked) { flash(i === 2 ? '中ボスA・Bを撃破すると解放されます' : '中ボスAを撃破すると解放されます'); return; } openSheet(i); }}>
              <div className={'boss-dot ' + pos.size}><span className="boss-gi" /><BossNodeImg src={pinSrc} /></div>
              <div className="boss-lbl">{b.role} ・ {b.name}{nodeLocked ? ' 🔒' : ''}</div>
            </div>
          );
        })}
```

備考:
- `.boss-node.locked` のCSS（グレースケール＋減光）は既存のため、ロック表示はそのまま効きます。
- ロックノードのタップは出撃シートを開かず、解放条件をflash表示します。
- `profile.boss_round_role` は 0054 で追加。`getProfile`（`select *`）が自動で返すためAPI変更は不要です。
