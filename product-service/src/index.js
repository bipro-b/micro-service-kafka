const express = require("express");
const app = express();

app.get("/products", (req, res) => {
  res.json([
    { id: "p1", name: "Laptop" },
    { id: "p2", name: "Phone" },
  ]);
});

app.listen(4001, () => {
  console.log("📦 Product Service running on port 4001");
});
