const express = require("express");
const client = require("prom-client");
const publishOrderCreated = require("./kafkaProducer");

const app = express();
app.use(express.json());

// ── Prometheus setup ──────────────────────────────────────────────────────────
const register = new client.Registry();
register.setDefaultLabels({ service: "order-service" });
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

const ordersCreatedTotal = new client.Counter({
  name: "orders_created_total",
  help: "Total number of orders placed",
  labelNames: ["service"],
  registers: [register],
});

const orderValueDollars = new client.Histogram({
  name: "order_value_dollars",
  help: "Dollar value distribution of individual orders",
  labelNames: ["service"],
  buckets: [10, 25, 50, 100, 250, 500, 1000, 2000, 5000],
  registers: [register],
});

const ordersByStatus = new client.Gauge({
  name: "orders_by_status",
  help: "Current count of orders grouped by status",
  labelNames: ["service", "status"],
  registers: [register],
});

// ── Instrumentation middleware ────────────────────────────────────────────────
app.use((req, res, next) => {
  const start = Date.now();
  res.on("finish", () => {
    const route = req.route?.path ?? req.path;
    const dur = (Date.now() - start) / 1000;
    httpRequestsTotal.inc({ service: "order-service", method: req.method, route, status_code: String(res.statusCode) });
    httpRequestDurationSeconds.observe({ service: "order-service", method: req.method, route }, dur);
  });
  next();
});

// ── In-memory order store (seeded) ───────────────────────────────────────────
const orders = [
  { id: "1716800001000", userId: "u1", item: "Wireless Headphones", quantity: 1, price: 59.99,  status: "delivered", createdAt: new Date(Date.now() - 86400000).toISOString() },
  { id: "1716800002000", userId: "u2", item: "Mechanical Keyboard", quantity: 2, price: 129.99, status: "shipped",   createdAt: new Date(Date.now() - 43200000).toISOString() },
  { id: "1716800003000", userId: "u3", item: "USB-C Hub",           quantity: 1, price: 34.49,  status: "processing", createdAt: new Date(Date.now() - 3600000).toISOString() },
  { id: "1716800004000", userId: "u4", item: "SSD 1TB",             quantity: 1, price: 89.99,  status: "delivered", createdAt: new Date(Date.now() - 172800000).toISOString() },
  { id: "1716800005000", userId: "u5", item: "iPhone 15 Pro",       quantity: 1, price: 999.99, status: "shipped",   createdAt: new Date(Date.now() - 7200000).toISOString() },
];

const STATUS_FLOW = ["pending", "processing", "shipped", "delivered"];

function syncStatusGauges() {
  const counts = {};
  ["pending", "processing", "shipped", "delivered", "cancelled"].forEach((s) => (counts[s] = 0));
  orders.forEach((o) => { counts[o.status] = (counts[o.status] || 0) + 1; });
  Object.entries(counts).forEach(([status, count]) =>
    ordersByStatus.set({ service: "order-service", status }, count)
  );
}
syncStatusGauges();

// Simulate status progression every 30 s so the gauge changes over time
setInterval(() => {
  orders
    .filter((o) => o.status !== "delivered" && o.status !== "cancelled")
    .slice(0, 2)
    .forEach((o) => {
      const idx = STATUS_FLOW.indexOf(o.status);
      if (idx < STATUS_FLOW.length - 1) o.status = STATUS_FLOW[idx + 1];
    });
  syncStatusGauges();
}, 30000);

// ── Routes ────────────────────────────────────────────────────────────────────
app.get("/health", (req, res) =>
  res.json({ status: "ok", service: "order-service", totalOrders: orders.length })
);

app.get("/orders", (req, res) => res.json(orders));

app.post("/orders", async (req, res) => {
  const { userId, item, quantity = 1, price } = req.body;
  if (!userId || !item) {
    return res.status(400).json({ error: "userId and item are required" });
  }
  const orderPrice = price ?? parseFloat((Math.random() * 490 + 10).toFixed(2));
  const order = {
    id: Date.now().toString(),
    userId,
    item,
    quantity: Number(quantity),
    price: orderPrice,
    status: "pending",
    createdAt: new Date().toISOString(),
  };
  orders.push(order);
  ordersCreatedTotal.inc({ service: "order-service" });
  orderValueDollars.observe({ service: "order-service" }, orderPrice * order.quantity);
  syncStatusGauges();

  try {
    await publishOrderCreated(order);
  } catch (err) {
    console.error("Kafka publish failed (non-fatal):", err.message);
  }

  res.status(201).json({ message: "order created", order });
});

app.get("/metrics", async (req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

app.listen(4003, () => console.log("Order Service v2 running on port 4003"));
