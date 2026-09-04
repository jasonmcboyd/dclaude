import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import sql from 'mssql';
import NodeSqlParser from 'node-sql-parser';

const { Parser } = NodeSqlParser;

const PORT = parseInt(process.env.SQL_MCP_PORT || '3100', 10);

// ---------------------------------------------------------------------------
// Connection string parsing — extract server and database for pool naming
// ---------------------------------------------------------------------------
function parseConnectionName(connStr) {
  const pairs = new Map();
  for (const part of connStr.split(';')) {
    const eq = part.indexOf('=');
    if (eq < 0) continue;
    pairs.set(part.slice(0, eq).trim().toLowerCase(), part.slice(eq + 1).trim());
  }
  const server = pairs.get('server') || pairs.get('data source') || 'unknown';
  const host = server.replace(/^tcp:/, '').split(',')[0].split('\\')[0];
  const db = pairs.get('database') || pairs.get('initial catalog') || '';
  return db ? `${host}/${db}` : host;
}

// ---------------------------------------------------------------------------
// Connection string → mssql config object
// ---------------------------------------------------------------------------
function parseConnectionConfig(connStr) {
  const pairs = new Map();
  for (const part of connStr.split(';')) {
    const eq = part.indexOf('=');
    if (eq < 0) continue;
    pairs.set(part.slice(0, eq).trim().toLowerCase(), part.slice(eq + 1).trim());
  }
  const raw = pairs.get('server') || pairs.get('data source') || 'localhost';
  const serverParts = raw.replace(/^tcp:/, '');
  const [hostAndInstance, portStr] = serverParts.split(',');
  const [host, instance] = hostAndInstance.split('\\');

  const config = {
    server: host,
    database: pairs.get('database') || pairs.get('initial catalog') || undefined,
    user: pairs.get('user id') || pairs.get('uid') || undefined,
    password: pairs.get('password') || pairs.get('pwd') || undefined,
    options: {
      encrypt: (pairs.get('encrypt') || 'false').toLowerCase() === 'true',
      trustServerCertificate: (pairs.get('trustservercertificate') || 'false').toLowerCase() === 'true',
    },
  };
  if (instance) config.options.instanceName = instance;
  if (portStr) config.port = parseInt(portStr, 10);
  if (pairs.has('integrated security') || pairs.has('trusted_connection')) {
    const val = (pairs.get('integrated security') || pairs.get('trusted_connection') || '').toLowerCase();
    if (val === 'true' || val === 'sspi' || val === 'yes') {
      config.options.trustedConnection = true;
      delete config.user;
      delete config.password;
    }
  }
  return config;
}

// ---------------------------------------------------------------------------
// Connection pools — one per SQL_CONN_{n} env var
// ---------------------------------------------------------------------------
const pools = new Map();

for (const [key, value] of Object.entries(process.env)) {
  if (!key.startsWith('SQL_CONN_')) continue;
  const name = parseConnectionName(value);
  try {
    const config = parseConnectionConfig(value);
    const pool = new sql.ConnectionPool(config);
    await pool.connect();
    pools.set(name, pool);
    console.log(`[sql-mcp] Connected: ${name}`);
  } catch (err) {
    console.error(`[sql-mcp] Failed to connect ${name}: ${err.message}`);
  }
}

if (pools.size === 0) {
  console.error('[sql-mcp] No database connections configured (set SQL_CONN_<name> env vars)');
  process.exit(1);
}

const availableNames = [...pools.keys()];

// ---------------------------------------------------------------------------
// SQL validation
// ---------------------------------------------------------------------------
const parser = new Parser();
const EXEC_RE = /\bEXEC(UTE)?\b/i;

function validateSelectOnly(rawSql) {
  if (EXEC_RE.test(rawSql)) {
    return 'EXEC/EXECUTE statements are not allowed. Only SELECT queries are permitted.';
  }
  try {
    const ast = parser.astify(rawSql, { database: 'TransactSQL' });
    const statements = Array.isArray(ast) ? ast : [ast];
    for (const stmt of statements) {
      if (stmt.type !== 'select') {
        return `${stmt.type.toUpperCase()} statements are not allowed. Only SELECT queries are permitted.`;
      }
    }
  } catch {
    return 'Failed to parse the SQL statement. Please simplify the query or check the syntax. Only SELECT queries are permitted.';
  }
  return null;
}

function getPool(name) {
  const pool = pools.get(name);
  if (!pool) {
    return { error: `Unknown database '${name}'. Available: ${availableNames.join(', ')}` };
  }
  return { pool };
}

// ---------------------------------------------------------------------------
// MCP Server
// ---------------------------------------------------------------------------
const mcpServer = new McpServer(
  { name: 'sql-mcp', version: '1.0.0' },
  { capabilities: { tools: {} } },
);

mcpServer.registerTool(
  'list-databases',
  {
    description: 'List the available database connection names.',
  },
  () => ({
    content: [{ type: 'text', text: JSON.stringify(availableNames, null, 2) }],
  }),
);

mcpServer.registerTool(
  'list-tables',
  {
    description: 'List tables and views in a database, optionally filtered by schema.',
    inputSchema: z.object({
      database: z.string().describe('Database connection name'),
      schema: z.string().optional().describe('Schema filter (e.g. dbo)'),
    }),
  },
  async ({ database, schema }) => {
    const result = getPool(database);
    if (result.error) return { content: [{ type: 'text', text: result.error }], isError: true };
    try {
      const request = result.pool.request();
      let query = 'SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE FROM INFORMATION_SCHEMA.TABLES';
      if (schema) {
        request.input('schema', sql.NVarChar, schema);
        query += ' WHERE TABLE_SCHEMA = @schema';
      }
      query += ' ORDER BY TABLE_SCHEMA, TABLE_NAME';
      const rows = await request.query(query);
      return { content: [{ type: 'text', text: JSON.stringify(rows.recordset, null, 2) }] };
    } catch (err) {
      return { content: [{ type: 'text', text: `SQL error: ${err.message}` }], isError: true };
    }
  },
);

mcpServer.registerTool(
  'describe-table',
  {
    description: 'Describe columns, types, and key constraints for a table.',
    inputSchema: z.object({
      database: z.string().describe('Database connection name'),
      schema: z.string().default('dbo').describe('Table schema (default: dbo)'),
      table: z.string().describe('Table name'),
    }),
  },
  async ({ database, schema, table }) => {
    const result = getPool(database);
    if (result.error) return { content: [{ type: 'text', text: result.error }], isError: true };
    try {
      const request = result.pool.request();
      request.input('schema', sql.NVarChar, schema);
      request.input('table', sql.NVarChar, table);
      const rows = await request.query(`
        SELECT
          c.COLUMN_NAME,
          c.DATA_TYPE,
          c.CHARACTER_MAXIMUM_LENGTH,
          c.NUMERIC_PRECISION,
          c.NUMERIC_SCALE,
          c.IS_NULLABLE,
          c.COLUMN_DEFAULT,
          (
            SELECT STRING_AGG(tc.CONSTRAINT_TYPE, ', ')
            FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
            JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
              ON kcu.CONSTRAINT_NAME = tc.CONSTRAINT_NAME
              AND kcu.TABLE_SCHEMA = tc.TABLE_SCHEMA
            WHERE kcu.TABLE_SCHEMA = c.TABLE_SCHEMA
              AND kcu.TABLE_NAME = c.TABLE_NAME
              AND kcu.COLUMN_NAME = c.COLUMN_NAME
          ) AS CONSTRAINTS
        FROM INFORMATION_SCHEMA.COLUMNS c
        WHERE c.TABLE_SCHEMA = @schema AND c.TABLE_NAME = @table
        ORDER BY c.ORDINAL_POSITION
      `);
      if (rows.recordset.length === 0) {
        return { content: [{ type: 'text', text: `Table [${schema}].[${table}] not found or has no columns.` }], isError: true };
      }
      return { content: [{ type: 'text', text: JSON.stringify(rows.recordset, null, 2) }] };
    } catch (err) {
      return { content: [{ type: 'text', text: `SQL error: ${err.message}` }], isError: true };
    }
  },
);

mcpServer.registerTool(
  'query',
  {
    description: 'Execute a read-only SQL query. Only SELECT statements are allowed. The query runs inside a transaction that is always rolled back.',
    inputSchema: z.object({
      database: z.string().describe('Database connection name'),
      sql: z.string().describe('SQL SELECT query to execute'),
    }),
  },
  async ({ database, sql: userSql }) => {
    const result = getPool(database);
    if (result.error) return { content: [{ type: 'text', text: result.error }], isError: true };

    const validationError = validateSelectOnly(userSql);
    if (validationError) {
      return { content: [{ type: 'text', text: validationError }], isError: true };
    }

    const transaction = new sql.Transaction(result.pool);
    try {
      await transaction.begin();
      const rows = await transaction.request().query(userSql);
      return { content: [{ type: 'text', text: JSON.stringify(rows.recordset, null, 2) }] };
    } catch (err) {
      return { content: [{ type: 'text', text: `SQL error: ${err.message}` }], isError: true };
    } finally {
      try { await transaction.rollback(); } catch { /* already rolled back or connection lost */ }
    }
  },
);

// ---------------------------------------------------------------------------
// HTTP server with MCP + health endpoint
// ---------------------------------------------------------------------------
const transports = new Map();

const httpServer = createServer(async (req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok' }));
    return;
  }

  if (req.url !== '/mcp') {
    res.writeHead(404);
    res.end('Not Found');
    return;
  }

  if (req.method === 'POST') {
    const sessionId = req.headers['mcp-session-id'];
    let transport;

    if (sessionId && transports.has(sessionId)) {
      transport = transports.get(sessionId);
    } else if (!sessionId) {
      transport = new StreamableHTTPServerTransport({
        sessionIdGenerator: () => randomUUID(),
        onsessioninitialized: (id) => {
          transports.set(id, transport);
        },
      });
      transport.onclose = () => {
        if (transport.sessionId) transports.delete(transport.sessionId);
      };
      await mcpServer.connect(transport);
    } else {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Invalid or expired session' }));
      return;
    }

    await transport.handleRequest(req, res);
    return;
  }

  if (req.method === 'GET') {
    const sessionId = req.headers['mcp-session-id'];
    if (sessionId && transports.has(sessionId)) {
      await transports.get(sessionId).handleRequest(req, res);
      return;
    }
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Session ID required for GET' }));
    return;
  }

  if (req.method === 'DELETE') {
    const sessionId = req.headers['mcp-session-id'];
    if (sessionId && transports.has(sessionId)) {
      await transports.get(sessionId).handleRequest(req, res);
      transports.delete(sessionId);
      return;
    }
    res.writeHead(404);
    res.end('Session not found');
    return;
  }

  res.writeHead(405);
  res.end('Method Not Allowed');
});

httpServer.listen(PORT, () => {
  console.log(`[sql-mcp] Listening on port ${PORT}`);
  console.log(`[sql-mcp] Databases: ${availableNames.join(', ')}`);
});

// ---------------------------------------------------------------------------
// Graceful shutdown
// ---------------------------------------------------------------------------
async function shutdown() {
  console.log('[sql-mcp] Shutting down...');
  for (const transport of transports.values()) {
    try { await transport.close(); } catch { /* best effort */ }
  }
  httpServer.close();
  for (const [name, pool] of pools) {
    try { await pool.close(); } catch { /* best effort */ }
    console.log(`[sql-mcp] Closed pool: ${name}`);
  }
  process.exit(0);
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
