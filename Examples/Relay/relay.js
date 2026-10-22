// SideSeat reference relay. Pairs one app (device) with one browser (agent) by a 6-digit code.
// A starting point for local development, not a production service: no TLS, no agent accounts, no audit log.

const http = require('http')
const fs = require('fs')
const path = require('path')
const crypto = require('crypto')
const { WebSocketServer } = require('ws')

const HOST = process.env.HOST || '127.0.0.1'
const PORT = Number(process.env.PORT || 8080)
const DEVICE_TOKEN = process.env.DEVICE_TOKEN || ''
const CONSOLE = path.join(__dirname, 'public', 'index.html')

const rooms = new Map()

const server = http.createServer((req, res) => {
  if (req.url === '/' || req.url === '/index.html') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' })
    return res.end(fs.readFileSync(CONSOLE))
  }
  res.writeHead(404).end()
})

const wss = new WebSocketServer({ noServer: true, maxPayload: 4 * 1024 * 1024 })

server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url, 'http://relay')
  const role = url.pathname.replace(/^\//, '')
  if (role !== 'device' && role !== 'agent') return socket.destroy()
  if (role === 'device' && DEVICE_TOKEN && !validToken(req, url)) {
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n')
    return socket.destroy()
  }
  wss.handleUpgrade(req, socket, head, ws => (role === 'device' ? onDevice(ws) : onAgent(ws, url)))
})

function validToken(req, url) {
  const given = url.searchParams.get('token') || (req.headers.authorization || '').replace(/^Bearer /, '')
  const a = Buffer.from(given)
  const b = Buffer.from(DEVICE_TOKEN)
  return a.length === b.length && crypto.timingSafeEqual(a, b)
}

function newCode() {
  let code
  do { code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0') } while (rooms.has(code))
  return code
}

function send(ws, message) {
  if (ws && ws.readyState === ws.OPEN) ws.send(JSON.stringify(message))
}

function onDevice(device) {
  const code = newCode()
  const room = { device, agent: null }
  rooms.set(code, room)
  log(code, 'device connected')
  send(device, { type: 'session', code })

  device.on('message', (data, isBinary) => {
    if (isBinary) {
      if (room.agent && room.agent.readyState === room.agent.OPEN && room.agent.bufferedAmount < 2 * 1024 * 1024) room.agent.send(data, { binary: true })
      return
    }
    let message
    try { message = JSON.parse(data) } catch { return }
    send(room.agent, message)
    if (message.type === 'consent') log(code, `agent allowed to ${message.mode}`)
    if (message.type === 'denied' && room.agent) {
      log(code, 'agent denied')
      room.agent.close(4403, 'denied')
      room.agent = null
    }
    if (message.type === 'end') {
      room.ended = true
      device.close(1000, 'ended')
    }
  })

  device.on('close', () => {
    log(code, 'device left')
    rooms.delete(code)
    if (room.agent) {
      if (!room.ended) send(room.agent, { type: 'end', reason: 'disconnected' })
      room.agent.close(1000, 'device left')
    }
  })
  keepAlive(device)
}

function onAgent(agent, url) {
  const code = url.searchParams.get('code') || ''
  const name = (url.searchParams.get('name') || '').trim().slice(0, 40)
  const room = rooms.get(code)
  if (!room || !name) return agent.close(4404, 'unknown code')
  if (room.agent) return agent.close(4409, 'an agent is already connected')

  room.agent = agent
  log(code, `agent "${name}" joined`)
  send(room.device, { type: 'agentJoined', agentId: crypto.randomUUID(), agentName: name })

  agent.on('message', (data, isBinary) => {
    if (isBinary) return
    let message
    try { message = JSON.parse(data) } catch { return }
    if (message.type === 'input') send(room.device, message)
    if (message.type === 'end') {
      room.ended = true
      send(room.device, { type: 'end', reason: 'agentEnded' })
      send(agent, { type: 'end', reason: 'agentEnded' })
      room.device.close(1000, 'agent ended')
    }
  })

  agent.on('close', () => {
    if (room.agent !== agent) return
    room.agent = null
    log(code, 'agent left')
    send(room.device, { type: 'agentLeft' })
  })
  keepAlive(agent)
}

function keepAlive(ws) {
  const timer = setInterval(() => ws.readyState === ws.OPEN && ws.ping(), 25_000)
  ws.on('close', () => clearInterval(timer))
}

function log(code, text) {
  console.log(`${new Date().toISOString()} [${code}] ${text}`)
}

server.listen(PORT, HOST, () => {
  console.log(`SideSeat relay on http://${HOST}:${PORT}`)
  console.log(`  apps connect to  ws://${HOST}:${PORT}/device${DEVICE_TOKEN ? '?token=…' : ''}`)
  console.log(`  agents open      http://${HOST}:${PORT}`)
})
