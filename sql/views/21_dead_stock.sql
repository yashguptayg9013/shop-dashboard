-- Dead stock: money sitting on the shelf.
--   Dead       no sale in 90 days
--   Slow       still sells, but there's more than six months of stock at the current pace
--   Seasonal   a festival item with stock left over: hold it for the next festival, don't discount it

create or replace view shop.v_dead_stock as
select s.product_id, s.sku, s.product, s.category, s.supplier,
       s.qty, s.unit_cost, s.stock_value,
       s.sold_90d, s.last_sale, s.days_since_last_sale, s.days_of_cover,
       s.last_purchase,
       case when z.is_seasonal                                       then 'Seasonal'
            when s.days_since_last_sale >= 90 or s.last_sale is null then 'Dead'
            else 'Slow' end                                          as status,
       z.rush_uplift
from shop.v_stock_on_hand s
left join shop.v_product_seasonality z using (product_id)
where s.qty > 0
  and (s.days_since_last_sale >= 90 or s.last_sale is null or s.days_of_cover > 180);
