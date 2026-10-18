-- Owner's dashboard: database schema (PostgreSQL 14+)
--
-- Two registers feed it:
--   purchases: supplier bills, read by Bill Reader (one row per bill + one per line item)
--   sales:     the shop's own invoices, exported from the billing app
-- Stock is never stored. It is always worked out as opening stock + purchases - sales,
-- so it can't drift from the bills.

drop schema if exists shop cascade;
create schema shop;
set search_path = shop;

-- The business itself. Its state decides CGST+SGST (same state) or IGST (other state).
create table business (
    name        text not null,
    gstin       char(15) not null,
    state_code  char(2) not null
);
insert into business values ('Kaveri Imports & Trading', '27AAPCK7731R1ZI', '27');

create table suppliers (
    supplier_id     smallint primary key,
    name            text not null,
    gstin           char(15) not null unique,
    state_code      char(2) not null,            -- first two digits of the GSTIN
    city            text not null,
    lead_time_days  smallint not null check (lead_time_days > 0)  -- order to goods on the shelf
);

create table products (
    product_id   smallint primary key,
    sku          text not null unique,
    name         text not null,
    category     text not null,
    hsn          text not null,
    gst_rate     numeric(4,1) not null check (gst_rate in (0, 5, 18, 40)),
    unit         text not null,
    supplier_id  smallint not null references suppliers,
    pack_size    int not null check (pack_size > 0)  -- the supplier sells in multiples of this
);

create table customers (
    customer_id  int primary key,
    name         text not null,
    gstin        char(15) unique,                 -- null = unregistered (B2C for GST)
    state_code   char(2) not null,
    city         text not null
);

create table opening_stock (
    product_id  smallint primary key references products,
    as_of       date not null,
    qty         int not null check (qty >= 0),
    unit_cost   numeric(10,2) not null
);

create table purchase_invoices (
    purchase_id    int primary key,
    supplier_id    smallint not null references suppliers,
    invoice_no     text not null,
    invoice_date   date not null,                 -- goods are counted in stock from this date
    taxable_value  numeric(12,2) not null,
    cgst           numeric(12,2) not null default 0,
    sgst           numeric(12,2) not null default 0,
    igst           numeric(12,2) not null default 0,
    round_off      numeric(6,2) not null default 0,
    grand_total    numeric(12,2) not null,
    unique (supplier_id, invoice_no)
);

create table purchase_items (
    purchase_id    int not null references purchase_invoices,
    line_no        smallint not null,
    product_id     smallint not null references products,
    qty            int not null check (qty > 0),
    rate           numeric(10,2) not null,        -- per unit, before GST
    taxable_value  numeric(12,2) not null,
    gst_rate       numeric(4,1) not null,
    primary key (purchase_id, line_no)
);

create table sales_invoices (
    sale_id          int primary key,
    invoice_no       text not null unique,        -- KIT/25-26/00001, restarts each financial year
    invoice_ts       timestamp not null,
    channel          text not null check (channel in ('counter', 'b2b', 'online')),
    customer_id      int references customers,    -- null for walk-in and online buyers
    place_of_supply  char(2) not null,            -- state code; 27 = Maharashtra (same state)
    payment_mode     text not null check (payment_mode in ('cash', 'upi', 'card', 'credit', 'bank')),
    taxable_value    numeric(12,2) not null,
    cgst             numeric(12,2) not null default 0,
    sgst             numeric(12,2) not null default 0,
    igst             numeric(12,2) not null default 0,
    round_off        numeric(6,2) not null default 0,
    grand_total      numeric(12,2) not null
);

create table sales_items (
    sale_id        int not null references sales_invoices,
    line_no        smallint not null,
    product_id     smallint not null references products,
    qty            int not null check (qty > 0),
    rate           numeric(10,2) not null,        -- per unit, before GST
    discount       numeric(10,2) not null default 0,
    taxable_value  numeric(12,2) not null,
    gst_rate       numeric(4,1) not null,
    primary key (sale_id, line_no)
);

-- Festivals that move demand. The owner adds next year's dates; the festival-prep
-- view compares stock with what sold before the same festival last year.
create table festivals (
    name           text not null,
    festival_date  date primary key,
    rush_days      smallint not null default 21  -- how many days before it shoppers start buying
);
insert into festivals values
    ('Diwali', '2025-10-20', 21),
    ('Ganesh Chaturthi', '2026-09-14', 10),
    ('Diwali', '2026-11-08', 21);

create index on sales_invoices (invoice_ts);
create index on sales_items (product_id);
create index on purchase_invoices (invoice_date);
create index on purchase_items (product_id);

-- The dashboard's "today": the date of the last sale in the data.
create function as_of() returns date language sql stable as $$
    select max(invoice_ts)::date from shop.sales_invoices
$$;
