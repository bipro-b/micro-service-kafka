const { Kafka } = require("kafkajs");

const kafka = new Kafka({
  clientId: "order-service",
  brokers: ["kafka:9092"],
});

const producer = kafka.producer();

async function publishOrderCreated(order) {
  await producer.connect();
  await producer.send({
    topic: "user-events",
    messages: [
      {
        value: JSON.stringify({
          type: "ORDER_CREATED",
          orderId: order.id,
          userId: order.userId,
        }),
      },
    ],
  });
}

module.exports = publishOrderCreated;
