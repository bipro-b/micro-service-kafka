const axios = require("axios");

const GATEWAY_URL = process.env.GATEWAY_URL || "http://api-gateway:4000";
const INTERVAL_MS = parseInt(process.env.INTERVAL_MS || "2000");

const USERS = ["u1", "u2", "u3", "u4", "u5", "u6", "u7", "u8"];
const PRODUCTS = [
  { item: "MacBook Pro 16", price: 2499.99 },
  { item: "iPhone 15 Pro", price: 999.99 },
  { item: "AirPods Pro", price: 249.99 },
  { item: "USB-C Hub 10-in-1", price: 49.99 },
  { item: "Keychron K2 Keyboard", price: 89.99 },
  { item: "SanDisk SSD 1TB", price: 89.99 },
  { item: "LG 27UK850 Monitor", price: 499.99 },
  { item: "Logitech MX Master 3", price: 99.99 },
  { item: "Corsair 32GB DDR5", price: 129.99 },
  { item: "Dell XPS 15", price: 1899.99 },
];
const PRODUCT_IDS = ["p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8", "p9", "p10", "p11", "p12"];

function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

let requestCount = 0;
let errorCount = 0;

async function generateTraffic() {
  const roll = Math.random();
  let endpoint = "";

  try {
    if (roll < 0.30) {
      endpoint = "GET /products";
      await axios.get(`${GATEWAY_URL}/products`, { timeout: 4000 });
    } else if (roll < 0.42) {
      const id = pick(PRODUCT_IDS);
      endpoint = `GET /products/${id}`;
      await axios.get(`${GATEWAY_URL}/products/${id}`, { timeout: 4000 });
    } else if (roll < 0.42 + 0.05) {
      endpoint = "GET /products?category=laptops";
      await axios.get(`${GATEWAY_URL}/products?category=laptops`, { timeout: 4000 });
    } else if (roll < 0.65) {
      endpoint = "GET /users";
      await axios.get(`${GATEWAY_URL}/users`, { timeout: 4000 });
    } else if (roll < 0.72) {
      const uid = pick(USERS);
      endpoint = `GET /users/${uid}`;
      await axios.get(`${GATEWAY_URL}/users/${uid}`, { timeout: 4000 });
    } else if (roll < 0.82) {
      endpoint = "GET /orders";
      await axios.get(`${GATEWAY_URL}/orders`, { timeout: 4000 });
    } else {
      const user = pick(USERS);
      const product = pick(PRODUCTS);
      const qty = Math.floor(Math.random() * 3) + 1;
      endpoint = "POST /orders";
      await axios.post(
        `${GATEWAY_URL}/orders`,
        { userId: user, item: product.item, quantity: qty, price: product.price },
        { timeout: 4000 }
      );
    }
    requestCount++;
    if (requestCount % 50 === 0) {
      console.log(`[load-gen] requests=${requestCount} errors=${errorCount} last="${endpoint}"`);
    }
  } catch (err) {
    errorCount++;
    const status = err.response?.status || "timeout";
    console.error(`[load-gen] FAIL ${endpoint} → ${status}`);
  }
}

// Burst mode: send multiple concurrent requests
async function burst() {
  const concurrency = parseInt(process.env.CONCURRENCY || "3");
  await Promise.allSettled(Array.from({ length: concurrency }, () => generateTraffic()));
}

console.log(`[load-gen] Starting in 15s → target=${GATEWAY_URL} interval=${INTERVAL_MS}ms`);
setTimeout(() => {
  setInterval(burst, INTERVAL_MS);
}, 15000);
