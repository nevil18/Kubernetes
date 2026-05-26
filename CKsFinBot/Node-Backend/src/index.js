/** @format */

import connectDB from "./db/index.js";
import { app } from "./app.js";
import http from "http";
import { Server } from "socket.io";
import { handleNewChatMessage } from "./Controllers/chat.controller.js"; // Assuming you create this


const PORT = process.env.PORT || 8000;
const httpServer = http.createServer(app);

const io = new Server(httpServer, {
  pingTimeout: 60000,
  cors: {
    origin: "*",
    credentials: true,
  },
});
app.set("io", io);

io.on("connection", (socket) => {
  console.log("✅ A user connected:", socket.id);

  socket.on("joinConversation", (conversationId) => {
    socket.join(conversationId);
    console.log(`User ${socket.id} joined conversation ${conversationId}`);
  });

  socket.on("sendMessage", (data) => {
    console.log("called");
    handleNewChatMessage(socket, data);
  });

  socket.on("disconnect", () => {
    console.log("❌ User disconnected:", socket.id);
  });
});

// --- Start the Server ---
connectDB()
  .then(() => {
    httpServer.listen(PORT, "0.0.0.0", () => {
      console.log(`🚀 Server is running at http://0.0.0.0:${PORT}`);
    });
  })
  .catch((err) => {
    console.error("MONGO db connection failed !!! ", err);
  });
