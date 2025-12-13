const express = require("express");
const startConsumer = require("./kafkaConsumer");

const app = express();

// start kafka consumer in background
startConsumer().catch((e) => console.error("Kafka consumer error:", e));

app.get("/users", (req, res) => {
  res.json([
    { id: "u1", name: "Bipro" },
    { id: "u2", name: "Alex" },
  ]);
});

app.listen(4002, () => {
  console.log("👤 User Service running on port 4002");
});
