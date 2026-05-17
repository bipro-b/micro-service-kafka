const express = require("express");
const client = require("prom-client");
const startConsumer = require("./kafkaConsumer");

const app = express();

// ── Prometheus setup ──────────────────────────────────────────────────────────
const register = new client.Registry();
register.setDefaultLabels({ service: "user-service" });
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

const kafkaEventsReceived = new client.Counter({
  name: "kafka_events_received_total",
  help: "Total Kafka events consumed by user-service",
  labelNames: ["service", "event_type"],
  registers: [register],
});

// ── Instrumentation middleware ────────────────────────────────────────────────
app.use((req, res, next) => {
  const start = Date.now();
  res.on("finish", () => {
    const route = req.route?.path ?? req.path;
    const dur = (Date.now() - start) / 1000;
    httpRequestsTotal.inc({ service: "user-service", method: req.method, route, status_code: String(res.statusCode) });
    httpRequestDurationSeconds.observe({ service: "user-service", method: req.method, route }, dur);
  });
  next();
});

// ── User data ─────────────────────────────────────────────────────────────────
const USERS = [
  { id: "u1", name: "Bipro B",       email: "bipro@example.com",  role: "admin",  createdAt: "2024-01-10" },
  { id: "u2", name: "Alex Chen",     email: "alex@example.com",   role: "user",   createdAt: "2024-02-15" },
  { id: "u3", name: "Sarah Kim",     email: "sarah@example.com",  role: "user",   createdAt: "2024-03-01" },
  { id: "u4", name: "Raj Patel",     email: "raj@example.com",    role: "seller", createdAt: "2024-03-20" },
  { id: "u5", name: "Maria Gomez",   email: "maria@example.com",  role: "user",   createdAt: "2024-04-05" },
  { id: "u6", name: "Tom Lee",       email: "tom@example.com",    role: "seller", createdAt: "2024-04-18" },
  { id: "u7", name: "Emma Wilson",   email: "emma@example.com",   role: "user",   createdAt: "2024-05-02" },
  { id: "u8", name: "James Brown",   email: "james@example.com",  role: "user",   createdAt: "2024-05-15" },
];

// ── Kafka consumer ────────────────────────────────────────────────────────────
startConsumer(kafkaEventsReceived).catch((e) =>
  console.error("Kafka consumer failed to start:", e.message)
);

// ── Routes ────────────────────────────────────────────────────────────────────
app.get("/health", (req, res) =>
  res.json({ status: "ok", service: "user-service", totalUsers: USERS.length })
);

app.get("/users", (req, res) => res.json(USERS));

app.get("/users/:id", (req, res) => {
  const user = USERS.find((u) => u.id === req.params.id);
  if (!user) return res.status(404).json({ error: "user not found", id: req.params.id });
  res.json(user);
});

app.get("/metrics", async (req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

app.listen(4002, () => console.log("User Service v2 running on port 4002"));
