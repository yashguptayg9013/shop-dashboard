-- Stock is worked out from the bills, never typed in:
--   closing stock = opening stock + everything bought - everything sold, day by day.

create or replace view shop.v_daily_stock as
with moves as (
    select product_id, as_of as day, qty as qty_in, 0 as qty_out
    from shop.opening_stock
    union all
    select pi.product_id, p.invoice_date, pi.qty, 0
    from shop.purchase_items pi
    join shop.purchase_invoices p using (purchase_id)
    union all
    select i.product_id, s.invoice_ts::date, 0, i.qty
    from shop.sales_items i
    join shop.sales_invoices s using (sale_id)
),
per_day as (
    select product_id, day, sum(qty_in) as qty_in, sum(qty_out) as qty_out
    from moves
    group by product_id, day
),
calendar as (              -- every product on every day, so days with no movement still get a row
    select p.product_id, d::date as day
    from shop.products p
    cross join generate_series((select min(as_of) from shop.opening_stock), shop.as_of(), interval '1 day') d
)
select c.product_id,
       c.day,
       coalesce(m.qty_in, 0)  as qty_in,
       coalesce(m.qty_out, 0) as qty_out,
       sum(coalesce(m.qty_in, 0) - coalesce(m.qty_out, 0))
           over (partition by c.product_id order by c.day) as closing_qty
from calendar c
left join per_day m using (product_id, day);


-- Stock on hand today, what it's worth at cost, and how fast it's moving.
create or replace view shop.v_stock_on_hand as
with today as (
    select product_id, closing_qty as qty
    from shop.v_daily_stock
    where day = shop.as_of()
),
current_cost as (
    select product_id, unit_cost
    from shop.v_cost_history
    where valid_to = 'infinity'
),
sales as (
    select product_id,
           max(sale_date)                                                    as last_sale,
           sum(qty) filter (where sale_date > shop.as_of() - 30)             as sold_30d,
           sum(qty) filter (where sale_date > shop.as_of() - 90)             as sold_90d
    from shop.v_sales_lines
    group by product_id
),
bought as (
    select pi.product_id, max(p.invoice_date) as last_purchase
    from shop.purchase_items pi
    join shop.purchase_invoices p using (purchase_id)
    group by pi.product_id
)
select p.product_id, p.sku, p.name as product, p.category,
       sup.name                                     as supplier,
       t.qty,
       c.unit_cost,
       round(t.qty * c.unit_cost, 2)                as stock_value,
       coalesce(s.sold_30d, 0)                      as sold_30d,
       coalesce(s.sold_90d, 0)                      as sold_90d,
       s.last_sale,
       shop.as_of() - s.last_sale                   as days_since_last_sale,
       b.last_purchase,
       round(t.qty / nullif(s.sold_90d / 90.0, 0))  as days_of_cover   -- at the last 90 days' pace
from shop.products p
join shop.suppliers sup using (supplier_id)
join today t            using (product_id)
join current_cost c     using (product_id)
left join sales s       using (product_id)
left join bought b      using (product_id);
