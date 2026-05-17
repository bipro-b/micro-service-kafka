const express = require("express");
const client = require("prom-client");

const app = express();
app.use(express.json());

// ── Prometheus setup ──────────────────────────────────────────────────────────
const register = new client.Registry();
register.setDefaultLabels({ service: "product-service" });
client.collectDefaultMetrics({ register });

const httpRequestsTotal = new client.Counter({
  name: "http_requests_total",
  help: "Total number of HTTP requests",
  labelNames: ["service", "method", "route", "status_code"],
  registers: [register],
});

const httpRequestDurationSeconds = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "HTTP request latency in seconds",
  labelNames: ["service", "method", "route"],
  buckets: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1],
  registers: [register],
});

const productsInStock = new client.Gauge({
  name: "products_in_stock_total",
  help: "Total units of all products currently in stock",
  registers: [register],
});

const productCatalogSize = new client.Gauge({
  name: "product_catalog_size",
  help: "Number of distinct products in the catalog",
  registers: [register],
});

// ── Instrumentation middleware ────────────────────────────────────────────────
app.use((req, res, next) => {
  const start = Date.now();
  res.on("finish", () => {
    const route = req.route?.path ?? req.path;
    const dur = (Date.now() - start) / 1000;
    httpRequestsTotal.inc({ service: "product-service", method: req.method, route, status_code: String(res.statusCode) });
    httpRequestDurationSeconds.observe({ service: "product-service", method: req.method, route }, dur);
  });
  next();
});

// ── Product catalog ───────────────────────────────────────────────────────────
const PRODUCTS = [
  { id: "p1",  name: "MacBook Pro 16",           category: "laptops",     price: 2499.99, stock: 15, brand: "Apple" },
  { id: "p2",  name: "Dell XPS 15",              category: "laptops",     price: 1899.99, stock: 8,  brand: "Dell" },
  { id: "p3",  name: "iPhone 15 Pro",            category: "phones",      price: 999.99,  stock: 42, brand: "Apple" },
  { id: "p4",  name: "Samsung Galaxy S24 Ultra", category: "phones",      price: 1199.99, stock: 31, brand: "Samsung" },
  { id: "p5",  name: "Sony WH-1000XM5",         category: "audio",       price: 349.99,  stock: 24, brand: "Sony" },
  { id: "p6",  name: "AirPods Pro 2nd Gen",      category: "audio",       price: 249.99,  stock: 57, brand: "Apple" },
  { id: "p7",  name: "LG 27UK850 4K Monitor",   category: "monitors",    price: 499.99,  stock: 12, brand: "LG" },
  { id: "p8",  name: "Keychron K2 Keyboard",    category: "keyboards",   price: 89.99,   stock: 63, brand: "Keychron" },
  { id: "p9",  name: "Logitech MX Master 3S",   category: "mice",        price: 99.99,   stock: 78, brand: "Logitech" },
  { id: "p10", name: "Anker USB-C Hub 10-in-1", category: "accessories", price: 49.99,   stock: 145, brand: "Anker" },
  { id: "p11", name: "SanDisk Extreme SSD 1TB", category: "storage",     price: 89.99,   stock: 93, brand: "SanDisk" },
  { id: "p12", name: "Corsair Vengeance 32GB",  category: "memory",      price: 129.99,  stock: 28, brand: "Corsair" },
];

productsInStock.set(PRODUCTS.reduce((sum, p) => sum + p.stock, 0));
productCatalogSize.set(PRODUCTS.length);

// ── Routes ────────────────────────────────────────────────────────────────────
app.get("/health", (req, res) =>
  res.json({ status: "ok", service: "product-service", catalogSize: PRODUCTS.length })
);

app.get("/products", (req, res) => {
  let list = PRODUCTS;
  if (req.query.category) {
    list = list.filter((p) => p.category === req.query.category);
  }
  if (req.query.brand) {
    list = list.filter((p) => p.brand.toLowerCase() === req.query.brand.toLowerCase());
  }
  res.json(list);
});

app.get("/products/:id", (req, res) => {
  const product = PRODUCTS.find((p) => p.id === req.params.id);
  if (!product) return res.status(404).json({ error: "product not found", id: req.params.id });
  res.json(product);
});

app.get("/metrics", async (req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

app.listen(4001, () => console.log("Product Service v2 running on port 4001"));
