-- ドリンクPOS: Supabase スキーマ
-- Supabase ダッシュボード → SQL Editor に全文貼り付けて Run するだけ

create table products (
  id uuid primary key,
  name text not null,
  category text not null check (category in ('soft','nonal','can','draft','craft')),
  location text not null default '坂下',  -- 販売所。商品は販売所に属する
  price integer not null check (price >= 0),
  sort_order integer not null default 0,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table stock_events (
  id uuid primary key,
  product_id uuid not null references products(id),
  qty_delta integer not null,
  type text not null check (type in ('initial','restock','loss','adjust')),
  reason text,
  device text,
  created_at timestamptz not null default now()
);

create table sales (
  id uuid primary key,
  device text,
  location text,  -- 会計時の販売所
  items jsonb not null,
  payment text not null check (payment in ('cash','paypay')),
  total integer not null,
  cash_received integer,
  change integer,
  status text not null default 'completed' check (status in ('completed','cancelled')),
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  updated_at timestamptz not null default now()
);

create table cash_counts (
  id uuid primary key,
  location text,  -- 点検した販売所
  counted_amount integer not null,
  float_amount integer not null default 0,
  theoretical_amount integer not null,
  diff integer not null,
  note text,
  created_at timestamptz not null default now()
);

-- 端末のハートビート(棚卸し前の「未送信あり」警告に使う)
create table devices (
  id text primary key,
  name text,
  pending integer not null default 0,
  last_seen timestamptz not null default now()
);

-- スタッフ名簿
create table staff (
  id uuid primary key,
  name text not null,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

-- スタッフが在庫から飲んだ記録(1レコード=1本。売上ではない)
create table staff_drinks (
  id uuid primary key,
  staff_id uuid not null references staff(id),
  staff_name text not null,
  product_id uuid not null references products(id),
  product_name text not null,
  location text,
  device text,
  cancelled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 開催情報(開催日・OPEN/END・タイムテーブル・シフト)。1行のみ、上書き更新
create table event_config (
  id integer primary key,
  data jsonb not null,
  updated_at timestamptz not null default now()
);

-- 更新時に updated_at を自動更新(取消の同期検知に必要)
create or replace function touch_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end $$ language plpgsql;

create trigger products_touch before update on products
  for each row execute function touch_updated_at();
create trigger sales_touch before update on sales
  for each row execute function touch_updated_at();
create trigger staff_touch before update on staff
  for each row execute function touch_updated_at();
create trigger staff_drinks_touch before update on staff_drinks
  for each row execute function touch_updated_at();
create trigger event_config_touch before update on event_config
  for each row execute function touch_updated_at();

-- RLS: 1日イベントの簡易運用として anon キーに全権限を与える。
-- URL と anon キーの組が実質のパスワードなので、共有リンクを部外者に渡さないこと。
alter table products enable row level security;
alter table stock_events enable row level security;
alter table sales enable row level security;
alter table cash_counts enable row level security;
alter table devices enable row level security;
alter table staff enable row level security;
alter table staff_drinks enable row level security;
alter table event_config enable row level security;

create policy anon_all on products for all using (true) with check (true);
create policy anon_all on stock_events for all using (true) with check (true);
create policy anon_all on sales for all using (true) with check (true);
create policy anon_all on cash_counts for all using (true) with check (true);
create policy anon_all on devices for all using (true) with check (true);
create policy anon_all on staff for all using (true) with check (true);
create policy anon_all on staff_drinks for all using (true) with check (true);
create policy anon_all on event_config for all using (true) with check (true);

-- ジャンル一律価格(v2.1〜)。価格の正はここ。products.priceは旧版互換の複製
create table prices (
  category text primary key check (category in ('soft','nonal','can','draft','craft')),
  price integer not null check (price >= 0),
  updated_at timestamptz not null default now()
);
create trigger prices_touch before update on prices
  for each row execute function touch_updated_at();
alter table prices enable row level security;
create policy anon_all on prices for all using (true) with check (true);
insert into prices (category, price) values
  ('soft',200),('nonal',500),('can',500),('draft',600),('craft',800);

-- 釣り銭準備金(日別・販売所別、金種枚数つき) v2.1〜
create table cash_floats (
  id text primary key,              -- "YYYY-MM-DD|販売所"
  day date not null,
  location text not null,
  counts jsonb not null default '{}'::jsonb,
  total integer not null default 0,
  updated_at timestamptz not null default now()
);
create trigger cash_floats_touch before update on cash_floats
  for each row execute function touch_updated_at();
alter table cash_floats enable row level security;
create policy anon_all on cash_floats for all using (true) with check (true);

-- 【既存DBの移行用】上のcreate tableを旧版で実行済みの場合のみ、必要な行を実行する:
-- v1.4 カテゴリ4分類化:
--   alter table products drop constraint products_category_check;
--   alter table products add constraint products_category_check check (category in ('soft','nonal','can','draft'));
-- v1.6 販売所(2売り場)対応:
--   alter table products add column location text not null default '坂下';
--   alter table sales add column location text;
--   alter table cash_counts add column location text;
-- v2.0 スタッフドリンク・開催情報:
--   上の create table staff / staff_drinks / event_config と
--   対応する create trigger 3本・alter table〜enable row level security 3本・
--   create policy anon_all 3本をそのまま実行する
