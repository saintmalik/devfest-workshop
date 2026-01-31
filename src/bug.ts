// auth.ts - Authentication service with MULTIPLE security issues
import express, { Request, Response, NextFunction } from 'express';
import mysql from 'mysql';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { exec } from 'child_process';

const app = express();

// SECURITY ISSUE #1: Hardcoded secrets in code
const DB_PASSWORD: string = "MyP@ssw0rd123!";
const JWT_SECRET: string = "super-secret-jwt-key-12345";
const API_KEY: string = "sk-proj-abc123xyz789-OPENAI-KEY";
const AWS_SECRET: string = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
const STRIPE_KEY: string = "sk_live_51HqB2cK7v8N9oP1Q2r3S4t5U6v7W8x9Y0z1A2b3C4d5";
const PRIVATE_KEY: string = "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA0Z3VS...[truncated]";

// SECURITY ISSUE #2: SQL Injection vulnerability
const db = mysql.createConnection({
  host: 'localhost',
  user: 'root',
  password: DB_PASSWORD,
  database: 'userdb'
});

app.use(express.json());

// TypeScript interfaces (but still vulnerable code!)
interface User {
  id: number;
  username: string;
  password: string;
  email: string;
  role: string;
}

interface LoginRequest {
  username: string;
  password: string;
}

interface Session {
  [key: string]: string;
}

// SECURITY ISSUE #3: No input validation + SQL Injection
app.post('/login', (req: Request, res: Response) => {
  const { username, password } = req.body as LoginRequest;

  // SQL Injection vulnerable query - TypeScript doesn't prevent this!
  const query: string = `SELECT * FROM users WHERE username = '${username}' AND password = '${password}'`;

  db.query(query, (err: any, results: User[]) => {
    if (results && results.length > 0) {
      const token: string = jwt.sign({ user: username }, JWT_SECRET);
      res.json({ token: token });
    } else {
      res.status(401).send('Invalid credentials');
    }
  });
});

// SECURITY ISSUE #4: No authentication check + Type assertion abuse
app.get('/admin/users', (req: Request, res: Response) => {
  db.query('SELECT * FROM users', (err: any, results: any) => {
    res.json(results as User[]); // Exposes all user data including passwords
  });
});

// SECURITY ISSUE #5: Command Injection vulnerability
app.post('/backup', (req: Request, res: Response) => {
  const filename: string = req.body.filename;

  // Command injection vulnerable - TypeScript can't prevent OS command injection
  exec(`tar -czf backups/${filename}.tar.gz /var/data`, (error, stdout, stderr) => {
    if (error) {
      res.status(500).send('Backup failed');
    } else {
      res.send('Backup created');
    }
  });
});

// SECURITY ISSUE #6: Path Traversal vulnerability
app.get('/download', (req: Request, res: Response) => {
  const file: string = req.query.file as string;
  res.download(`/uploads/${file}`); // Can access any file: ../../../etc/passwd
});

// SECURITY ISSUE #7: XSS vulnerability
app.get('/search', (req: Request, res: Response) => {
  const searchTerm: string = req.query.q as string;
  res.send(`<h1>Search results for: ${searchTerm}</h1>`); // No sanitization
});

// SECURITY ISSUE #8: Insecure deserialization with any type
app.post('/process', (req: Request, res: Response) => {
  const data: any = req.body.data; // Using 'any' bypasses type safety
  const obj: any = eval('(' + data + ')'); // NEVER use eval!
  res.json(obj);
});

// SECURITY ISSUE #9: Weak cryptography
function hashPassword(password: string): string {
  return crypto.createHash('md5').update(password).digest('hex'); // MD5 is broken!
}

// SECURITY ISSUE #10: No rate limiting on sensitive endpoints
app.post('/reset-password', (req: Request, res: Response) => {
  const email: string = req.body.email;
  // Anyone can spam this endpoint
  const resetToken: string = Math.random().toString(36); // Weak token generation
  console.log(`Reset token for ${email}: ${resetToken}`);
  res.send('Password reset email sent');
});

// SECURITY ISSUE #11: Logging sensitive information
app.post('/payment', (req: Request, res: Response) => {
  console.log('Processing payment:', req.body); // Logs credit card data
  console.log('Stripe Key:', STRIPE_KEY);
  res.send('Payment processed');
});

// SECURITY ISSUE #12: CORS misconfiguration
app.use((req: Request, res: Response, next: NextFunction) => {
  res.header('Access-Control-Allow-Origin', '*'); // Allows any origin
  res.header('Access-Control-Allow-Headers', '*');
  next();
});

// SECURITY ISSUE #13: Debug mode enabled in production
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  console.error(err.stack); // Exposes stack traces
  res.status(500).send(err.stack); // Sends stack trace to client
});

// SECURITY ISSUE #14: Insecure session management
const sessions: Session = {}; // Stored in memory, will be lost on restart

app.post('/create-session', (req: Request, res: Response) => {
  const sessionId: string = Date.now().toString(); // Predictable session ID
  sessions[sessionId] = req.body.username;
  res.json({ sessionId });
});

// SECURITY ISSUE #15: Prototype pollution vulnerability
app.post('/merge-config', (req: Request, res: Response) => {
  const userConfig: any = req.body;
  const defaultConfig: any = { theme: 'light', language: 'en' };

  // Vulnerable merge function
  function merge(target: any, source: any): any {
    for (const key in source) {
      if (typeof source[key] === 'object') {
        target[key] = merge(target[key] || {}, source[key]);
      } else {
        target[key] = source[key];
      }
    }
    return target;
  }

  const config = merge(defaultConfig, userConfig);
  res.json(config);
});

// SECURITY ISSUE #16: Type coercion vulnerabilities
app.post('/update-user', (req: Request, res: Response) => {
  const userId: any = req.body.userId; // Should be number but accepts any
  const isAdmin: any = req.body.isAdmin; // Boolean check bypassed

  // Vulnerable comparison - can be bypassed with type coercion
  if (isAdmin == true) { // Using == instead of ===
    console.log('Granting admin access');
  }

  const query = `UPDATE users SET role = 'admin' WHERE id = ${userId}`; // SQL Injection + no validation
  db.query(query, (err: any) => {
    res.send('User updated');
  });
});

// SECURITY ISSUE #17: Race condition in concurrent requests
let requestCount: number = 0;
app.get('/counter', (req: Request, res: Response) => {
  requestCount++; // Not thread-safe
  setTimeout(() => {
    res.json({ count: requestCount });
  }, 100);
});

// SECURITY ISSUE #18: No HTTPS enforcement
const PORT: number = 80;
app.listen(PORT, () => {
  console.log(`Server running on HTTP (not HTTPS!) on port ${PORT}`);
  console.log('DB Password:', DB_PASSWORD);
  console.log('JWT Secret:', JWT_SECRET);
  console.log('API Keys loaded successfully');
});

// Additional hardcoded secrets for testing
const GITHUB_TOKEN: string = "ghp_1234567890abcdefghijklmnopqrstuvwxyz";
const SLACK_WEBHOOK: string = "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX";
const MONGODB_URI: string = "mongodb://admin:SuperSecret123@localhost:27017/mydb";
const SENDGRID_API_KEY: string = "SG.1234567890abcdefghijklmnopqrstuvwxyz";
const TWILIO_AUTH_TOKEN: string = "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6";
const FIREBASE_CONFIG = {
  apiKey: "AIzaSyD1234567890abcdefghijklmnopqrstuv",
  authDomain: "myapp.firebaseapp.com",
  projectId: "myapp-12345",
  storageBucket: "myapp-12345.appspot.com",
  messagingSenderId: "123456789012",
  appId: "1:123456789012:web:abcdef1234567890"
};

// SECURITY ISSUE #19: Regex DoS (ReDoS) vulnerability
app.get('/validate-email', (req: Request, res: Response) => {
  const email: string = req.query.email as string;
  const emailRegex = /^([a-zA-Z0-9_\.\-])+\@(([a-zA-Z0-9\-])+\.)+([a-zA-Z0-9]{2,4})+$/; // Vulnerable pattern

  if (emailRegex.test(email)) {
    res.send('Valid email');
  } else {
    res.send('Invalid email');
  }
});

// SECURITY ISSUE #20: XML External Entity (XXE) injection
import xml2js from 'xml2js';

app.post('/parse-xml', (req: Request, res: Response) => {
  const xmlData: string = req.body.xml;
  const parser = new xml2js.Parser(); // No security options set

  parser.parseString(xmlData, (err: any, result: any) => {
    res.json(result); // Can be exploited for XXE attacks
  });
});

export default app;