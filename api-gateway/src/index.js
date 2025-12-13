const express = require("express");
const axios = require("axios");

const app = express();
app.use(express.json());

app.get("/products", async (req, res) => {
  const r = await axios.get("http://product-service:4001/products");
  res.json(r.data);
});

app.get("/users", async (req, res) => {
  const r = await axios.get("http://user-service:4002/users");
  res.json(r.data);
});

app.post("/orders", async (req, res) => {
  const r = await axios.post("http://order-service:4003/orders", req.body);
  res.json(r.data);
});

app.listen(4000, () => {
  console.log("🚪 API Gateway running on port 4000");
});
