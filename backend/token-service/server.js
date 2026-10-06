// SoundClash token service.
// LiveKit access tokens, scoped by role. Secrets stay server-side.
//
// NOTE: the /v1/musickit-token endpoint below is NOT used by the iOS app — native
// iOS MusicKit attaches the developer token via the app's signing automatically.
// It's kept only in case server-side Apple Music API calls are ever needed.
// Run:  npm install && npm start        (env vars below)
// Deploy anywhere Node runs (Fly.io / Render / a $5 VPS all fine for a prototype).

const express = require('express');
const jwt = require('jsonwebtoken');
const { AccessToken } = require('livekit-server-sdk');

const app = express();
app.use(express.json());

const {
  PORT = 3000,
  APPLE_TEAM_ID,
  APPLE_KEY_ID,
  APPLE_PRIVATE_KEY,      // full .p8 contents; keep \n newlines intact in env
  LIVEKIT_URL,
  LIVEKIT_API_KEY,
  LIVEKIT_API_SECRET,
} = process.env;

// ---- MusicKit developer token (cached until near expiry) ----
let cachedDevToken = null;
let cachedDevTokenExp = 0;

function musickitDeveloperToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedDevToken && cachedDevTokenExp - now > 3600) return cachedDevToken; // refresh 1h early

  if (!APPLE_TEAM_ID || !APPLE_KEY_ID || !APPLE_PRIVATE_KEY) {
    throw new Error('Missing Apple MusicKit env vars');
  }
  const token = jwt.sign({}, APPLE_PRIVATE_KEY.replace(/\\n/g, '\n'), {
    algorithm: 'ES256',
    expiresIn: '180d',                 // Apple hard ceiling: ~6 months
    issuer: APPLE_TEAM_ID,
    header: { alg: 'ES256', kid: APPLE_KEY_ID },
  });
  cachedDevToken = token;
  cachedDevTokenExp = now + 180 * 24 * 3600;
  return token;
}

app.get('/v1/musickit-token', (req, res) => {
  try {
    res.json({ token: musickitDeveloperToken() });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ---- LiveKit access token ----
// Body: { room, identity, role }  role: competitor | judge | audience | host
// Competitors + judges + host can publish (mic); audience subscribes only.
app.post('/v1/livekit-token', async (req, res) => {
  try {
    const { room, identity, role } = req.body;
    if (!room || !identity || !role) {
      return res.status(400).json({ error: 'room, identity, role required' });
    }
    const canPublish = ['competitor', 'judge', 'host'].includes(role);
    const at = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
      identity,
      ttl: '6h',                        // a battle never runs longer than this
    });
    at.addGrant({ roomJoin: true, room, canPublish, canSubscribe: true });
    res.json({ token: await at.toJwt(), url: LIVEKIT_URL });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/health', (_req, res) => res.json({ ok: true }));

app.listen(PORT, () => console.log(`token-service listening on :${PORT}`));
