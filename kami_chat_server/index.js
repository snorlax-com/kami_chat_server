const express = require("express");
const cors = require("cors");

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

app.get("/", (req, res) => {
  res.json({ status: "kami chat server running" });
});

app.get("/health", (req, res) => {
  res.json({ ok: true });
});

app.post("/api/chat/send", (req, res) => {
  const { userId, message } = req.body || {};
  console.log("[chat/send]", { userId, message });
  res.json({ status: "received" });
});

app.listen(PORT, () => {
  console.log(`Kami chat server listening on port ${PORT}`);
});
