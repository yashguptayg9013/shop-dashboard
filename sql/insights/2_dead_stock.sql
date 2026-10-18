-- Insight 2: Rs 73,000 is stuck in items customers stopped asking for, and most of
-- it was bought after their sales had started falling.

set search_path = shop;

-- What's dead, and what share of all stock it is
select status,
       count(*)                                                        as items,
       sum(stock_value)                                                as stock_value,
       round(100 * sum(stock_value) / (select sum(stock_value) from v_stock_on_hand), 1) as share_of_stock_pct,
       string_agg(sku || ' (' || days_since_last_sale || ' days)', ', ' order by stock_value desc) as items_and_days_since_sale
from v_dead_stock
group by status;

-- Bills for dead items in 2026, next to how many sold that month
with monthly as (
    select product_id, month, sum(qty) as sold
    from v_sales_lines
    group by product_id, month
)
select p.sku, pi.invoice_date, i.qty as bought, i.taxable_value as bill_value,
       m.sold as sold_that_month,
       first_value(m2.sold) over (partition by p.sku order by m2.month) as sold_jan_2026
from purchase_items i
join purchase_invoices pi using (purchase_id)
join products p using (product_id)
left join monthly m  on m.product_id = p.product_id and m.month = date_trunc('month', pi.invoice_date)
left join monthly m2 on m2.product_id = p.product_id and m2.month = '2026-01-01'
where p.product_id in (select product_id from v_dead_stock where status = 'Dead')
  and pi.invoice_date >= '2026-01-01'
order by p.sku, pi.invoice_date;
