# Inline stylesheet of the HTML report (no external resource, no script).

$script:ELReportCss = @'
:root { --ink: #1f2933; --muted: #52606d; --line: #d9e2ec; --bg: #f5f7fa; --card: #ffffff;
  --accent: #0b5cad; --high: #b42318; --high-bg: #fde8e7; --medium: #9a5b00; --medium-bg: #fff4dc;
  --low: #22653b; --low-bg: #e6f4ea; --deferred-bg: #eef2f7; }
* { box-sizing: border-box; }
body { margin: 0; font-family: "Segoe UI", Roboto, Helvetica, Arial, sans-serif; color: var(--ink);
  background: var(--bg); line-height: 1.45; }
main { max-width: 1200px; margin: 0 auto; padding: 24px 16px 48px; }
header h1 { margin: 0 0 6px; font-size: 1.6rem; }
.meta { color: var(--muted); margin: 0 0 8px; font-size: .9rem; }
.notice { background: #e8f1fb; border-left: 4px solid var(--accent); padding: 10px 14px; margin: 12px 0 0; }
.badge { display: inline-block; padding: 2px 10px; border-radius: 999px; font-size: .75rem;
  vertical-align: middle; font-weight: 600; }
.badge.demo { background: #fff0c2; color: #7a4d00; border: 1px solid #f0c75e; }
section { margin-top: 28px; }
h2 { font-size: 1.15rem; border-bottom: 2px solid var(--line); padding-bottom: 6px; }
.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 12px; }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 12px 14px; }
.card .value { display: block; font-size: 1.6rem; font-weight: 700; }
.card .label { color: var(--muted); font-size: .85rem; }
.card.alert .value { color: var(--high); }
table { width: 100%; border-collapse: collapse; background: var(--card); font-size: .88rem; }
th, td { text-align: left; padding: 7px 9px; border-bottom: 1px solid var(--line); vertical-align: top; }
th { background: #e4e7eb; font-weight: 600; }
td.num { text-align: right; font-variant-numeric: tabular-nums; }
.risk { display: inline-block; padding: 1px 8px; border-radius: 4px; font-weight: 600; font-size: .8rem; }
.risk-high { background: var(--high-bg); color: var(--high); }
.risk-medium { background: var(--medium-bg); color: var(--medium); }
.risk-low { background: var(--low-bg); color: var(--low); }
tr.deferred td { background: var(--deferred-bg); color: var(--muted); }
.empty { color: var(--muted); font-style: italic; }
.table-wrap { overflow-x: auto; }
footer { margin-top: 36px; color: var(--muted); font-size: .8rem; }
'@
