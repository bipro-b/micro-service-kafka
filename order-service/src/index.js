const express = require("express");
const publishOrderCreated = require("./kafkaProducer");

const app = express();
app.use(express.json());

app.post("/orders", async (req, res) => {
  const order = {
    id: Date.now().toString(),
    userId: req.body.userId,
  };

  await publishOrderCreated(order);
  res.json({ message: "Order created", order });
});

app.listen(4003, () => {
  console.log("🛒 Order Service running on port 4003");
});
