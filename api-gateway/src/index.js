const express = require("express");
const axios = require("axios");
const client = require("prom-client");
const rateLimit = require("express-rate-limit");

const app = express();
app.use(express.json());

// ── Prometheus setup ──────────────────────────────────────────────────────────
const register = new client.Registry();
register.setDefaultLabels({ service: "api-gateway" });
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
  labelNames: ["service", "method", "route", "status_code"],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5],
  registers: [register],
});

const upstreamRequestsTotal = new client.Counter({
  name: "upstream_requests_total",
  help: "Total upstream service calls from the gateway",
  labelNames: ["upstream", "method", "status"],
  registers: [register],
});

const upstreamLatencySeconds = new client.Histogram({
  name: "upstream_latency_seconds",
  help: "Latency of upstream service calls",
  labelNames: ["upstream", "method"],
  buckets: [0.005, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2],
  registers: [register],
});

const activeConnections = new client.Gauge({
  name: "active_http_connections",
  help: "Current number of in-flight HTTP connections",
  labelNames: ["service"],
  registers: [register],
});

// ── Rate limiter ──────────────────────────────────────────────────────────────
const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many requests — try again in 60 seconds" },
});
app.use(limiter);

// ── Request instrumentation middleware ────────────────────────────────────────
app.use((req, res, next) => {
  req.startEpoch = Date.now();
  req.requestId = `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
  res.setHeader("X-Request-ID", req.requestId);
  activeConnections.inc({ service: "api-gateway" });

  res.on("finish", () => {
    activeConnections.dec({ service: "api-gateway" });
    const duration = (Date.now() - req.startEpoch) / 1000;
    const route = req.route?.path ?? req.path;
    const labels = {
      service: "api-gateway",
      method: req.method,
      route,
      status_code: String(res.statusCode),
    };
    httpRequestsTotal.inc(labels);
    httpRequestDurationSeconds.observe(labels, duration);
  });
  next();
});

// ── Upstream proxy helper ─────────────────────────────────────────────────────
async function proxy(upstream, method, url, body) {
  const timer = upstreamLatencySeconds.startTimer({ upstream, method });
  try {
    const resp =
      method === "POST"
        ? await axios.post(url, body, { timeout: 5000 })
        : await axios.get(url, { timeout: 5000 });
    timer();
    upstreamRequestsTotal.inc({ upstream, method, status: "success" });
    return { data: resp.data, statusCode: resp.status };
  } catch (err) {
    timer();
    upstreamRequestsTotal.inc({ upstream, method, status: "error" });
    throw err;
  }
}

// ── Routes ────────────────────────────────────────────────────────────────────
app.get("/health", (req, res) =>
  res.json({ status: "ok", service: "api-gateway", ts: new Date().toISOString() })
);

app.get("/products", async (req, res) => {
  try {
    const qs = req.url.includes("?") ? `?${req.url.split("?")[1]}` : "";
    const { data } = await proxy("product-service", "GET", `http://product-service:4001/products${qs}`);
    res.json(data);
  } catch (err) {
    res.status(502).json({ error: "product-service unavailable", requestId: req.requestId });
  }
});

app.get("/products/:id", async (req, res) => {
  try {
    const { data } = await proxy("product-service", "GET", `http://product-service:4001/products/${req.params.id}`);
    res.json(data);
  } catch (err) {
    const status = err.response?.status === 404 ? 404 : 502;
    res.status(status).json({ error: status === 404 ? "product not found" : "product-service unavailable" });
  }
});

app.get("/users", async (req, res) => {
  try {
    const { data } = await proxy("user-service", "GET", "http://user-service:4002/users");
    res.json(data);
  } catch (err) {
    res.status(502).json({ error: "user-service unavailable", requestId: req.requestId });
  }
});

app.get("/users/:id", async (req, res) => {
  try {
    const { data } = await proxy("user-service", "GET", `http://user-service:4002/users/${req.params.id}`);
    res.json(data);
  } catch (err) {
    const status = err.response?.status === 404 ? 404 : 502;
    res.status(status).json({ error: status === 404 ? "user not found" : "user-service unavailable" });
  }
});

app.get("/orders", async (req, res) => {
  try {
    const { data } = await proxy("order-service", "GET", "http://order-service:4003/orders");
    res.json(data);
  } catch (err) {
    res.status(502).json({ error: "order-service unavailable", requestId: req.requestId });
  }
});

app.post("/orders", async (req, res) => {
  try {
    const { data, statusCode } = await proxy("order-service", "POST", "http://order-service:4003/orders", req.body);
    res.status(statusCode).json(data);
  } catch (err) {
    const status = err.response?.status ?? 502;
    const body = err.response?.data ?? { error: "order-service unavailable" };
    res.status(status).json(body);
  }
});

app.get("/metrics", async (req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

// ── 404 fallback ──────────────────────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({ error: "route not found", path: req.path });
});

app.listen(4000, () => console.log("API Gateway v2 running on port 4000"));
