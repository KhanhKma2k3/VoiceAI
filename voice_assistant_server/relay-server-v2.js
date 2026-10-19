/**
 * Relay Server v2
 * ---------------
 * Khác biệt so với v1:
 *  - KHÔNG còn AGENT_TOKENS / CONTROLLER_TOKENS cấu hình tay theo deviceId.
 *  - Client (điện thoại hoặc bản Windows Desktop của app) gửi `authToken`
 *    chính là JWT lấy được sau khi ApiService.login() thành công.
 *  - Relay verify JWT (khớp chính xác với backend FastAPI: python-jose,
 *    HS256, claim "sub" = username), rồi TỰ NHÓM mọi kết nối cùng username
 *    lại với nhau.
 *  - Điện thoại và máy tính đăng nhập CÙNG 1 tài khoản => tự động "thấy nhau",
 *    không cần nhập token/deviceId thủ công nữa.
 *
 * Biến "userId" dùng trong code bên dưới thực chất chứa USERNAME (vì backend
 * của bạn dùng username làm subject của JWT, không có id dạng số riêng).
 * Giữ tên "userId" chỉ để code tổng quát, không có ý nghĩa gì khác.
 *
 * Cấu hình qua biến môi trường:
 *   PORT           - cổng lắng nghe (mặc định 8080)
 *   JWT_SECRET     - PHẢI giống hệt settings.JWT_SECRET_KEY trong config.py của backend
 *   JWT_ALGORITHM  - PHẢI giống hệt settings.JWT_ALGORITHM trong config.py (thường "HS256")
 */

const http = require('http');
const { WebSocketServer } = require('ws');
const jwt = require('jsonwebtoken');

const PORT = process.env.PORT || 8080;
const JWT_SECRET = process.env.JWT_SECRET;
// Phải khớp settings.JWT_ALGORITHM trong config.py của backend (thường là "HS256").
const JWT_ALGORITHM = process.env.JWT_ALGORITHM || 'HS256';
const crypto = require('crypto');
console.log('[JWT] fingerprint:', crypto.createHash('sha256').update(JWT_SECRET || '').digest('hex').slice(0, 8));
if (!JWT_SECRET) {
  console.warn(
    '[CẢNH BÁO] Chưa cấu hình JWT_SECRET. Server sẽ từ chối mọi kết nối ' +
    'cho tới khi bạn cấu hình biến môi trường này (phải khớp secret backend).'
  );
}

/**
 * Xác thực authToken do client gửi lên, trả về "username" nếu hợp lệ, hoặc
 * null nếu không hợp lệ / hết hạn.
 *
 * Khớp CHÍNH XÁC với backend FastAPI của bạn (auth.py):
 *   - create_access_token() ký bằng jose.jwt.encode(data, JWT_SECRET_KEY, algorithm=JWT_ALGORITHM)
 *   - payload có claim "sub" = username (không phải userId dạng số)
 *   - _decode_token() lấy payload.get("sub") làm định danh user
 *
 * => Relay dùng thẳng "sub" làm khóa nhóm thiết bị (thay cho "userId").
 */
function verifyAuthToken(authToken) {
  if (!authToken || !JWT_SECRET) return null;
  try {
    const payload = jwt.verify(authToken, JWT_SECRET, { algorithms: [JWT_ALGORITHM] });
    const username = payload.sub;
    return username ? String(username) : null;
  } catch (err) {
     console.log('[auth] token bị từ chối:', err.message); 
    return null;
  }
}

// userId -> { agents: Map<connId, {ws, deviceName}>, controllers: Map<connId, {ws, deviceName}> }
const users = new Map();

function getUserBucket(userId) {
  let bucket = users.get(userId);
  if (!bucket) {
    bucket = { agents: new Map(), controllers: new Map() };
    users.set(userId, bucket);
  }
  return bucket;
}

function send(ws, obj) {
  if (ws && ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(obj));
  }
}

function broadcastAgentList(userId) {
  const bucket = users.get(userId);
  if (!bucket) return;
  const agentList = Array.from(bucket.agents.entries()).map(([connId, a]) => ({
    id: connId,
    name: a.deviceName || 'PC',
  }));
  for (const c of bucket.controllers.values()) {
    send(c.ws, { type: 'agents_online', agents: agentList });
  }
}

let connCounter = 0;

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('ok');
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ server });

wss.on('connection', (ws, req) => {
    console.log('[conn] kết nối mới từ', req.socket.remoteAddress);
  let session = null; // { userId, role, connId, deviceName }
  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      send(ws, { type: 'error', message: 'JSON không hợp lệ' });
      return;
    }

    if (msg.type === 'register') {
      const { role, authToken, deviceName } = msg;

      if (role !== 'agent' && role !== 'controller') {
        send(ws, { type: 'error', message: 'role phải là agent hoặc controller' });
        ws.close();
        return;
      }

      const userId = verifyAuthToken(authToken);
      if (!userId) {
        send(ws, { type: 'error', message: 'Xác thực thất bại (authToken không hợp lệ/hết hạn)' });
        ws.close();
        return;
      }

      const connId = `${role}-${++connCounter}`;
      session = { userId, role, connId, deviceName: deviceName || role };

      const bucket = getUserBucket(userId);
      const registry = role === 'agent' ? bucket.agents : bucket.controllers;
      registry.set(connId, { ws, deviceName: session.deviceName });

      send(ws, { type: 'registered', role, connId });
      console.log(`[+] user=${userId} role=${role} connId=${connId} đã kết nối`);

      if (role === 'agent') broadcastAgentList(userId);
      if (role === 'controller') {
        // Gửi ngay danh sách agent hiện có cho controller vừa vào.
        const agentList = Array.from(bucket.agents.entries()).map(([id, a]) => ({
          id,
          name: a.deviceName,
        }));
        send(ws, { type: 'agents_online', agents: agentList });
      }
      return;
    }

    if (!session) {
      send(ws, { type: 'error', message: 'Phải register trước' });
      return;
    }

    const bucket = getUserBucket(session.userId);

    if (msg.type === 'command' && session.role === 'controller') {
      // targetAgentId không bắt buộc: nếu không truyền và chỉ có 1 agent
      // online, tự động route tới agent đó.
      let targetAgent = null;
      if (msg.targetAgentId) {
        targetAgent = bucket.agents.get(msg.targetAgentId);
      } else if (bucket.agents.size === 1) {
        targetAgent = bucket.agents.values().next().value;
      }

      if (!targetAgent) {
        send(ws, {
          type: 'result',
          requestId: msg.requestId,
          success: false,
          message: bucket.agents.size === 0
            ? 'Chưa có máy tính nào online cho tài khoản này.'
            : 'Có nhiều máy tính online, cần chỉ định targetAgentId.',
        });
        return;
      }

      send(targetAgent.ws, {
        type: 'command',
        sourceConnId: session.connId,
        requestId: msg.requestId,
        action: msg.action,
        params: msg.params || {},
      });
      return;
    }

    if (msg.type === 'result' && session.role === 'agent') {
      const dest = bucket.controllers.get(msg.sourceConnId);
      send(dest ? dest.ws : null, {
        type: 'result',
        requestId: msg.requestId,
        success: msg.success,
        message: msg.message,
        data: msg.data,
      });
      return;
    }

    send(ws, { type: 'error', message: 'Message type không được hỗ trợ ở role này' });
  });

  ws.on('close', () => {
    if (!session) return;
    const bucket = getUserBucket(session.userId);
    const registry = session.role === 'agent' ? bucket.agents : bucket.controllers;
    registry.delete(session.connId);
    console.log(`[-] user=${session.userId} role=${session.role} connId=${session.connId} đã ngắt kết nối`);
    if (session.role === 'agent') broadcastAgentList(session.userId);
  });
});

server.listen(PORT, () => {
  console.log(`Relay server v2 đang chạy tại cổng ${PORT}`);
});