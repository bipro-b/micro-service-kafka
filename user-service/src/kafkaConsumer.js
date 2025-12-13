const { Kafka } = require("kafkajs");

const kafka = new Kafka({
  clientId: "user-service",
  brokers: ["kafka:9092"],
});

const consumer = kafka.consumer({ groupId: "user-group" });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function startConsumer() {
  let attempt = 0;

  while (true) {
    try {
      attempt++;
      console.log(`🔁 Connecting Kafka consumer... attempt ${attempt}`);

      await consumer.connect();
      await consumer.subscribe({ topic: "user-events", fromBeginning: true });

      await consumer.run({
        eachMessage: async ({ message }) => {
          const data = JSON.parse(message.value.toString());
          console.log("👤 User Service received:", data);
        },
      });

      console.log("✅ Kafka consumer running");
      break; // consumer.run keeps process alive
    } catch (err) {
      console.error("❌ Kafka consumer start failed:", err.message);
      await sleep(5000);
    }
  }
}

module.exports = startConsumer;
