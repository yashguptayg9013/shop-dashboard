// Draws the dashboard from window.DASH (docs/data.js, exported from the PostgreSQL views).
// Plain DOM and SVG, no libraries. All text goes in through textContent.

(function () {
  "use strict";
  const D = window.DASH;
  const REPO = "https://github.com/yashguptayg9013/shop-dashboard/blob/main/";
  const LOOKER_URL = ""; // paste the Looker Studio report link here to show the button

  // ?theme=light|dark forces a theme (for embedding)
  const theme = new URLSearchParams(location.search).get("theme");
  if (theme === "light" || theme === "dark") document.documentElement.dataset.theme = theme;
  if (LOOKER_URL) {
    const a = document.getElementById("looker-link");
    a.href = LOOKER_URL;
    a.hidden = false;
  }

  // ------------------------------------------------------------------ formatting

  const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const inr = new Intl.NumberFormat("en-IN", { maximumFractionDigits: 0 });
  const rupees = (n) => (n < 0 ? "-₹" : "₹") + inr.format(Math.abs(Math.round(n)));
  const lakh = (n, d = 1) => {
    const a = Math.abs(n);
    if (a >= 1e7) return "₹" + (n / 1e7).toFixed(2) + " Cr";
    if (a >= 1e5) return "₹" + (n / 1e5).toFixed(d) + " L";
    return rupees(n);
  };
  const num = (n) => inr.format(Math.round(n));
  const pct = (n, d = 1) => (n == null ? "–" : Number(n).toFixed(d) + "%");
  const parse = (s) => new Date(s.slice(0, 10) + "T00:00:00");
  const day = (s) => { const d = parse(s); return d.getDate() + " " + MONTHS[d.getMonth()] + " " + d.getFullYear(); };
  const dayShort = (s) => { const d = parse(s); return d.getDate() + " " + MONTHS[d.getMonth()]; };
  const monthLong = (s) => { const d = parse(s); return MONTHS[d.getMonth()] + " " + d.getFullYear(); };
  // Month axis ticks: the year appears on the first tick and on each January
  const monthTick = (s, i) => { const d = parse(s); return MONTHS[d.getMonth()] + (i === 0 || d.getMonth() === 0 ? " ’" + String(d.getFullYear()).slice(2) : ""); };
  const sum = (rows, k) => rows.reduce((t, r) => t + (Number(r[k]) || 0), 0);

  // ------------------------------------------------------------------ DOM helpers

  function el(tag, attrs, ...kids) {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v == null || v === false) continue;
      if (k === "class") n.className = v;
      else if (k === "text") n.textContent = v;
      else if (k === "style") n.setAttribute("style", v);
      else n.setAttribute(k, v);
    }
    for (const kid of kids.flat()) if (kid != null) n.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
    return n;
  }
  const SVGNS = "http://www.w3.org/2000/svg";
  function s(tag, attrs, text) {
    const n = document.createElementNS(SVGNS, tag);
    for (const [k, v] of Object.entries(attrs || {})) if (v != null) n.setAttribute(k, v);
    if (text != null) n.textContent = text;
    return n;
  }

  const STATUS = {
    critical: { color: "var(--critical)" },
    serious: { color: "var(--serious)" },
    warning: { color: "var(--warning)" },
    good: { color: "var(--good)" },
    neutral: { color: "var(--neutral)" },
  };
  const pill = (label, kind) => el("span", { class: "pill" }, el("i", { style: "background:" + STATUS[kind].color, "aria-hidden": "true" }), label);
  const item = (name, sku) => el("td", { class: "item" }, name, el("span", { class: "sku", text: sku }));

  function table(cols, rows, foot) {
    const thead = el("thead", {}, el("tr", {}, cols.map((c) => el("th", { class: c.n ? "n" : null, scope: "col", text: c.h }))));
    const tbody = el("tbody", {}, rows.map((r) => el("tr", {}, cols.map((c) => {
      const v = c.v(r);
      if (v && v.nodeType && v.tagName === "TD") return v;
      return el("td", { class: c.n ? "n" : null }, v);
    }))));
    const t = el("table", {}, thead, tbody);
    if (foot) t.append(el("tfoot", {}, el("tr", {}, foot.map((f, i) => el("td", { class: cols[i] && cols[i].n ? "n" : null, colspan: f && f.span }, f && f.v != null ? f.v : f)))));
    return t;
  }

  // ------------------------------------------------------------------ tooltip

  function tooltip(container) {
    const tip = el("div", { class: "tip", role: "status", "aria-live": "polite" });
    container.append(tip);
    return {
      show(x, y, title, rows, foot) {
        tip.replaceChildren(el("div", { class: "t", text: title }));
        for (const r of rows) tip.append(el("div", { class: "r" }, el("span", {}, el("i", { style: "background:" + r.color }), r.label), el("b", { text: r.value })));
        if (foot) tip.append(el("div", { class: "foot", text: foot }));
        tip.classList.add("on");
        const cw = container.clientWidth, tw = tip.offsetWidth, th = tip.offsetHeight;
        let left = x + 14;
        if (left + tw > cw) left = x - tw - 14;
        tip.style.left = Math.max(0, left) + "px";
        tip.style.top = Math.max(0, y - th - 10) + "px";
      },
      hide() { tip.classList.remove("on"); },
    };
  }

  function niceMax(max, ticks = 4) {
    const raw = max / ticks;
    const mag = Math.pow(10, Math.floor(Math.log10(raw)));
    const step = [1, 2, 2.5, 5, 10].map((m) => m * mag).find((st) => st >= raw);
    return { step, top: Math.ceil(max / step) * step };
  }

  const roundedTop = (x, y, w, h, r) => {
    r = Math.max(0, Math.min(r, w / 2, h));
    return `M${x},${y + h}V${y + r}Q${x},${y} ${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h}Z`;
  };

  // ------------------------------------------------------------------ column chart (stacked or grouped)

  function columnChart(container, opt) {
    const tip = tooltip(container);
    function draw() {
      const W = Math.max(300, container.clientWidth), H = opt.height || 250;
      const m = { t: 18, r: 6, b: 26, l: 46 };
      const pw = W - m.l - m.r, ph = H - m.t - m.b;
      const n = opt.categories.length;
      const totals = opt.categories.map((_, i) => opt.series.reduce((t, sr) => t + sr.values[i], 0));
      const peak = opt.stacked ? Math.max(...totals) : Math.max(...opt.series.flatMap((sr) => sr.values));
      const { step, top } = niceMax(peak);
      const y = (v) => m.t + ph - (v / top) * ph;
      const band = pw / n;
      const svg = s("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": opt.label });
      for (let v = 0; v <= top + 1e-9; v += step) {
        svg.append(s("line", { x1: m.l, x2: W - m.r, y1: y(v), y2: y(v), stroke: v === 0 ? "var(--axis)" : "var(--grid)", "stroke-width": 1, "shape-rendering": "crispEdges" }));
        svg.append(s("text", { x: m.l - 8, y: y(v) + 4, "text-anchor": "end" }, opt.yFormat(v)));
      }
      const cols = [];
      opt.categories.forEach((c, i) => {
        const cx = m.l + band * i + band / 2;
        const g = s("g", { class: "col" });
        if (opt.stacked) {
          const bw = Math.min(24, band * 0.62);
          let acc = 0;
          opt.series.forEach((sr, k) => {
            const v = sr.values[i];
            const y0 = y(acc), y1 = y(acc + v);
            const gap = k > 0 ? 2 : 0;
            const h = Math.max(0, y0 - y1 - gap);
            const isTop = k === opt.series.length - 1;
            g.append(isTop
              ? s("path", { d: roundedTop(cx - bw / 2, y1, bw, h, 4), fill: sr.color })
              : s("rect", { x: cx - bw / 2, y: y1, width: bw, height: h, fill: sr.color }));
            acc += v;
          });
        } else {
          const k = opt.series.length;
          const bw = Math.min(16, (band * 0.7 - 2 * (k - 1)) / k);
          const start = cx - (k * bw + 2 * (k - 1)) / 2;
          opt.series.forEach((sr, j) => {
            const v = sr.values[i];
            g.append(s("path", { d: roundedTop(start + j * (bw + 2), y(v), bw, y(0) - y(v), 4), fill: sr.color }));
          });
        }
        svg.append(g);
        cols.push(g);
        if ((n - 1 - i) % (W < 520 ? 2 : 1) === 0) svg.append(s("text", { x: cx, y: H - 8, "text-anchor": "middle" }, opt.xFormat(c, i)));
        if (opt.labelIdx && opt.labelIdx.includes(i)) {
          const v = opt.stacked ? totals[i] : Math.max(...opt.series.map((sr) => sr.values[i]));
          svg.append(s("text", { class: "lbl", x: cx, y: y(v) - 6, "text-anchor": "middle" }, opt.labelFormat(v)));
        }
      });
      // One hit target per month: the whole band, so the reader aims at a month, not a sliver
      opt.categories.forEach((c, i) => {
        const hit = s("rect", { class: "hit", x: m.l + band * i, y: m.t, width: band, height: ph, tabindex: 0, "aria-label": opt.ariaFor(i) });
        const show = (px, py) => {
          cols.forEach((g, j) => g.classList.toggle("dim", j !== i));
          const t = opt.tooltip(i);
          tip.show(px, py, t.title, t.rows, t.foot);
        };
        hit.addEventListener("pointermove", (e) => { const r = container.getBoundingClientRect(); show(e.clientX - r.left, e.clientY - r.top); });
        hit.addEventListener("focus", () => show((m.l + band * i + band / 2) * container.clientWidth / W, m.t + 30));
        const hide = () => { cols.forEach((g) => g.classList.remove("dim")); tip.hide(); };
        hit.addEventListener("pointerleave", hide);
        hit.addEventListener("blur", hide);
        svg.append(hit);
      });
      container.querySelector("svg")?.remove();
      container.prepend(svg);
    }
    draw();
    new ResizeObserver(() => draw()).observe(container);
  }

  // ------------------------------------------------------------------ line chart

  function lineChart(container, opt) {
    const tip = tooltip(container);
    function draw() {
      const W = Math.max(280, container.clientWidth), H = opt.height || 220;
      const m = { t: 14, r: 92, b: 26, l: 40 };
      const pw = W - m.l - m.r, ph = H - m.t - m.b;
      const n = opt.categories.length;
      const { step, top } = niceMax(Math.max(...opt.series.flatMap((sr) => sr.values)));
      const x = (i) => m.l + (pw * i) / (n - 1);
      const y = (v) => m.t + ph - (v / top) * ph;
      const svg = s("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": opt.label });
      for (let v = 0; v <= top + 1e-9; v += step) {
        svg.append(s("line", { x1: m.l, x2: m.l + pw, y1: y(v), y2: y(v), stroke: v === 0 ? "var(--axis)" : "var(--grid)", "stroke-width": 1, "shape-rendering": "crispEdges" }));
        svg.append(s("text", { x: m.l - 8, y: y(v) + 4, "text-anchor": "end" }, opt.yFormat(v)));
      }
      opt.categories.forEach((c, i) => {
        if ((n - 1 - i) % (W < 520 ? 3 : 2) === 0) svg.append(s("text", { x: x(i), y: H - 8, "text-anchor": "middle" }, opt.xFormat(c, i)));
      });
      const cross = s("line", { y1: m.t, y2: m.t + ph, stroke: "var(--axis)", "stroke-width": 1, opacity: 0 });
      svg.append(cross);
      opt.series.forEach((sr) => {
        const d = sr.values.map((v, i) => (i ? "L" : "M") + x(i).toFixed(1) + "," + y(v).toFixed(1)).join("");
        svg.append(s("path", { d, fill: "none", stroke: sr.color, "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round" }));
        const last = sr.values[n - 1];
        svg.append(s("circle", { cx: x(n - 1), cy: y(last), r: 4, fill: sr.color, stroke: "var(--surface)", "stroke-width": 2 }));
      });
      // End labels, nudged apart only if they would overlap
      const ends = opt.series.map((sr) => ({ sr, yy: y(sr.values[n - 1]) })).sort((a, b) => a.yy - b.yy);
      for (let i = 1; i < ends.length; i++) if (ends[i].yy - ends[i - 1].yy < 26) ends[i].yy = ends[i - 1].yy + 26;
      ends.forEach(({ sr, yy }) => {
        svg.append(s("text", { class: "lbl", x: x(n - 1) + 10, y: yy - 1 }, opt.yFormat(sr.values[n - 1], true)));
        svg.append(s("text", { x: x(n - 1) + 10, y: yy + 12 }, sr.label));
      });
      const dots = opt.series.map((sr) => { const c = s("circle", { r: 4, fill: sr.color, stroke: "var(--surface)", "stroke-width": 2, opacity: 0 }); svg.append(c); return c; });
      const hit = s("rect", { class: "hit", x: m.l - 6, y: m.t, width: pw + 12, height: ph, tabindex: 0, "aria-label": opt.label + ". Use left and right arrows to move between months." });
      let cur = n - 1;
      const show = (i, px, py) => {
        cur = i;
        cross.setAttribute("x1", x(i)); cross.setAttribute("x2", x(i)); cross.setAttribute("opacity", 1);
        opt.series.forEach((sr, k) => { dots[k].setAttribute("cx", x(i)); dots[k].setAttribute("cy", y(sr.values[i])); dots[k].setAttribute("opacity", 1); });
        tip.show(px, py, opt.titleFormat(opt.categories[i]), opt.series.map((sr) => ({ color: sr.color, label: sr.label, value: opt.yFormat(sr.values[i], true) })));
      };
      const hide = () => { cross.setAttribute("opacity", 0); dots.forEach((d) => d.setAttribute("opacity", 0)); tip.hide(); };
      hit.addEventListener("pointermove", (e) => {
        const r = container.getBoundingClientRect();
        const sx = ((e.clientX - r.left) * W) / container.clientWidth;
        const i = Math.max(0, Math.min(n - 1, Math.round(((sx - m.l) / pw) * (n - 1))));
        show(i, e.clientX - r.left, e.clientY - r.top);
      });
      const kb = (i) => show(i, (x(i) * container.clientWidth) / W, m.t + 30);
      hit.addEventListener("focus", () => kb(cur));
      hit.addEventListener("keydown", (e) => {
        if (e.key === "ArrowRight") { kb(Math.min(n - 1, cur + 1)); e.preventDefault(); }
        if (e.key === "ArrowLeft") { kb(Math.max(0, cur - 1)); e.preventDefault(); }
      });
      hit.addEventListener("pointerleave", hide);
      hit.addEventListener("blur", hide);
      svg.append(hit);
      container.querySelector("svg")?.remove();
      container.prepend(svg);
    }
    draw();
    new ResizeObserver(() => draw()).observe(container);
  }

  // ------------------------------------------------------------------ SQL viewer

  const KEYWORDS = /\b(select|from|where|join|left|full|cross|lateral|on|using|group by|order by|having|with|recursive|as|and|or|not|in|exists|case|when|then|else|end|union all|create or replace view|create table|create function|create or replace function|create index|filter|over|partition by|distinct on|distinct|limit|between|is|null|coalesce|greatest|least|returns|language|primary key|references|check|insert into|values|unique)\b/gi;

  function sqlBlock(target, files) {
    const host = document.getElementById(target);
    for (const f of files) {
      const text = D.sql[f];
      if (!text) continue;
      const pre = el("pre");
      for (const line of text.split("\n")) {
        const at = line.indexOf("--");
        const code = at >= 0 ? line.slice(0, at) : line;
        let last = 0;
        code.replace(KEYWORDS, (mm, _g, idx) => {
          pre.append(code.slice(last, idx), el("span", { class: "k", text: mm }));
          last = idx + mm.length;
          return mm;
        });
        pre.append(code.slice(last));
        if (at >= 0) pre.append(el("span", { class: "c", text: line.slice(at) }));
        pre.append("\n");
      }
      host.append(el("details", { class: "sql" },
        el("summary", {}, "SQL behind this", el("span", { class: "file", text: f })),
        pre,
        el("a", { class: "gh", href: REPO + f, text: "Open " + f + " on GitHub" })));
    }
  }

  // ------------------------------------------------------------------ page

  document.getElementById("as-of").textContent = day(D.as_of);
  document.getElementById("biz-name").textContent = D.business.name;

  // KPI tiles
  const ms = D.monthly_sales;
  const last = ms[ms.length - 1], prev = ms[ms.length - 2];
  const gstLast = D.gst_monthly[D.gst_monthly.length - 1];
  const stockValue = sum(D.stock, "stock_value");
  const dead = D.dead_stock.filter((r) => r.status === "Dead");
  const deadValue = sum(dead, "stock_value");
  const urgent = D.reorder.filter((r) => r.status < "3");
  const thisWeek = D.reorder.filter((r) => r.status.startsWith("3"));
  const dueDate = (() => { const d = parse(gstLast.month); return "20 " + MONTHS[(d.getMonth() + 1) % 12]; })();
  const change = (a, b, unit) => {
    const dlt = unit === "pts" ? a - b : (a / b - 1) * 100;
    const cls = dlt >= 0 ? "up" : "down";
    return el("span", {}, el("span", { class: cls, text: (dlt >= 0 ? "▲ " : "▼ ") + Math.abs(dlt).toFixed(1) + (unit === "pts" ? " pts" : "%") }), " vs " + MONTHS[parse(prev.month).getMonth()]);
  };
  const tiles = [
    ["Sales, " + monthLong(last.month), lakh(last.revenue), change(last.revenue, prev.revenue)],
    ["Gross margin, " + MONTHS[parse(last.month).getMonth()], pct(last.margin_pct), change(last.margin_pct, prev.margin_pct, "pts")],
    ["Stock at cost", lakh(stockValue, 2), D.stock.length + " items"],
    ["Dead stock", rupees(deadValue), pct((100 * deadValue) / stockValue, 0) + " of stock, " + dead.length + " items"],
    ["Order now", String(urgent.length + thisWeek.length), urgent.length + " today, " + thisWeek.length + " this week"],
    ["GST cash, " + MONTHS[parse(gstLast.month).getMonth()], lakh(gstLast.cash_payable, 2), "GSTR-3B due " + dueDate],
  ];
  document.getElementById("kpis").append(...tiles.map(([l, v, d]) => el("div", { class: "card kpi" }, el("div", { class: "label", text: l }), el("div", { class: "value", text: v }), el("div", { class: "delta" }, d))));
  document.getElementById("kpi-sub").textContent = "Latest month: " + monthLong(last.month);

  // Sales trend
  const CH = [
    { key: "b2b_revenue", label: "B2B (retailers)", color: "var(--s1)" },
    { key: "counter_revenue", label: "Shop counter", color: "var(--s2)" },
    { key: "online_revenue", label: "Online", color: "var(--s3)" },
  ];
  document.getElementById("sales-legend").append(...CH.map((c) => el("span", {}, el("i", { style: "background:" + c.color }), c.label)));
  const peakIdx = ms.reduce((b, r, i) => (r.revenue > ms[b].revenue ? i : b), 0);
  columnChart(document.getElementById("sales-chart"), {
    label: "Monthly sales by channel, stacked columns",
    categories: ms.map((r) => r.month),
    series: CH.map((c) => ({ ...c, values: ms.map((r) => Number(r[c.key])) })),
    stacked: true,
    yFormat: (v) => (v === 0 ? "0" : "₹" + v / 1e5 + "L"),
    xFormat: monthTick,
    labelIdx: [peakIdx, ms.length - 1],
    labelFormat: (v) => lakh(v),
    ariaFor: (i) => monthLong(ms[i].month) + ": sales " + lakh(ms[i].revenue) + ", margin " + pct(ms[i].margin_pct),
    tooltip: (i) => ({
      title: monthLong(ms[i].month),
      rows: [...CH].reverse().map((c) => ({ color: c.color, label: c.label, value: lakh(ms[i][c.key], 2) })),
      foot: "Total " + lakh(ms[i].revenue, 2) + " · margin " + pct(ms[i].margin_pct) + " · " + num(ms[i].invoices) + " invoices",
    }),
  });
  document.getElementById("sales-table").append(table([
    { h: "Month", v: (r) => monthLong(r.month) },
    { h: "Sales", n: 1, v: (r) => rupees(r.revenue) },
    { h: "B2B", n: 1, v: (r) => rupees(r.b2b_revenue) },
    { h: "Counter", n: 1, v: (r) => rupees(r.counter_revenue) },
    { h: "Online", n: 1, v: (r) => rupees(r.online_revenue) },
    { h: "Gross profit", n: 1, v: (r) => rupees(r.gross_profit) },
    { h: "Margin", n: 1, v: (r) => pct(r.margin_pct) },
    { h: "Invoices", n: 1, v: (r) => num(r.invoices) },
    { h: "vs last month", n: 1, v: (r) => (r.revenue_vs_prev_month_pct == null ? "–" : (r.revenue_vs_prev_month_pct > 0 ? "+" : "") + pct(r.revenue_vs_prev_month_pct)) },
  ], ms));

  // Category shares
  const cats = {};
  for (const r of D.category_monthly) {
    const c = (cats[r.category] ||= { rev: 0, gp: 0 });
    c.rev += r.revenue; c.gp += r.gross_profit;
  }
  const totRev = Object.values(cats).reduce((t, c) => t + c.rev, 0);
  const totGp = Object.values(cats).reduce((t, c) => t + c.gp, 0);
  const catRows = Object.entries(cats).map(([name, c]) => ({ name, rs: (100 * c.rev) / totRev, ps: (100 * c.gp) / totGp })).sort((a, b) => b.rs - a.rs);
  const maxShare = Math.max(...catRows.flatMap((r) => [r.rs, r.ps]));
  document.getElementById("shares").append(...catRows.map((r) => el("div", { class: "share-row" + (r.name === "Power banks" ? " hl" : "") },
    el("div", { class: "name", text: r.name }),
    el("div", { class: "bars", role: "img", "aria-label": r.name + ": " + pct(r.rs) + " of sales, " + pct(r.ps) + " of gross profit" },
      el("div", { class: "bar-line" }, el("div", { class: "b", style: `width:${(r.rs / maxShare) * 82}%;background:var(--s1)` }), el("span", { class: "v", text: pct(r.rs) })),
      el("div", { class: "bar-line" }, el("div", { class: "b", style: `width:${(r.ps / maxShare) * 82}%;background:var(--s2)` }), el("span", { class: "v", text: pct(r.ps) }))))));

  // Margin lines
  const months = ms.map((r) => r.month);
  const pb = months.map((mo) => D.category_monthly.find((r) => r.month === mo && r.category === "Power banks").margin_pct);
  lineChart(document.getElementById("margin-chart"), {
    label: "Gross margin by month, whole shop and power banks",
    categories: months,
    series: [
      { label: "Whole shop", color: "var(--s1)", values: ms.map((r) => r.margin_pct) },
      { label: "Power banks", color: "var(--s2)", values: pb },
    ],
    yFormat: (v, precise) => (precise ? pct(v) : v + "%"),
    xFormat: monthTick,
    titleFormat: monthLong,
  });
  sqlBlock("sql-sales", ["sql/views/10_sales_lines.sql", "sql/views/11_monthly_sales.sql"]);

  // Reorder
  const statusPill = (st) => ({ "1": pill("Out of stock", "critical"), "2": pill("Order today", "serious"), "3": pill("This week", "warning") })[st[0]] || pill("OK", "good");
  document.getElementById("reorder-table").append(table([
    { h: "Item", v: (r) => item(r.product, r.sku) },
    { h: "Status", v: (r) => statusPill(r.status) },
    { h: "In stock", n: 1, v: (r) => num(r.qty) },
    { h: "Sells / day", n: 1, v: (r) => Number(r.per_day).toFixed(1) },
    { h: "Days left", n: 1, v: (r) => Number(r.days_of_cover).toFixed(1) },
    { h: "Lead time", n: 1, v: (r) => r.lead_time_days + " d" },
    { h: "Order", n: 1, v: (r) => num(r.order_qty) },
    { h: "At cost", n: 1, v: (r) => rupees(r.order_value) },
    { h: "Supplier", v: (r) => el("span", { class: "muted", text: r.supplier }) },
  ], D.reorder, [{ v: "Total to order", span: 7 }, rupees(sum(D.reorder, "order_value")), ""]));
  const so = D.stockouts.slice(0, 8);
  document.getElementById("stockout-table").append(table([
    { h: "Item", v: (r) => item(r.product, r.sku) },
    { h: "Days out", n: 1, v: (r) => r.days_out },
    { h: "Pace in stock", n: 1, v: (r) => Number(r.per_day_in_stock).toFixed(1) + " / day" },
    { h: "Missed units", n: 1, v: (r) => num(r.missed_units) },
    { h: "Missed sales", n: 1, v: (r) => rupees(r.missed_revenue) },
    { h: "Missed profit", n: 1, v: (r) => rupees(r.missed_profit) },
  ], so, [{ v: "All " + D.stockouts.length + " items", span: 4 }, rupees(sum(D.stockouts, "missed_revenue")), rupees(sum(D.stockouts, "missed_profit"))]));
  sqlBlock("sql-reorder", ["sql/views/20_stock.sql", "sql/views/22_reorder.sql"]);

  // Diwali
  const fp = D.festival_prep;
  if (fp.length) {
    const f = fp[0];
    document.getElementById("diwali-sub").textContent =
      `${f.festival} is on ${day(f.festival_date)} and the rush starts ${day(f.rush_start)}. Everyday reorders keep normal sales covered; this is the extra stock the rush needs on top. For everyday items that's today's pace, sped up as much as last year's rush sped it up. For festival-only items it's last year's rush minus what's on the shelf. Order by = rush start minus the supplier's lead time.`;
  }
  document.getElementById("diwali-table").append(table([
    { h: "Order by", v: (r) => el("b", { text: dayShort(r.order_by) }) },
    { h: "Item", v: (r) => item(r.product, r.sku) },
    { h: "Supplier", v: (r) => el("span", { class: "muted", text: r.supplier + " (" + r.lead_time_days + " d)" }) },
    { h: "Sold last rush", n: 1, v: (r) => num(r.units_last_rush) },
    { h: "Rush vs usual", n: 1, v: (r) => (r.rush_uplift == null ? "–" : Number(r.rush_uplift).toFixed(1) + "×") },
    { h: "Sells / day now", n: 1, v: (r) => (r.is_seasonal ? "festival only" : Number(r.per_day_now).toFixed(1)) },
    { h: "In stock", n: 1, v: (r) => num(r.stock_now) },
    { h: "Extra to order", n: 1, v: (r) => num(r.festival_qty) },
    { h: "At cost", n: 1, v: (r) => rupees(r.festival_value) },
  ], fp, [{ v: fp.length + " items", span: 8 }, rupees(sum(fp, "festival_value"))]));
  sqlBlock("sql-diwali", ["sql/views/13_seasonality.sql", "sql/views/23_festival_prep.sql"]);

  // Dead stock
  const deadKind = { Dead: "serious", Slow: "warning", Seasonal: "neutral" };
  const dsAll = D.dead_stock;
  document.getElementById("dead-table").append(table([
    { h: "Item", v: (r) => item(r.product, r.sku) },
    { h: "Status", v: (r) => pill(r.status, deadKind[r.status]) },
    { h: "Units", n: 1, v: (r) => num(r.qty) },
    { h: "Value at cost", n: 1, v: (r) => rupees(r.stock_value) },
    { h: "Last sold", n: 1, v: (r) => (r.last_sale ? dayShort(r.last_sale) + " · " + r.days_since_last_sale + " d ago" : "Never") },
    { h: "Last bought", n: 1, v: (r) => (r.last_purchase ? day(r.last_purchase) : "Opening stock") },
    { h: "Supplier", v: (r) => el("span", { class: "muted", text: r.supplier }) },
  ], dsAll, [{ v: "Dead and slow", span: 3 }, rupees(sum(dsAll.filter((r) => r.status !== "Seasonal"), "stock_value")), { v: "", span: 3 }]));
  sqlBlock("sql-dead", ["sql/views/21_dead_stock.sql"]);

  // GST
  const g = D.gst_monthly;
  columnChart(document.getElementById("gst-chart"), {
    label: "GST on sales, input tax credit and cash payable by month",
    categories: g.map((r) => r.month),
    series: [
      { label: "GST on sales", color: "var(--s1)", values: g.map((r) => r.output_tax) },
      { label: "Input tax credit", color: "var(--s2)", values: g.map((r) => r.itc) },
      { label: "Cash payable", color: "var(--s3)", values: g.map((r) => r.cash_payable) },
    ],
    stacked: false,
    height: 230,
    yFormat: (v) => (v === 0 ? "0" : "₹" + v / 1e5 + "L"),
    xFormat: monthTick,
    ariaFor: (i) => monthLong(g[i].month) + ": GST on sales " + lakh(g[i].output_tax, 2) + ", credit " + lakh(g[i].itc, 2) + ", cash " + lakh(g[i].cash_payable, 2),
    tooltip: (i) => ({
      title: monthLong(g[i].month),
      rows: [
        { color: "var(--s1)", label: "GST on sales", value: rupees(g[i].output_tax) },
        { color: "var(--s2)", label: "Input tax credit", value: rupees(g[i].itc) },
        { color: "var(--s3)", label: "Cash payable", value: rupees(g[i].cash_payable) },
      ],
      foot: g[i].credit_carried_forward > 0 ? "Credit carried forward " + rupees(g[i].credit_carried_forward) : "No credit carried forward",
    }),
  });
  document.getElementById("gst-table").append(table([
    { h: "Month", v: (r) => monthLong(r.month) },
    { h: "Taxable sales", n: 1, v: (r) => rupees(r.taxable_sales) },
    { h: "B2B (GSTIN)", n: 1, v: (r) => rupees(r.b2b_taxable) },
    { h: "CGST", n: 1, v: (r) => rupees(r.out_cgst) },
    { h: "SGST", n: 1, v: (r) => rupees(r.out_sgst) },
    { h: "IGST", n: 1, v: (r) => rupees(r.out_igst) },
    { h: "Input tax credit", n: 1, v: (r) => rupees(r.itc) },
    { h: "Cash payable", n: 1, v: (r) => el("b", { text: rupees(r.cash_payable) }) },
  ], g, [{ v: "12 months", span: 1 }, rupees(sum(g, "taxable_sales")), rupees(sum(g, "b2b_taxable")), rupees(sum(g, "out_cgst")), rupees(sum(g, "out_sgst")), rupees(sum(g, "out_igst")), rupees(sum(g, "itc")), rupees(sum(g, "cash_payable"))]));
  const hsn = D.gst_hsn.filter((r) => r.month === last.month);
  document.getElementById("hsn-summary").textContent = "HSN summary for " + monthLong(last.month) + " (GSTR-1 table 12)";
  document.getElementById("hsn-table").append(table([
    { h: "HSN", v: (r) => r.hsn },
    { h: "Description", v: (r) => r.description },
    { h: "UQC", v: (r) => r.uqc },
    { h: "Rate", n: 1, v: (r) => Number(r.gst_rate) + "%" },
    { h: "Quantity", n: 1, v: (r) => num(r.total_qty) },
    { h: "Taxable value", n: 1, v: (r) => rupees(r.taxable_value) },
    { h: "IGST", n: 1, v: (r) => rupees(r.igst || 0) },
    { h: "CGST", n: 1, v: (r) => rupees(r.cgst || 0) },
    { h: "SGST", n: 1, v: (r) => rupees(r.sgst || 0) },
  ], hsn));
  sqlBlock("sql-gst", ["sql/views/30_gst.sql"]);

  // Products
  document.getElementById("product-table").append(table([
    { h: "Item", v: (r) => item(r.product, r.sku) },
    { h: "Class", v: (r) => el("b", { text: r.abc_class }) },
    { h: "Category", v: (r) => el("span", { class: "muted", text: r.category }) },
    { h: "Units", n: 1, v: (r) => num(r.units) },
    { h: "Sales", n: 1, v: (r) => rupees(r.revenue) },
    { h: "Share", n: 1, v: (r) => pct(r.revenue_share_pct) },
    { h: "Gross profit", n: 1, v: (r) => rupees(r.gross_profit) },
    { h: "Margin", n: 1, v: (r) => pct(r.margin_pct) },
    { h: "Sales rank", n: 1, v: (r) => "#" + r.revenue_rank },
    { h: "Profit rank", n: 1, v: (r) => (r.profit_rank - r.revenue_rank >= 5 ? el("b", { text: "#" + r.profit_rank + " ▼" }) : "#" + r.profit_rank) },
  ], D.products));
  sqlBlock("sql-products", ["sql/views/12_product_performance.sql"]);

  // Checks
  const ok = '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="7" fill="var(--good)"/><path d="M4.8 8.2l2.1 2.1 4.3-4.6" stroke="#fff" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  const bad = '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="7" fill="var(--critical)"/><path d="M5.5 5.5l5 5m0-5l-5 5" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/></svg>';
  document.getElementById("checks").append(...D.checks.map((c) => {
    const li = el("li");
    li.insertAdjacentHTML("afterbegin", c.failures === 0 ? ok : bad); // static icon markup only
    li.append(el("span", {}, c.check_name, c.failures ? el("b", { text: " (" + c.failures + " failed)" }) : el("span", { class: "sr", text: " (passed)" })));
    return li;
  }));
  sqlBlock("sql-checks", ["sql/01_schema.sql", "sql/views/90_data_checks.sql"]);
})();
