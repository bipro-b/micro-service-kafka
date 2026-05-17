const { Kafka } = require("kafkajs");

const kafka = new Kafka({
  clientId: "user-service",
  brokers: [process.env.KAFKA_BROKERS || "kafka:9092"],
});

const consumer = kafka.consumer({ groupId: "user-group" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function startConsumer(metricsCounter) {
  let attempt = 0;
  while (true) {
    try {
      attempt++;
      console.log(`Connecting Kafka consumer... attempt ${attempt}`);
      await consumer.connect();
      await consumer.subscribe({ topic: "user-events", fromBeginning: false });
      await consumer.run({
        eachMessage: async ({ message }) => {
          const data = JSON.parse(message.value.toString());
          console.log("User Service received event:", data.type, "orderId:", data.orderId);
          if (metricsCounter) {
            metricsCounter.inc({ service: "user-service", event_type: data.type || "UNKNOWN" });
          }
        },
      });
      console.log("Kafka consumer connected and running");
      break;
    } catch (err) {
      console.error(`Kafka consumer attempt ${attempt} failed:`, err.message);
      await sleep(5000);
    }
  }
}

module.exports = startConsumer;
