-- What did each unit cost us, and what did we make on every sale?
--
-- Cost is the last purchase price on or before the sale date: the rate on the
-- latest supplier bill for that item (opening stock cost before the first bill).
-- It's how most small traders think about cost, and it shows supplier price
-- rises the month they land.

create or replace view shop.v_cost_history as
with prices as (
    select product_id, as_of as valid_from, unit_cost, 0 as source
    from shop.opening_stock
    union all
    select pi.product_id, p.invoice_date, round(sum(pi.taxable_value) / sum(pi.qty), 2), 1
    from shop.purchase_items pi
    join shop.purchase_invoices p using (purchase_id)
    group by pi.product_id, p.invoice_date
),
one_per_day as (           -- a bill dated the same day as opening stock wins
    select distinct on (product_id, valid_from) product_id, valid_from, unit_cost
    from prices
    order by product_id, valid_from, source desc
)
select product_id,
       valid_from,
       lead(valid_from, 1, 'infinity') over (partition by product_id order by valid_from) as valid_to,
       unit_cost
from one_per_day;


-- One row per line on a sales invoice, with cost and gross profit.
-- Revenue is the taxable value (before GST): GST is collected for the government.
create or replace view shop.v_sales_lines as
select s.sale_id,
       s.invoice_no,
       s.invoice_ts,
       s.invoice_ts::date                      as sale_date,
       date_trunc('month', s.invoice_ts)::date as month,
       s.channel,
       s.customer_id,
       s.place_of_supply,
       i.product_id,
       p.sku,
       p.name                                  as product,
       p.category,
       i.qty,
       i.taxable_value                         as revenue,
       c.unit_cost,
       round(i.qty * c.unit_cost, 2)           as cogs,
       i.taxable_value - round(i.qty * c.unit_cost, 2) as gross_profit
from shop.sales_invoices s
join shop.sales_items i   using (sale_id)
join shop.products p      using (product_id)
join shop.v_cost_history c
  on c.product_id = i.product_id
 and s.invoice_ts::date >= c.valid_from
 and s.invoice_ts::date <  c.valid_to;
