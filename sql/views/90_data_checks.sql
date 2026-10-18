-- Data checks. A dashboard is only as good as the bills under it, so the build
-- stops if any of these finds a problem. Each row: what was checked, how many failed.

-- GSTIN: 2-digit state, PAN, entity number, 'Z', then a check character computed
-- from the first 14 (each character's value times 1 or 2, digits summed in base 36).
create or replace function shop.gstin_is_valid(g text) returns boolean
language sql immutable as $$
    select g ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'
       and substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ',
                  (36 - (select sum(v / 36 + v % 36)
                         from (select (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ', substr(g, i, 1)) - 1)
                                      * (2 - i % 2) as v
                               from generate_series(1, 14) i) chars)::int % 36) % 36 + 1, 1)
           = substr(g, 15, 1)
$$;

create or replace view shop.v_data_checks as
with sale_lines as (
    select sale_id, sum(taxable_value) as taxable, sum(taxable_value * gst_rate / 100) as tax
    from shop.sales_items group by sale_id
),
purchase_lines as (
    select purchase_id, sum(taxable_value) as taxable from shop.purchase_items group by purchase_id
),
serials as (                -- KIT/25-26/00042 -> financial year 25-26, serial 42
    select split_part(invoice_no, '/', 2) as fy, split_part(invoice_no, '/', 3)::int as serial
    from shop.sales_invoices
)
select 'Sales invoice totals match their lines' as check_name,
       (select count(*) from shop.sales_invoices s join sale_lines l using (sale_id)
        where s.taxable_value <> l.taxable) as failures
union all
select 'Purchase bill totals match their lines',
       (select count(*) from shop.purchase_invoices p join purchase_lines l using (purchase_id)
        where p.taxable_value <> l.taxable)
union all
select 'GST on each sales invoice matches its lines (within Rs 1)',
       (select count(*) from shop.sales_invoices s join sale_lines l using (sale_id)
        where abs(s.cgst + s.sgst + s.igst - l.tax) > 1)
union all
select 'Same-state bills charge CGST + SGST, other states IGST',
       (select count(*) from shop.sales_invoices s cross join shop.business b
        where (s.place_of_supply = b.state_code and (s.igst <> 0 or s.cgst <> s.sgst))
           or (s.place_of_supply <> b.state_code and (s.cgst <> 0 or s.sgst <> 0)))
     + (select count(*) from shop.purchase_invoices p join shop.suppliers sup using (supplier_id)
        cross join shop.business b
        where (sup.state_code = b.state_code and (p.igst <> 0 or p.cgst <> p.sgst))
           or (sup.state_code <> b.state_code and (p.cgst <> 0 or p.sgst <> 0)))
union all
select 'Grand total = taxable value + GST + round-off',
       (select count(*) from shop.sales_invoices
        where grand_total <> taxable_value + cgst + sgst + igst + round_off)
     + (select count(*) from shop.purchase_invoices
        where grand_total <> taxable_value + cgst + sgst + igst + round_off)
union all
select 'Invoice numbers run 1, 2, 3... with no gaps in each financial year',
       (select count(*) from (select fy from serials group by fy
                              having min(serial) <> 1 or max(serial) <> count(*)
                                  or count(distinct serial) <> count(*)) gaps)
union all
select 'Stock never goes below zero',
       (select count(*) from shop.v_daily_stock where closing_qty < 0)
union all
select 'Every GSTIN has a valid format and check character',
       (select count(*) from shop.customers where gstin is not null and not shop.gstin_is_valid(gstin))
     + (select count(*) from shop.suppliers where not shop.gstin_is_valid(gstin))
     + (select count(*) from shop.business where not shop.gstin_is_valid(gstin))
union all
select 'Every sale has a cost price',
       (select count(*) from shop.sales_items) - (select count(*) from shop.v_sales_lines);
