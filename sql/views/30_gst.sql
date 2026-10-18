-- Monthly GST summary, laid out like GSTR-3B: tax collected on sales (output tax),
-- tax paid on purchases that can be claimed back (input tax credit, ITC), and the
-- cash to pay.
--
-- Unused credit carries forward to the next month. Because each month depends on the
-- one before, the running balance is a recursive query.
--
-- Simplified: CGST, SGST and IGST credit are pooled. The real set-off order (IGST
-- credit first, CGST credit can't pay SGST, and so on) can move money between heads,
-- so treat this as an estimate and let your CA file the return.

create or replace view shop.v_gst_monthly as
with recursive
outward as (
    select date_trunc('month', s.invoice_ts)::date              as month,
           sum(s.taxable_value)                                 as taxable_sales,
           sum(s.taxable_value) filter (where c.gstin is not null) as b2b_taxable,   -- GSTR-1 table 4
           sum(s.taxable_value) filter (where c.gstin is null)     as b2c_taxable,   -- GSTR-1 tables 5 and 7
           sum(s.cgst) as out_cgst, sum(s.sgst) as out_sgst, sum(s.igst) as out_igst
    from shop.sales_invoices s
    left join shop.customers c using (customer_id)
    group by 1
),
inward as (
    select date_trunc('month', invoice_date)::date as month,
           sum(taxable_value)                      as taxable_purchases,
           sum(cgst) as itc_cgst, sum(sgst) as itc_sgst, sum(igst) as itc_igst
    from shop.purchase_invoices
    group by 1
),
months as (
    select coalesce(o.month, i.month)                                   as month,
           coalesce(o.taxable_sales, 0)                                 as taxable_sales,
           coalesce(o.b2b_taxable, 0)                                   as b2b_taxable,
           coalesce(o.b2c_taxable, 0)                                   as b2c_taxable,
           coalesce(o.out_cgst, 0) as out_cgst, coalesce(o.out_sgst, 0) as out_sgst, coalesce(o.out_igst, 0) as out_igst,
           coalesce(o.out_cgst + o.out_sgst + o.out_igst, 0)            as output_tax,
           coalesce(i.taxable_purchases, 0)                             as taxable_purchases,
           coalesce(i.itc_cgst, 0) as itc_cgst, coalesce(i.itc_sgst, 0) as itc_sgst, coalesce(i.itc_igst, 0) as itc_igst,
           coalesce(i.itc_cgst + i.itc_sgst + i.itc_igst, 0)            as itc,
           row_number() over (order by coalesce(o.month, i.month))      as n
    from outward o
    full join inward i using (month)
),
ledger as (
    select n, 0::numeric as credit_brought_forward,
           greatest(output_tax - itc, 0) as cash_payable,
           greatest(itc - output_tax, 0) as credit_carried_forward
    from months where n = 1
    union all
    select m.n, l.credit_carried_forward,
           greatest(m.output_tax - m.itc - l.credit_carried_forward, 0),
           greatest(m.itc + l.credit_carried_forward - m.output_tax, 0)
    from months m
    join ledger l on m.n = l.n + 1
)
select m.month, m.taxable_sales, m.b2b_taxable, m.b2c_taxable,
       m.out_cgst, m.out_sgst, m.out_igst, m.output_tax,
       m.taxable_purchases, m.itc_cgst, m.itc_sgst, m.itc_igst, m.itc,
       l.credit_brought_forward, l.cash_payable, l.credit_carried_forward
from months m
join ledger l using (n);


-- HSN-wise summary of outward supplies (GSTR-1 table 12), by month.
create or replace view shop.v_gst_hsn_monthly as
select date_trunc('month', s.invoice_ts)::date                                         as month,
       p.hsn,
       string_agg(distinct p.category, ', ')                                           as description,
       p.unit                                                                          as uqc,
       i.gst_rate,
       sum(i.qty)                                                                      as total_qty,
       sum(i.taxable_value)                                                            as taxable_value,
       round(sum(i.taxable_value * i.gst_rate / 100) filter (where s.place_of_supply <> b.state_code), 2) as igst,
       round(sum(i.taxable_value * i.gst_rate / 200) filter (where s.place_of_supply =  b.state_code), 2) as cgst,
       round(sum(i.taxable_value * i.gst_rate / 200) filter (where s.place_of_supply =  b.state_code), 2) as sgst
from shop.sales_invoices s
join shop.sales_items i using (sale_id)
join shop.products p    using (product_id)
cross join shop.business b
group by 1, p.hsn, p.unit, i.gst_rate;
