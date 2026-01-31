const fetch = require("node-fetch");
const crypto = require("crypto");
const OpenAI = require("openai/index.js");

const SAST_RECOMMEND_REPORT = process.env.SAST_RECOMMEND_REPORT
const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY;

const openai = new OpenAI({
  baseURL: "https://api.deepseek.com",
  apiKey: DEEPSEEK_API_KEY,
});

function normalize(str) {
  return (str || "").trim().replace(/\s+/g, " ");
}

function makeCacheKey(finding) {
  const rule = normalize(finding.rule);
  const title = normalize(
    finding.title?.replace(/function argument `[^`]+`/, "function argument `<VAR>`")
  );
  const description = normalize(finding.description);
  const keyInput = `${rule}|${title}|${description}`;
  const hash = crypto.createHash("sha256").update(keyInput).digest("hex");

  return hash;
}

async function d1Query(sql, params = []) {
  const res = await fetch(SAST_RECOMMEND_REPORT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ sql, params }),
  });

  const data = await res.json();

  if (!res.ok) {
    console.error(`D1 Error: ${data.errors?.[0]?.message || res.statusText}`);
    throw new Error(`D1 error: ${data.errors?.[0]?.message || res.statusText}`);
  }

  return data.result?.[0]?.results || [];
}

async function ensureTable() {
  await d1Query(`
    CREATE TABLE IF NOT EXISTS recommendations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cache_key TEXT UNIQUE,
      recommendation TEXT
    );
  `);
}

async function getAIRecommendation(finding, temperature = 0.0, maxRetries = 5) {
  await ensureTable();
  const cacheKey = makeCacheKey(finding);

  const rows = await d1Query(
    `SELECT recommendation FROM recommendations WHERE cache_key = ? LIMIT 1`,
    [cacheKey]
  );

  if (rows.length > 0 && rows[0].recommendation) {
    console.log(`Cache hit: ${finding.rule}`);
    return rows[0].recommendation;
  }

  console.log(`API call: ${finding.rule}`);

  const prompt = `
You are a senior DevSecOps assistant.
For the following security issue, provide a short, actionable remediation recommendation and a reference link if possible.

Rule: ${finding.rule}
Title: ${finding.title}
Description: ${finding.description}

Recommendation:
`;

  let lastError;
  let recommendation;

  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      const response = await openai.chat.completions.create({
        model: "deepseek-chat",
        messages: [{ role: "user", content: prompt }],
        temperature,
      });

      recommendation = response.choices[0].message.content.trim();

      await d1Query(
        `INSERT INTO recommendations (cache_key, recommendation) VALUES (?, ?) ON CONFLICT(cache_key) DO NOTHING`,
        [cacheKey, recommendation]
      );

      console.log(`Cached: ${finding.rule}`);
      return recommendation;
    } catch (err) {
      lastError = err;
      console.error(`API error (attempt ${attempt + 1}): ${err.message}`);

      if (err.status === 429) {
        const delay = Math.pow(2, attempt) * 1000 + Math.random() * 500;
        console.log(`Retrying in ${Math.floor(delay)}ms`);
        await new Promise((res) => setTimeout(res, delay));
      } else {
        break;
      }
    }
  }

  console.error(`Failed to get recommendation for: ${finding.rule}`);
  throw lastError;
}

module.exports = { getAIRecommendation };