const express = require("express");
const publishOrderCreated = require("./kafkaProducer");

const app = express();
app.use(express.json());

app.get("/orders", async (req, res) => {
  const fakeOrders = [
    {
      id: "1716800001000",
      userId: "user_01",
      item: "Wireless Headphones",
      quantity: 1,
      price: 59.99,
      status: "delivered",
    },
    {
      id: "1716800002000",
      userId: "user_02",
      item: "Mechanical Keyboard",
      quantity: 2,
      price: 129.99,
      status: "processing",
    },
    {
      id: "1716800003000",
      userId: "user_03",
      item: "USB-C Hub",
      quantity: 1,
      price: 34.49,
      status: "shipped",
    },
  ];

  res.json(fakeOrders);
});

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
