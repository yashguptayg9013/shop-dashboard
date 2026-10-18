#!/usr/bin/env python3
"""Simulate a year of trading for Kaveri Imports & Trading, Bhiwandi (fictional).

Writes one CSV per table in data/, matching sql/01_schema.sql. The run is seeded,
so it gives the same data every time. Every business, person and GSTIN is made up.

What the simulation models:
  - Three sales channels: the shop counter, B2B orders from retailers, and online
    orders shipped across India (inter-state, so IGST).
  - Demand that moves with the weekday and the season: Diwali and Dhanteras, the
    wedding season for kitchenware, the monsoon dip and Ganesh Chaturthi.
  - Products whose demand grows (USB-C), fades out (micro-USB, wired earphones)
    or only sells at festivals (brass and copper gift items).
  - An owner who reorders by feel: reorder levels set once from last year's sales,
    checked on Mondays and Thursdays. Fast growers run out; fading items pile up.
  - Supplier lead times and price changes (power banks up 8% from February).

To use real data instead, export your purchase and sales registers into CSVs with
the same columns and skip this script.

Usage: python3 scripts/generate_data.py [output_dir]
"""

import csv
import datetime as dt
import math
import os
import random
import sys

SEED = 20261019
START = dt.date(2025, 10, 1)
END = dt.date(2026, 9, 30)
DIWALI = [dt.date(2025, 10, 20), dt.date(2026, 11, 8)]
GANESH_CHATURTHI = [dt.date(2026, 9, 14)]
CLOSED = {dt.date(2025, 10, 22), dt.date(2025, 10, 23), dt.date(2026, 3, 4)}  # Padwa, Bhai Dooj, Holi

HOME_STATE = "27"  # Maharashtra

rng = random.Random(SEED)

# --------------------------------------------------------------------------- master data

SUPPLIERS = [
    # id, name, gstin, state, city, lead days, invoice number format
    (1, "Shree Ganesh Electronics Traders", "27AAKFS4821M1ZQ", "27", "Mumbai", 3, "SGE/{fy}/{n:04d}"),
    (2, "Zenith Mobile Gear LLP", "07AAJFZ3318Q1ZG", "07", "New Delhi", 6, "ZMG/{fy2}/{n:04d}"),
    (3, "Northline Home Goods Pvt. Ltd.", "07AAECN5512K1ZF", "07", "New Delhi", 8, "NHG-{cy}-{n:05d}"),
    (4, "Om Sai Steel Centre", "27ABDPO7720H1ZL", "27", "Mumbai", 4, "{n}"),
    (5, "Moradabad Metal Crafts", "09AAPFM2290L1ZO", "09", "Moradabad", 9, "MMC/{fy}/{n:03d}"),
]
LEAD = {s[0]: s[5] for s in SUPPLIERS}
SUP_STATE = {s[0]: s[3] for s in SUPPLIERS}

# Counter price is GST-inclusive, as on the shelf tag. pop = how often the item is
# picked, per channel (counter, b2b, online). trend = demand multiplier at the start
# and end of the year; dies = date demand reaches zero. festive = how much more it
# sells at peak Diwali. wedding = multiplier in wedding season. open_days = opening
# stock as days of normal sales.
P = [
    # id sku           name                               category            hsn    gst sup cost   price  pop (c, b, o)    trend        dies          festive wedding moq open_days unit
    (1, "CHG-C20",   "USB-C Fast Charger 20W",           "Chargers",         "8504", 18, 1, 245,   499, (8, 7, 6),      (1.0, 1.9), None,              1.6, 1.0, 10, 18, "PCS"),
    (2, "CHG-C33",   "USB-C Fast Charger 33W",           "Chargers",         "8504", 18, 1, 390,   799, (3, 3, 4),      (0.6, 1.6), None,              1.6, 1.0, 10, 25, "PCS"),
    (3, "CHG-MU10",  "Micro-USB Charger 10W",            "Chargers",         "8504", 18, 1, 120,   249, (3, 3, 1),      (1.0, 0.0), dt.date(2026, 4, 15), 1.0, 1.0, 20, 75, "PCS"),
    (4, "CHG-CAR",   "Car Charger Dual USB",             "Accessories",      "8504", 18, 2, 150,   349, (1.5, 1.5, 1),  (1.0, 1.0), None,              1.4, 1.0, 10, 35, "PCS"),
    (5, "CBL-C1",    "Braided USB-C Cable 1m",           "Cables",           "8544", 18, 1, 68.5,  199, (9, 9, 5),      (1.0, 1.3), None,              1.3, 1.0, 20, 25, "PCS"),
    (6, "CBL-LT1",   "USB-C to Lightning Cable 1m",      "Cables",           "8544", 18, 1, 140,   399, (3, 3, 3),      (1.0, 1.0), None,              1.3, 1.0, 10, 30, "PCS"),
    (7, "CBL-MU1",   "Micro-USB Cable 1m",               "Cables",           "8544", 18, 1, 32,    99,  (4, 5, 1),      (1.0, 0.0), dt.date(2026, 5, 20), 1.0, 1.0, 50, 60, "PCS"),
    (8, "CBL-AUX",   "3.5mm AUX Cable 1m",               "Cables",           "8544", 18, 2, 28,    99,  (1.2, 1.5, 0.3), (0.6, 0.0), dt.date(2026, 2, 28), 1.0, 1.0, 50, 160, "PCS"),
    (9, "PRT-TG",    "Tempered Glass Screen Guard",      "Phone protection", "7007", 18, 1, 18,    99,  (14, 10, 3),    (1.0, 1.1), None,              1.2, 1.0, 100, 30, "PCS"),
    (10, "PRT-CASE", "Silicone Phone Case (assorted)",   "Phone protection", "3926", 18, 1, 45,    199, (8, 7, 3),      (1.0, 1.0), None,              1.2, 1.0, 50, 30, "PCS"),
    (11, "ACC-STD",  "Aluminium Phone Stand",            "Accessories",      "7616", 18, 1, 95,    299, (2, 2, 2),      (1.0, 1.0), None,              1.3, 1.0, 20, 30, "PCS"),
    (12, "ACC-STRP", "Smartwatch Strap 22mm",            "Accessories",      "9113", 18, 2, 60,    199, (1, 1, 1.5),    (1.0, 1.2), None,              1.2, 1.0, 20, 40, "PCS"),
    (13, "AUD-TWS2", "TWS Earbuds Model X2",             "Audio",            "8518", 18, 1, 610,   1299, (4, 4, 7),     (1.0, 1.6), None,              2.6, 1.0, 10, 20, "PCS"),
    (14, "AUD-NB5",  "Neckband Earphones N5",            "Audio",            "8518", 18, 2, 380,   849, (3, 3, 3),      (1.0, 0.55), None,             1.6, 1.0, 10, 30, "PCS"),
    (15, "AUD-WRD",  "Wired Earphones 3.5mm",            "Audio",            "8518", 18, 2, 85,    249, (4, 4, 1),      (1.0, 0.0), dt.date(2026, 6, 10), 1.0, 1.0, 20, 70, "PCS"),
    (16, "AUD-SPK",  "Bluetooth Speaker Mini",           "Audio",            "8518", 18, 2, 520,   1099, (1.5, 1.5, 2.5), (1.0, 1.0), None,            3.0, 1.0, 5, 30, "PCS"),
    (17, "PWR-10K",  "Power Bank 10000mAh",              "Power banks",      "8507", 18, 1, 720,   999, (5, 5, 6),      (1.0, 1.2), None,              1.8, 1.0, 10, 20, "PCS"),
    (18, "PWR-20K",  "Power Bank 20000mAh",              "Power banks",      "8507", 18, 2, 1150,  1599, (2, 2, 3),     (1.0, 1.0), None,              1.5, 1.0, 5, 25, "PCS"),
    (19, "KIT-BTL1", "Stainless Steel Water Bottle 1L",  "Kitchenware",      "7323", 5, 3, 185,    349, (3, 4, 2),      (1.0, 1.0), None,              1.5, 1.2, 12, 35, "NOS"),
    (20, "KIT-MUG",  "Ceramic Coffee Mug 350ml",         "Kitchenware",      "6912", 5, 3, 72.5,   179, (2, 3, 1),      (1.0, 1.0), None,              1.4, 1.2, 24, 35, "NOS"),
    (21, "KIT-JAR",  "Glass Storage Jar 1.5L",           "Kitchenware",      "7013", 5, 3, 140,    279, (1.5, 2.5, 1),  (1.0, 1.0), None,              1.3, 1.2, 12, 40, "NOS"),
    (22, "KIT-TWL",  "Cotton Kitchen Towels (Set of 3)", "Kitchenware",      "6302", 5, 3, 120,    249, (2, 2.5, 1),    (1.0, 1.0), None,              1.2, 1.1, 20, 40, "SET"),
    (23, "STL-LBX",  "Steel Lunch Box 3-Tier",           "Kitchenware",      "7323", 5, 4, 260,    499, (2, 3, 1.5),    (1.0, 1.0), None,              1.5, 1.3, 10, 30, "NOS"),
    (24, "STL-DIN",  "Steel Dinner Set (24 pc)",         "Kitchenware",      "7323", 5, 4, 1450,   2399, (0.6, 1.2, 0.4), (1.0, 1.0), None,            4.0, 1.7, 4, 30, "SET"),
    (25, "STL-KDI",  "Steel Kadai 2.5L",                 "Kitchenware",      "7323", 5, 4, 390,    699, (1.2, 2, 0.6),  (1.0, 1.0), None,              2.5, 1.3, 6, 30, "NOS"),
    (26, "FST-DIYA", "Brass Diya Set (5 pc)",            "Festive & gifting", "7418", 5, 5, 210,   449, (0.08, 0.08, 0.05), (1.0, 1.0), None,         60, 1.0, 20, 0, "SET"),
    (27, "FST-CPB",  "Copper Bottle Gift Set",           "Festive & gifting", "7418", 5, 5, 480,   899, (0.3, 0.5, 0.4), (1.0, 1.0), None,            8, 1.6, 10, 0, "SET"),
    (28, "FST-THL",  "Brass Pooja Thali Set",            "Festive & gifting", "7418", 5, 5, 340,   649, (0.12, 0.12, 0.08), (1.0, 1.0), None,         35, 1.0, 10, 0, "SET"),
]
FESTIVE_ITEMS = {26, 27, 28}

# Trade (B2B) price = current cost x markup. Retail prices are fixed shelf prices.
B2B_MARKUP = {"Chargers": 1.20, "Cables": 1.32, "Audio": 1.16, "Power banks": 1.08, "Phone protection": 1.70,
              "Accessories": 1.28, "Kitchenware": 1.20, "Festive & gifting": 1.28}

# Supplier price changes: (product ids, from date, multiplier)
COST_CHANGES = [
    ({17, 18}, dt.date(2026, 2, 1), 1.08),   # power banks: cell prices up
    ({13}, dt.date(2026, 5, 1), 0.94),       # TWS X2: cheaper new batch
    ({23, 24, 25}, dt.date(2026, 4, 1), 1.05),  # steel prices
]

CUSTOMERS = [
    # name, city, state, registered?, size
    ("Patel Mobile Point", "Kalyan", "27", True, 9),
    ("New Sai Mobile", "Thane", "27", True, 8),
    ("Mahavir Telecom", "Pune", "27", True, 8),
    ("Shree Krishna Electronics", "Nashik", "27", True, 6),
    ("Royal Gift Centre", "Vasai", "27", True, 6),
    ("City Mobile Hub", "Panvel", "27", True, 5),
    ("Om Mobile Accessories", "Dombivli", "27", True, 5),
    ("Ganesh Steel & Gifts", "Bhiwandi", "27", True, 5),
    ("Balaji Mobile Care", "Ulhasnagar", "27", True, 4),
    ("Jai Bhavani Kitchenware", "Kalyan", "27", True, 4),
    ("Sai Darshan Mobile", "Ahmednagar", "27", True, 3),
    ("Laxmi Home Needs", "Thane", "27", True, 3),
    ("Kohinoor Telecom", "Mira Road", "27", True, 3),
    ("Swami Samarth Gifts", "Kolhapur", "27", True, 3),
    ("Fone Zone", "Navi Mumbai", "27", True, 3),
    ("Siddhivinayak Steel Bhandar", "Palghar", "27", True, 2),
    ("Aaradhya Mobile", "Aurangabad", "27", True, 2),
    ("Mobile Planet", "Nagpur", "27", True, 2),
    ("Shiv Shakti Electronics", "Shahapur", "27", True, 2),
    ("Raju Mobile Repair", "Bhiwandi", "27", False, 2),
    ("Ayesha Gift Corner", "Mumbra", "27", False, 2),
    ("Shubham Telecom", "Titwala", "27", False, 1),
    ("Star Electronics", "Surat", "24", True, 4),
    ("Vishal Gift House", "Vapi", "24", True, 2),
    ("Goa Mobile World", "Margao", "30", True, 2),
    ("Sagar Telecom", "Belagavi", "29", True, 2),
    ("Indore Mobile Bazaar", "Indore", "23", True, 2),
    ("Deccan Accessories", "Hyderabad", "36", True, 1),
]

ONLINE_STATES = [("27", 32), ("29", 10), ("07", 8), ("24", 8), ("09", 8), ("33", 7), ("36", 7),
                 ("19", 5), ("08", 5), ("32", 4), ("23", 3), ("30", 3)]

GSTIN_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"


def gstin(state, holder="F"):
    """A made-up GSTIN in the right format, with a valid check character."""
    letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    pan = "".join(rng.choice(letters) for _ in range(3)) + holder + rng.choice(letters)
    pan += "".join(rng.choice("0123456789") for _ in range(4)) + rng.choice(letters)
    body = state + pan + "1Z"
    total = 0
    for i, ch in enumerate(body):
        v = GSTIN_CHARS.index(ch) * (1 if i % 2 == 0 else 2)
        total += v // 36 + v % 36
    return body + GSTIN_CHARS[(36 - total % 36) % 36]


# --------------------------------------------------------------------------- demand model

def frac_of_year(d):
    return (d - START).days / (END - START).days


def trend(p, d):
    t0, t1 = p[10]
    dies = p[11]
    if dies:
        if d >= dies:
            return 0.0
        return t0 + (t1 - t0) * (d - START).days / (dies - START).days
    return t0 + (t1 - t0) * frac_of_year(d)


def festival_intensity(d, channel):
    """0..1: how deep into a festival rush this day is, for this channel."""
    best = 0.0
    for fest in DIWALI:
        before = (fest - d).days
        if channel == "b2b":
            # Retailers stock up 1-6 weeks ahead
            if 7 <= before <= 45:
                best = max(best, 1.0 if before <= 30 else (45 - before) / 15)
        else:
            # Shoppers buy in the last three weeks, peaking on Dhanteras (2 days before)
            if 0 <= before <= 21:
                best = max(best, 1.0 if before <= 3 else (21 - before) / 18)
    return best


def ganesh_intensity(d, channel):
    for fest in GANESH_CHATURTHI:
        before = (fest - d).days
        lead = 30 if channel == "b2b" else 10
        if 0 <= before <= lead:
            return 1.0
    return 0.0


def post_diwali(d):
    return any(0 < (d - f).days <= 12 for f in DIWALI)


def wedding_season(d):
    return (d.month == 11 and d.day >= 15) or d.month in (12, 1, 2)


def monsoon(d):
    return dt.date(d.year, 6, 10) <= d <= dt.date(d.year, 9, 15)


CHANNELS = {
    # invoices/day, weekday factors Mon..Sun, line-count weights
    "counter": (27, [0.85, 0.9, 0.9, 0.95, 1.0, 1.2, 1.3], [0.62, 0.28, 0.10]),
    "b2b": (5.0, [1.25, 1.0, 1.0, 1.0, 1.0, 0.8, 0.0], [0.05, 0.10, 0.20, 0.25, 0.20, 0.12, 0.08]),
    "online": (8, [1.0, 0.95, 0.95, 1.0, 1.0, 1.05, 1.15], [0.85, 0.15]),
}


def invoices_expected(channel, d):
    base, dow, _ = CHANNELS[channel]
    rate = base * dow[d.weekday()]
    fi = festival_intensity(d, channel)
    if channel == "counter":
        rate *= 1 + 1.0 * fi
        if post_diwali(d):
            rate *= 0.7
        if monsoon(d):
            rate *= 0.82
    elif channel == "b2b":
        rate *= (1 + 0.5 * fi) * (1 + 0.12 * frac_of_year(d))
        if d.month == 3:
            rate *= 1.15
        if monsoon(d):
            rate *= 0.9
    else:
        rate *= (1 + 0.9 * fi) * (1 + 0.45 * frac_of_year(d))
    return rate


def weight(p, channel, d):
    ci = {"counter": 0, "b2b": 1, "online": 2}[channel]
    w = p[9][ci] * trend(p, d)
    fi = festival_intensity(d, channel)
    w *= 1 + (p[12] - 1) * fi
    if p[0] == 28:
        w *= 1 + 14 * ganesh_intensity(d, channel)
    if wedding_season(d):
        w *= p[13]
    return w


def qty_for(p, channel, size=1):
    if channel == "counter":
        return rng.choices([1, 2, 3], [0.85, 0.12, 0.03])[0]
    if channel == "online":
        return rng.choices([1, 2], [0.9, 0.1])[0]
    unit_cost = p[7]
    if unit_cost < 80:
        packs = [10, 20, 25, 50]
    elif unit_cost < 400:
        packs = [3, 5, 10, 12]
    elif unit_cost < 1000:
        packs = [2, 3, 5, 6]
    else:
        packs = [1, 2, 2, 3]
    q = rng.choice(packs)
    if size >= 6:
        q = int(q * rng.choice([1, 1.5, 2]))
    return q


def expected_daily_units(p, d, ignore_festivals=True):
    """Expected sales per day without stock limits. The owner's reorder levels come from this."""
    total = 0.0
    for ch, (_, _, line_w) in CHANNELS.items():
        inv = sum(invoices_expected(ch, d + dt.timedelta(k)) for k in range(7)) / 7
        lines = sum((i + 1) * w for i, w in enumerate(line_w))
        ws = [weight(q, ch, d) for q in P]
        if ignore_festivals:
            ws = [q[9][{"counter": 0, "b2b": 1, "online": 2}[ch]] * trend(q, d) for q in P]
        share = ws[p[0] - 1] / sum(ws)
        avg_qty = {"counter": 1.18, "online": 1.1}.get(ch)
        if avg_qty is None:
            c = p[7]
            avg_qty = 26 if c < 80 else 7.5 if c < 400 else 4 if c < 1000 else 2
            avg_qty *= 1.15
        total += inv * lines * share * avg_qty
    return total


def poisson(lam):
    if lam <= 0:
        return 0
    if lam > 40:
        return max(0, int(round(rng.gauss(lam, math.sqrt(lam)))))
    l, k, prod = math.exp(-lam), 0, rng.random()
    while prod > l:
        k += 1
        prod *= rng.random()
    return k


def cost_on(pid, d):
    c = P[pid - 1][7]
    for ids, since, mult in COST_CHANGES:
        if pid in ids and d >= since:
            c *= mult
    return round(c, 2)


def r2(x):
    return round(x + 1e-9, 2)


def fy_codes(d):
    y = d.year if d.month >= 4 else d.year - 1
    return {"fy": f"{y % 100:02d}-{(y + 1) % 100:02d}", "fy2": f"{y % 100:02d}{(y + 1) % 100:02d}", "cy": str(d.year)}


def time_on(d, channel):
    if channel == "counter":
        hour = rng.choices(range(10, 22), [3, 5, 8, 9, 7, 5, 4, 6, 9, 10, 8, 4])[0]
    elif channel == "b2b":
        hour = rng.choices(range(10, 19), [6, 9, 9, 7, 5, 7, 8, 6, 3])[0]
    else:
        hour = rng.choices(range(24), [2, 1, 1, 0.5, 0.5, 0.5, 1, 2, 3, 4, 5, 5, 6, 5, 5, 5, 5, 6, 7, 8, 9, 10, 9, 5])[0]
    return dt.datetime(d.year, d.month, d.day, hour, rng.randrange(60), rng.randrange(60))


# --------------------------------------------------------------------------- simulation

def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)

    customers = []
    for i, (name, city, state, registered, size) in enumerate(CUSTOMERS, start=1):
        customers.append((i, name, gstin(state, "F" if i % 3 else "P") if registered else None, state, city, size))
    cust_weights = [c[5] for c in customers]

    # Owner's rules of thumb, set from last year's typical (non-festival) sales.
    policy = {}
    for p in P:
        d0 = expected_daily_units(p, START)
        lead = LEAD[p[6]]
        rop = math.ceil(d0 * (lead + 3))
        qty = max(p[14], int(math.ceil(d0 * 21 / p[14])) * p[14])
        policy[p[0]] = (rop, qty, d0)

    # Opening stock on 1 Oct 2025. Festival items were bought in September for Diwali,
    # sized on a hunch (more than the rush turned out to need).
    stock = {}
    opening = []
    diwali_guess = {26: 520, 27: 180, 28: 260}
    for p in P:
        if p[0] in FESTIVE_ITEMS:
            q = diwali_guess[p[0]]
        else:
            q = int(round(policy[p[0]][2] * p[15] * rng.uniform(0.85, 1.15) * (1 + 0.5 * (p[12] - 1))))
            if p[0] in (24, 25):
                q = int(q * 2.2)  # dinner sets and kadais stocked for Dhanteras
        stock[p[0]] = q
        opening.append((p[0], START.isoformat(), q, cost_on(p[0], START)))

    pending = []  # (arrival date, supplier, [(pid, qty)])
    purchase_invoices, purchase_items = [], []
    sales_invoices, sales_items = [], []
    sup_counter = {1: 812, 2: 1140, 3: 3050, 4: 4410, 5: 96}
    sup_fy = {}
    sale_serial = {}
    on_order = {p[0]: 0 for p in P}

    d = START
    while d <= END:
        # 1. Goods and bills that arrive today
        for arr in [x for x in pending if x[0] == d]:
            pending.remove(arr)
            _, sid, lines = arr
            codes = fy_codes(d)
            key = codes["cy"] if sid == 3 else codes["fy"]
            if sup_fy.get(sid) != key:
                if sid in sup_fy and sid in (1, 2, 5):
                    sup_counter[sid] = rng.randint(5, 25)  # supplier's numbering resets each FY
                sup_fy[sid] = key
            sup_counter[sid] += rng.randint(3, 14)
            inv_no = SUPPLIERS[sid - 1][6].format(n=sup_counter[sid], **codes)
            pid_inv = len(purchase_invoices) + 1
            taxable = 0.0
            tax = 0.0
            for ln, (pid, q) in enumerate(lines, start=1):
                rate = cost_on(pid, d - dt.timedelta(LEAD[sid]))
                tv = r2(q * rate)
                g = P[pid - 1][5]
                taxable += tv
                tax += tv * g / 100
                purchase_items.append((pid_inv, ln, pid, q, rate, tv, g))
                stock[pid] += q
                on_order[pid] -= q
            taxable = r2(taxable)
            if SUP_STATE[sid] == HOME_STATE:
                cgst = sgst = r2(tax / 2)
                igst = 0.0
            else:
                cgst = sgst = 0.0
                igst = r2(tax)
            gross = taxable + cgst + sgst + igst
            total = round(gross)
            purchase_invoices.append((pid_inv, sid, inv_no, d.isoformat(), taxable, cgst, sgst, igst,
                                      r2(total - gross), float(total)))

        # 2. Sales
        if d not in CLOSED:
            day_invoices = []
            for ch, (_, _, line_w) in CHANNELS.items():
                n = poisson(invoices_expected(ch, d))
                ws = [weight(p, ch, d) for p in P]
                for _ in range(n):
                    k = rng.choices(range(1, len(line_w) + 1), line_w)[0]
                    chosen = []
                    pool = list(range(len(P)))
                    pw = ws[:]
                    for _ in range(k):
                        if sum(pw[i] for i in pool) <= 0:
                            break
                        i = rng.choices(pool, [pw[j] for j in pool])[0]
                        pool.remove(i)
                        chosen.append(P[i])
                    cust = None
                    size = 1
                    if ch == "b2b":
                        cust = rng.choices(customers, cust_weights)[0]
                        size = cust[5]
                        pos = cust[3]
                    elif ch == "online":
                        pos = rng.choices([s for s, _ in ONLINE_STATES], [w for _, w in ONLINE_STATES])[0]
                    else:
                        pos = HOME_STATE
                    lines = []
                    for p in chosen:
                        want = qty_for(p, ch, size)
                        q = min(want, stock[p[0]])
                        if q <= 0:
                            continue  # out of stock: the sale is lost and nothing is recorded
                        stock[p[0]] -= q
                        g = p[5]
                        if ch == "counter":
                            rate = r2(p[8] / (1 + g / 100))
                        elif ch == "online":
                            rate = r2(round(p[8] * 0.95) / (1 + g / 100))
                        else:
                            rate = r2(cost_on(p[0], d) * B2B_MARKUP[p[3]])
                        disc = 0.0
                        if ch == "counter" and rng.random() < 0.08:
                            disc = r2(rate * q * rng.uniform(0.03, 0.10))
                        lines.append((p[0], q, rate, disc, r2(rate * q - disc), g))
                    if not lines:
                        continue
                    pay = {"counter": lambda: rng.choices(["upi", "cash", "card"], [0.6, 0.34, 0.06])[0],
                           "b2b": lambda: rng.choices(["credit", "upi", "bank"], [0.7, 0.2, 0.1])[0],
                           "online": lambda: rng.choices(["upi", "card"], [0.7, 0.3])[0]}[ch]()
                    day_invoices.append((time_on(d, ch), ch, cust[0] if cust else None, pos, pay, lines))

            day_invoices.sort(key=lambda x: x[0])
            for ts, ch, cid, pos, pay, lines in day_invoices:
                codes = fy_codes(d)
                sale_serial[codes["fy"]] = sale_serial.get(codes["fy"], 0) + 1
                sid = len(sales_invoices) + 1
                taxable = r2(sum(l[4] for l in lines))
                tax = sum(l[4] * l[5] / 100 for l in lines)
                if pos == HOME_STATE:
                    cgst = sgst = r2(tax / 2)
                    igst = 0.0
                else:
                    cgst = sgst = 0.0
                    igst = r2(tax)
                gross = taxable + cgst + sgst + igst
                total = round(gross)
                sales_invoices.append((sid, f"KIT/{codes['fy']}/{sale_serial[codes['fy']]:05d}", ts.isoformat(sep=" "),
                                       ch, cid, pos, pay, taxable, cgst, sgst, igst, r2(total - gross), float(total)))
                for ln, (pid, q, rate, disc, tv, g) in enumerate(lines, start=1):
                    sales_items.append((sid, ln, pid, q, rate, disc, tv, g))

        # 3. Owner checks the shelves on Mondays and Thursdays and phones suppliers
        if d.weekday() in (0, 3) and d < END:
            orders = {}
            for p in P:
                rop, qty, _ = policy[p[0]]
                if p[0] in FESTIVE_ITEMS:
                    continue  # festival stock is bought once a year, by hand
                if stock[p[0]] + on_order[p[0]] <= rop:
                    orders.setdefault(p[6], []).append((p[0], qty))
                    on_order[p[0]] += qty
            for sid, lines in orders.items():
                arrive = d + dt.timedelta(LEAD[sid] + rng.choice([0, 0, 1, 1, 2]))
                while arrive in CLOSED or arrive.weekday() == 6:
                    arrive += dt.timedelta(1)
                pending.append((arrive, sid, lines))
        d += dt.timedelta(1)

    # Write CSVs
    def write(name, header, rows):
        with open(os.path.join(out_dir, name + ".csv"), "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(header)
            for r in rows:
                w.writerow(["" if v is None else v for v in r])

    write("suppliers", ["supplier_id", "name", "gstin", "state_code", "city", "lead_time_days"],
          [s[:6] for s in SUPPLIERS])
    write("products", ["product_id", "sku", "name", "category", "hsn", "gst_rate", "unit", "supplier_id", "pack_size"],
          [(p[0], p[1], p[2], p[3], p[4], p[5], p[16], p[6], p[14]) for p in P])
    write("customers", ["customer_id", "name", "gstin", "state_code", "city"], [c[:5] for c in customers])
    write("opening_stock", ["product_id", "as_of", "qty", "unit_cost"], opening)
    write("purchase_invoices", ["purchase_id", "supplier_id", "invoice_no", "invoice_date", "taxable_value",
                                "cgst", "sgst", "igst", "round_off", "grand_total"], purchase_invoices)
    write("purchase_items", ["purchase_id", "line_no", "product_id", "qty", "rate", "taxable_value", "gst_rate"],
          purchase_items)
    write("sales_invoices", ["sale_id", "invoice_no", "invoice_ts", "channel", "customer_id", "place_of_supply",
                             "payment_mode", "taxable_value", "cgst", "sgst", "igst", "round_off", "grand_total"],
          sales_invoices)
    write("sales_items", ["sale_id", "line_no", "product_id", "qty", "rate", "discount", "taxable_value", "gst_rate"],
          sales_items)

    print(f"{len(sales_invoices)} sales invoices, {len(sales_items)} sales lines, "
          f"{len(purchase_invoices)} purchase bills, {len(purchase_items)} purchase lines -> {out_dir}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "data"))
