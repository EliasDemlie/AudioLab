import express, { Express } from 'express';
import http from 'http';
import { Server, Socket } from 'socket.io';
import prisma from './config/db';
import routes from './routes';
import { authMiddleware } from './middlewares/authMiddleware';  
import { verifyToken } from './utils/jwt';
import dotenv from 'dotenv';

dotenv.config();

const app: Express = express();
const server = http.createServer(app);
const io = new Server(server);

// Middleware
app.use(express.json());
app.use('/api', routes);

// Socket.IO authentication
interface AuthSocket extends Socket {
  userId?: string;
}

io.use((socket: AuthSocket, next) => {
  const token = socket.handshake.auth.token;
  if (!token) return next(new Error('Authentication error'));
  try {
    const decoded = verifyToken(token);
    socket.userId = decoded.userId;
    next();
  } catch (error) {
    next(new Error('Authentication error'));
  }
});

// Socket.IO events
io.on('connection', (socket: AuthSocket) => {
  console.log(`User connected: ${socket.userId}`);

  socket.on('joinConversation', async ({ conversationId }: { conversationId: string }) => {
    const conversation = await prisma.conversation.findFirst({
      where: { id: conversationId, OR: [{ user1Id: socket.userId! }, { user2Id: socket.userId! }] },
    });
    if (conversation) {
      socket.join(conversationId);
      await prisma.user.update({
        where: { id: socket.userId! },
        data: { isOnline: true, lastSeen: new Date() },
      });
    }
  });

  socket.on('disconnect', async () => {
    await prisma.user.update({
      where: { id: socket.userId! },
      data: { isOnline: false, lastSeen: new Date() },
    });
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log(`Server running on port ${PORT}`));