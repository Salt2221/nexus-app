const WebSocket = require('ws');
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORT = process.env.PORT || 3000;
const DATA_FILE = path.join(__dirname, 'data.json');

let DB = { users: {}, chats: {}, messages: {}, members: {} };

function save() {
  try { fs.writeFileSync(DATA_FILE, JSON.stringify(DB, null, 2)); } catch (_) {}
}
function load() {
  try { if (fs.existsSync(DATA_FILE)) DB = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')); } catch (_) {}
}
load();

function uid() { return crypto.randomUUID().slice(0, 8); }
function now() { return new Date().toISOString(); }

const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  if (req.url === '/' || req.url === '/index.html') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(`<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>NEXUS Chat</title><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:system-ui;background:#0D1117;color:#e6e6e6;height:100vh;display:flex;flex-direction:column}#login{display:flex;align-items:center;justify-content:center;height:100vh;flex-direction:column;gap:20px}#login h1{color:#6C63FF;font-size:28px}#login input{padding:12px 20px;border-radius:12px;border:1px solid #30363D;background:#161B22;color:#e6e6e6;font-size:16px;width:300px;outline:none}#login input:focus{border-color:#6C63FF}#login button{padding:12px 40px;border-radius:12px;border:none;background:#6C63FF;color:#fff;font-size:16px;cursor:pointer}#app{display:flex;height:100vh;height:100dvh;display:none}#sidebar{width:300px;background:#161B22;border-right:1px solid #30363D;display:flex;flex-direction:column}#sidebar h2{padding:16px;color:#6C63FF;border-bottom:1px solid #30363D}#chatList{flex:1;overflow-y:auto}.chat-item{padding:12px 16px;border-bottom:1px solid #21262d;cursor:pointer}.chat-item:hover{background:#1C2333}.chat-item.active{border-left:3px solid #6C63FF;background:#1C2333}.chat-item .title{font-weight:600;font-size:14px}.chat-item .preview{font-size:12px;color:#8b949e;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}#chatArea{flex:1;display:flex;flex-direction:column}#chatHeader{padding:12px 20px;border-bottom:1px solid #30363D;font-weight:600}#chatEmpty{flex:1;display:flex;align-items:center;justify-content:center;color:#484f58}#messages{flex:1;overflow-y:auto;padding:16px 20px;display:flex;flex-direction:column;gap:4px}.msg{max-width:70%;padding:8px 14px;border-radius:12px;font-size:14px;line-height:1.4;word-wrap:break-word}.msg.own{background:#6C63FF;color:#fff;align-self:flex-end;border-bottom-right-radius:4px}.msg.other{background:#21262d;align-self:flex-start;border-bottom-left-radius:4px}.msg .meta{font-size:11px;color:rgba(255,255,255,0.5);margin-top:4px}.msg.other .meta{color:#8b949e}#inputArea{padding:12px 20px;border-top:1px solid #30363D;display:flex;gap:8px}#inputArea input{flex:1;padding:10px 14px;border-radius:10px;border:1px solid #30363D;background:#0D1117;color:#e6e6e6;font-size:14px;outline:none}#inputArea input:focus{border-color:#6C63FF}#inputArea button{padding:10px 20px;border-radius:10px;border:none;background:#6C63FF;color:#fff;cursor:pointer}</style></head><body><div id="login"><h1>NEXUS Chat</h1><input id="nameInput" placeholder="Ваше имя" maxlength="20"><br><button onclick="login()">Войти</button></div><div id="app"><div id="sidebar"><h2>NEXUS</h2><div id="chatList"></div></div><div id="chatArea"><div id="chatEmpty">Выберите чат или создайте новый</div><div id="chatHeader" style="display:none"></div><div id="messages" style="display:none"></div><div id="inputArea" style="display:none"><input id="msgInput" placeholder="Сообщение..." onkeydown="if(event.key==='Enter')sendMsg()"><button onclick="sendMsg()">→</button></div></div></div><script>let ws,user=null,chats=[],curChat=null;function login(){const n=document.getElementById('nameInput').value.trim();if(!n)return;document.getElementById('login').style.display='none';document.getElementById('app').style.display='flex';connect(n)}function connect(n){const proto=location.protocol==='https:'?'wss:':'ws:';ws=new WebSocket(proto+'//'+location.host);ws.onopen=()=>ws.send(JSON.stringify({type:'auth',name:n}));ws.onmessage=e=>{const d=JSON.parse(e.data);switch(d.type){case'authed':user=d.user;break;case'chats':chats=d.chats;renderChats();break;case'messages':renderMessages(d.messages);break;case'new_message':renderMessages([...document.querySelectorAll('#messages .msg')].length>0?[...(window._lastMsgs||[]),d.message]:[d.message]);break;case'chat_created':ws.send(JSON.stringify({type:'get_chats'}));break}};ws.onclose=()=>setTimeout(()=>connect(n),3000)}function renderChats(){const el=document.getElementById('chatList');el.innerHTML=(chats||[]).map(c=>'<div class="chat-item'+(curChat&&curChat.id===c.id?' active':'')+'" onclick="selectChat(\\''+c.id+'\\')"><div class="title">'+esc(c.title)+'</div><div class="preview">'+esc(c.last_message||'')+'</div></div>').join('')+'<div class="chat-item" onclick="createChat()" style="color:#6C63FF;font-weight:600">+ Новый чат</div>'}function selectChat(id){curChat=chats.find(c=>c.id===id);document.getElementById('chatEmpty').style.display='none';document.getElementById('chatHeader').style.display='block';document.getElementById('chatHeader').textContent=curChat.title;document.getElementById('messages').style.display='flex';document.getElementById('inputArea').style.display='flex';renderChats();ws.send(JSON.stringify({type:'get_messages',chat_id:id,limit:50}))}function renderMessages(msgs){window._lastMsgs=msgs||[];const el=document.getElementById('messages');el.innerHTML=(msgs||[]).map(m=>'<div class="msg '+(m.user_id===user.id?'own':'other')+'">'+(m.user_id!==user.id?'<b>'+esc(m.user_name)+'</b><br>':'')+esc(m.text)+'<div class="meta">'+timeAgo(m.created_at)+'</div></div>').join('');el.scrollTop=el.scrollHeight}function sendMsg(){const input=document.getElementById('msgInput');const t=input.value.trim();if(!t||!curChat)return;input.value='';ws.send(JSON.stringify({type:'send_message',chat_id:curChat.id,text:t}))}function createChat(){const t=prompt('Название чата:');if(t&&t.trim())ws.send(JSON.stringify({type:'create_chat',title:t.trim()}))}function esc(s){return String(s||'').replace(/[<>&]/g,c=>({'<':'&lt;','>':'&gt;','&':'&amp;'}[c]))}function timeAgo(ts){const d=new Date(ts+(ts.endsWith('Z')?'':'Z'));const s=(Date.now()-d)/1e3;if(s<60)return'только что';if(s<3600)return Math.floor(s/60)+' мин';return d.toLocaleTimeString('ru',{hour:'2-digit',minute:'2-digit'})}</script></body></html>`);
    return;
  }

  res.writeHead(404); res.end();
});

const wss = new WebSocket.Server({ server, path: '/ws' });

wss.on('connection', (ws) => {
  let user = null;
  ws.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw);
      switch (msg.type) {
        case 'auth': {
          const id = msg.id || uid();
          user = { id, name: msg.name || 'User', avatar: msg.avatar || null };
          DB.users[id] = user;
          save();
          ws.send(JSON.stringify({ type: 'authed', user }));
          broadcast({ type: 'user_online', user });
          ws.send(JSON.stringify({ type: 'chats', chats: Object.values(DB.chats).map(c => ({ ...c, last_message: c.last_message || '' })) }));
          break;
        }
        case 'get_chats':
          ws.send(JSON.stringify({ type: 'chats', chats: Object.values(DB.chats).map(c => ({ ...c, last_message: c.last_message || '' })) }));
          break;
        case 'create_chat': {
          if (!user) break;
          const id = uid();
          DB.chats[id] = { id, title: msg.title || 'New Chat', type: msg.type || 'group', created_by: user.id, created_at: now(), last_message: '' };
          DB.members[id] = { [user.id]: { role: 'owner' } };
          if (msg.members) for (const mid of msg.members) DB.members[id][mid] = { role: 'member' };
          save();
          broadcast({ type: 'chat_created', chat: DB.chats[id] });
          break;
        }
        case 'get_messages': {
          if (!user) break;
          const chat_id = msg.chat_id;
          if (!DB.messages[chat_id]) DB.messages[chat_id] = [];
          ws.send(JSON.stringify({ type: 'messages', chat_id, messages: DB.messages[chat_id].slice(-(msg.limit || 50)) }));
          break;
        }
        case 'send_message': {
          if (!user) break;
          const chat_id = msg.chat_id, text = (msg.text || '').trim();
          if (!chat_id || !text || !DB.chats[chat_id]) break;
          const message = { id: uid(), chat_id, user_id: user.id, user_name: user.name, user_avatar: user.avatar, text, created_at: now() };
          if (!DB.messages[chat_id]) DB.messages[chat_id] = [];
          DB.messages[chat_id].push(message);
          DB.chats[chat_id].last_message = text;
          save();
          broadcast({ type: 'new_message', message });
          break;
        }
      }
    } catch(e) { ws.send(JSON.stringify({ type: 'error', error: 'Invalid' })); }
  });
  ws.on('close', () => { if (user) { delete DB.users[user.id]; save(); broadcast({ type: 'user_offline', user_id: user.id }); } });
});

function broadcast(data) {
  const json = JSON.stringify(data);
  wss.clients.forEach(c => { if (c.readyState === WebSocket.OPEN) c.send(json); });
}

server.listen(PORT, '0.0.0.0', () => {
  console.log(`NEXUS Chat Server running on port ${PORT}`);
  console.log(`WebSocket: ws://localhost:${PORT}/ws`);
});
