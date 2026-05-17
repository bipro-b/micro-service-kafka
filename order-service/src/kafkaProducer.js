const { Kafka } = require("kafkajs");

const kafka = new Kafka({
  clientId: "order-service",
  brokers: [process.env.KAFKA_BROKERS || "kafka:9092"],
});

const producer = kafka.producer();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let connected = false;

async function connectWithRetry() {
  let attempt = 0;
  while (true) {
    try {
      attempt++;
      console.log(`Connecting Kafka producer... attempt ${attempt}`);
      await producer.connect();
      connected = true;
      console.log("Kafka producer connected");
      break;
    } catch (err) {
      console.error(`Kafka producer attempt ${attempt} failed:`, err.message);
      await sleep(5000);
    }
  }
}

connectWithRetry();

async function publishOrderCreated(order) {
  if (!connected) {
    throw new Error("Kafka producer not yet connected");
  }
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
